import Testing
import Foundation
import CoreGraphics
import UniformTypeIdentifiers
import FoundationModels
import SystemOneCore
@testable import OpenAIFoundationModels

// MARK: - Test @Generable Schemas

@Generable
enum AuditCategory: String, Sendable, CaseIterable {
    case travel
    case meals
    case software
    case equipment
}

@Generable
struct ExpenseAuditDecision: Sendable {
    @Guide(description: "Determine whether the submitted expense is approved for reimbursement.")
    var isApproved: Bool

    @Guide(description: "Select the accounting category for the expense.")
    var category: AuditCategory

    @Guide(description: "Rate the policy compliance risk from 1 (low risk) to 5 (high risk).", .range(1...5))
    var riskScore: Int
}

// MARK: - Test Suite

@Suite("OpenAI Decisions Language Model Tests")
struct OpenAIDecisionsLanguageModelTests {

    @Test("OpenAIDecisionsLanguageModel capabilities advertise guidedGeneration and vision")
    func testCapabilities() {
        let model = OpenAIDecisionsLanguageModel(backend: MockOpenAIDecisionsBackend())
        #expect(model.capabilities.contains(.guidedGeneration))
        #expect(model.capabilities.contains(.vision))
    }

    @Test("OpenAIDecisionsLanguageModel supports PNG, JPEG, and WebP data attachments")
    func testSupportedDataAttachmentTypes() async throws {
        let model = OpenAIDecisionsLanguageModel(backend: MockOpenAIDecisionsBackend())

        let supportsPNG = try await model.supportsDataAttachmentType(.png)
        let supportsJPEG = try await model.supportsDataAttachmentType(.jpeg)
        let supportsWebP = try await model.supportsDataAttachmentType(.webP)
        let supportsPDF = try await model.supportsDataAttachmentType(.pdf)
        let supportsText = try await model.supportsDataAttachmentType(.plainText)

        #expect(supportsPNG == true)
        #expect(supportsJPEG == true)
        #expect(supportsWebP == true)
        #expect(supportsPDF == false)
        #expect(supportsText == false)

        let supportsDataEntry = try await model.supportsDataEntryType(.png)
        #expect(supportsDataEntry == false)
    }

    @Test("End-to-end: Evaluates @Generable struct via LanguageModelSession with MockOpenAIDecisionsBackend")
    func testLanguageModelSessionEvaluation() async throws {
        let mockBackend = MockOpenAIDecisionsBackend { request in
            let answers: [String: SystemOneAnswer] = [
                "isApproved": SystemOneAnswer(
                    type: "noul",
                    noul: 0.94,
                    confidence: 0.94,
                    probabilities: ["true": 0.94, "false": 0.06]
                ),
                "category": SystemOneAnswer(
                    type: "choice",
                    choice: "software",
                    confidence: 0.92,
                    probabilities: ["software": 0.92, "travel": 0.05, "meals": 0.03]
                ),
                "riskScore": SystemOneAnswer(
                    type: "score",
                    score: 0.0,
                    confidence: 0.90,
                    probabilities: ["0": 0.90, "1": 0.08, "2": 0.02],
                    legend: ["0": "Level 1", "1": "Level 2", "2": "Level 3", "3": "Level 4", "4": "Level 5"]
                )
            ]
            return SystemOneResponse(
                model: "gpt-6-luna",
                answers: answers,
                usage: SystemOneUsage(inputTokens: 85, outputTokens: 0),
                serverDurationMs: 12.5,
                transportDurationMs: 16.0
            )
        }

        let model = OpenAIDecisionsLanguageModel(backend: mockBackend)
        let session = LanguageModelSession(model: model)

        let prompt = "Annual GitHub Enterprise subscription renewal invoice for Engineering team"
        let response = try await session.respond(to: prompt, generating: ExpenseAuditDecision.self)

        // Verify strongly typed decoded struct
        #expect(response.content.isApproved == true)
        #expect(response.content.category == .software)
        #expect(response.content.riskScore == 1)

        // Verify calibrated probabilities and confidence
        let approvalProb = response.probability(for: "isApproved")
        #expect(approvalProb == 0.94)

        let catConf = response.confidence(for: "category")
        #expect(catConf == 0.92)

        let riskVal = response.scoreValue(for: "riskScore")
        #expect(riskVal?.rounded == 1)
        #expect(riskVal?.confidence == 0.90)

        // Verify zero output token usage
        #expect(response.usage.output.totalTokenCount == 0)
        #expect(response.usage.input.totalTokenCount == 85)

        // Verify metadata
        let modelMeta = try? response.metadata["model"]?.value(String.self)
        #expect(modelMeta == "gpt-6-luna")
        let outputTokensMeta = try? response.metadata["output_tokens"]?.value(String.self)
        #expect(outputTokensMeta == "0")

        // Operational confidence routing verification
        let policy = RoutingPolicy(escalateBelow: 0.60, autoAtOrAbove: 0.85)
        let judgement = policy.decideNoul(response, of: "isApproved")
        #expect(judgement.decision == .auto)
        #expect(judgement.answer == true)
    }

    @Test("End-to-end: Evaluates @Generable struct with image attachment")
    func testLanguageModelSessionWithAttachment() async throws {
        let mockBackend = MockOpenAIDecisionsBackend()
        let model = OpenAIDecisionsLanguageModel(backend: mockBackend)
        let session = LanguageModelSession(model: model)

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let ctx = CGContext(
            data: nil,
            width: 16,
            height: 16,
            bitsPerComponent: 8,
            bytesPerRow: 64,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        let cgImage = ctx.makeImage()!

        let prompt = Prompt {
            "Inspect receipt photo"
            Attachment(cgImage)
        }

        let response = try await session.respond(to: prompt, generating: ExpenseAuditDecision.self)

        #expect(response.content.isApproved == true)
        #expect(mockBackend.lastOpenAIRequest != nil)
        if case .multimodal(let messages) = mockBackend.lastOpenAIRequest?.input {
            #expect(messages.count == 1)
            #expect(messages[0].content.count == 2)
        } else {
            Issue.record("Expected multimodal message payload for attachment")
        }
    }

    @Test("OpenAIDecisionsExecutor rejects unstructured free-form text requests")
    func testStructuredOutputRequired() async throws {
        let model = OpenAIDecisionsLanguageModel(backend: MockOpenAIDecisionsBackend())
        let session = LanguageModelSession(model: model)

        do {
            _ = try await session.respond(to: "Tell me a story about Luna.")
            Issue.record("Expected structuredOutputRequired for unguided generation")
        } catch let error as SystemOneError {
            if case .structuredOutputRequired = error {
                // Expected
            } else {
                Issue.record("Expected .structuredOutputRequired, got: \(error)")
            }
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }
}
