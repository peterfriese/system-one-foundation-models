import Testing
import Foundation
import CoreGraphics
import UniformTypeIdentifiers
import FoundationModels
import SystemOneCore
@testable import GeminiFoundationModels

// MARK: - Test @Generable Schemas

@Generable
enum GeminiAuditCategory: String, Sendable, CaseIterable, Choosable {
    case travel
    case meals
    case software
    case equipment
}

@Generable
struct GeminiExpenseAuditDecision: Sendable {
    @Guide(description: "Determine whether the submitted expense is approved for reimbursement.")
    var isApproved: Bool

    @Guide(description: "Select the accounting category for the expense.")
    var category: GeminiAuditCategory

    @Guide(description: "Rate the policy compliance risk from 1 (low risk) to 5 (high risk).", .range(1...5))
    var riskScore: Int
}

// MARK: - Test Suite

@Suite("Google Gemini Decisions Language Model Tests")
struct GeminiDecisionsLanguageModelTests {

    @Test("GeminiDecisionsLanguageModel and GeminiLanguageModel typealias advertise guidedGeneration and vision")
    func testCapabilities() {
        let model: GeminiLanguageModel = GeminiDecisionsLanguageModel(backend: MockGeminiDecisionsBackend())
        #expect(model.capabilities.contains(.guidedGeneration))
        #expect(model.capabilities.contains(.vision))
    }

    @Test("GeminiDecisionsLanguageModel supports PNG, JPEG, and WebP data attachments")
    func testSupportedDataAttachmentTypes() async throws {
        let model = GeminiDecisionsLanguageModel(backend: MockGeminiDecisionsBackend())

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

    @Test("End-to-end: Evaluates @Generable struct via LanguageModelSession with MockGeminiDecisionsBackend")
    func testLanguageModelSessionEvaluation() async throws {
        let mockBackend = MockGeminiDecisionsBackend { _ in
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
                model: "gemini-decision-1",
                answers: answers,
                usage: SystemOneUsage(inputTokens: 85, outputTokens: 0),
                serverDurationMs: 12.5,
                transportDurationMs: 16.0
            )
        }

        let model = GeminiDecisionsLanguageModel(backend: mockBackend)
        let session = LanguageModelSession(model: model)

        let prompt = "Annual GitHub Enterprise subscription renewal invoice for Engineering team"
        let response = try await session.respond(to: prompt, generating: GeminiExpenseAuditDecision.self)

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
        #expect(modelMeta == "gemini-decision-1")
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
        let mockBackend = MockGeminiDecisionsBackend()
        let model = GeminiDecisionsLanguageModel(backend: mockBackend)
        let session = LanguageModelSession(model: model)

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let ctx = try #require(CGContext(
            data: nil,
            width: 16,
            height: 16,
            bitsPerComponent: 8,
            bytesPerRow: 64,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        let cgImage = try #require(ctx.makeImage())

        let prompt = Prompt {
            "Inspect receipt photo"
            Attachment(cgImage)
        }

        let response = try await session.respond(to: prompt, generating: GeminiExpenseAuditDecision.self)

        #expect(response.content.isApproved == true)
        #expect(mockBackend.lastGeminiRequest != nil)
        if case .multimodal(let items) = mockBackend.lastGeminiRequest?.input {
            #expect(items.count == 2)
            if case .text(let t) = items[0] {
                #expect(t.contains("Inspect receipt photo"))
            } else {
                Issue.record("Expected text ContentItem at index 0")
            }
            if case .image(let mimeType, let b64) = items[1] {
                #expect(mimeType == "image/jpeg" || mimeType == "image/png")
                #expect(!b64.isEmpty)
            } else {
                Issue.record("Expected image ContentItem at index 1")
            }
        } else {
            Issue.record("Expected multimodal ContentItem payload for attachment")
        }
    }

    @Test("Ergonomic shortcuts: session.probability, session.choice, and session.score work with GeminiLanguageModel")
    func testErgonomicShortcuts() async throws {
        let mockBackend = MockGeminiDecisionsBackend()
        let model = GeminiLanguageModel(backend: mockBackend)
        let session = LanguageModelSession(model: model)

        let prob = try await session.probability(
            of: "Is this expense policy-compliant?",
            state: "Lunch receipt for $24.50"
        )
        #expect(prob == 0.95)

        let choiceResult = try await session.choice(
            "Select expense category",
            from: GeminiAuditCategory.self,
            state: "Flight ticket to WWDC"
        )
        #expect(choiceResult.confidence == 0.95)

        let scoreResult = try await session.score(
            "Rate compliance risk",
            levels: ["Low", "Medium", "High"],
            state: "Standard software subscription"
        )
        #expect(scoreResult.confidence == 0.95)
        #expect(scoreResult.levels == ["Low", "Medium", "High"])
    }

    @Test("GeminiDecisionsExecutor rejects unstructured free-form text requests")
    func testStructuredOutputRequired() async throws {
        let model = GeminiDecisionsLanguageModel(backend: MockGeminiDecisionsBackend())
        let session = LanguageModelSession(model: model)

        do {
            _ = try await session.respond(to: "Tell me a story about Gemini.")
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

    @Test("GeminiDecisionsExecutor rejects absent or partial answers and throws decodingError")
    func testLanguageModelSessionWithPartialAnswersThrows() async throws {
        let mockBackend = MockGeminiDecisionsBackend { _ in
            let partialAnswers: [String: SystemOneAnswer] = [
                "isApproved": SystemOneAnswer(
                    type: "noul",
                    noul: 0.95,
                    confidence: 0.95
                )
            ]
            return SystemOneResponse(
                model: "gemini-decision-1",
                answers: partialAnswers,
                usage: SystemOneUsage(inputTokens: 50, outputTokens: 0)
            )
        }

        let model = GeminiDecisionsLanguageModel(backend: mockBackend)
        let session = LanguageModelSession(model: model)

        do {
            _ = try await session.respond(to: "Audit expense receipt", generating: GeminiExpenseAuditDecision.self)
            Issue.record("Expected decodingError for partial answers")
        } catch let error as SystemOneError {
            if case .decodingError(let message) = error {
                #expect(message == "Missing answer for expected question 'category'")
            } else {
                Issue.record("Expected .decodingError, got: \(error)")
            }
        }
    }

    // MARK: - Live API Integration Test

    @Test(
        "Live Google Gemini Decisions API integration test (runs when RUN_LIVE_GEMINI_TESTS=1)",
        .enabled(if: ProcessInfo.processInfo.environment["RUN_LIVE_GEMINI_TESTS"] == "1" || ProcessInfo.processInfo.environment["RUN_LIVE_API_TESTS"] == "1")
    )
    func testLiveGeminiDecisionsAPIIntegration() async throws {
        let apiKey: String? = {
            if let envKey = ProcessInfo.processInfo.environment["GEMINI_API_KEY"],
               !envKey.isEmpty,
               !envKey.lowercased().hasPrefix("your_") {
                return envKey
            }
            if let envKey = ProcessInfo.processInfo.environment["GOOGLE_API_KEY"],
               !envKey.isEmpty,
               !envKey.lowercased().hasPrefix("your_") {
                return envKey
            }
            let envURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent(".env")
            guard let contents = try? String(contentsOf: envURL, encoding: .utf8) else { return nil }
            for line in contents.components(separatedBy: .newlines) {
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.hasPrefix("#") || trimmed.isEmpty { continue }
                let parts = trimmed.split(separator: "=", maxSplits: 1).map(String.init)
                if parts.count == 2 {
                    let keyName = parts[0].trimmingCharacters(in: .whitespaces)
                    if keyName == "GEMINI_API_KEY" || keyName == "GOOGLE_API_KEY" {
                        var val = parts[1].trimmingCharacters(in: .whitespaces)
                        if (val.hasPrefix("\"") && val.hasSuffix("\"")) || (val.hasPrefix("'") && val.hasSuffix("'")) {
                            val = String(val.dropFirst().dropLast())
                        }
                        if !val.isEmpty && !val.lowercased().hasPrefix("your_") {
                            return val
                        }
                    }
                }
            }
            return nil
        }()

        guard let key = apiKey else {
            // Live key not present, skip live call
            return
        }

        let model = GeminiDecisionsLanguageModel(apiKey: key)
        let session = LanguageModelSession(model: model)

        let prompt = "Annual GitHub Enterprise subscription renewal invoice ($1,200) for the core engineering team, pre-approved by VP of Engineering."
        let response = try await session.respond(to: prompt, generating: GeminiExpenseAuditDecision.self)

        #expect(response.content.isApproved == true)
        #expect(response.content.category == .software)
        #expect((1...5).contains(response.content.riskScore))
        #expect(response.usage.input.totalTokenCount > 0)
        #expect(response.usage.output.totalTokenCount == 0)

        // Live multimodal image test against https://generativelanguage.googleapis.com/v1beta/decisions
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let ctx = try #require(CGContext(
            data: nil,
            width: 16,
            height: 16,
            bitsPerComponent: 8,
            bytesPerRow: 64,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        let cgImage = try #require(ctx.makeImage())

        let multimodalSession = LanguageModelSession(model: model)
        let multimodalPrompt = Prompt {
            "Receipt photo for annual GitHub Enterprise software license ($1,200) for the engineering team, approved by VP."
            Attachment(cgImage)
        }
        let multimodalResponse = try await multimodalSession.respond(
            to: multimodalPrompt,
            generating: GeminiExpenseAuditDecision.self
        )

        #expect(multimodalResponse.content.category == .software)
        #expect((1...5).contains(multimodalResponse.content.riskScore))
        #expect(multimodalResponse.usage.input.totalTokenCount > 0)
        #expect(multimodalResponse.usage.output.totalTokenCount == 0)
    }
}
