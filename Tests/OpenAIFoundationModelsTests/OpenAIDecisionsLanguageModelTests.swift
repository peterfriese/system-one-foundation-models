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

    @Test("OpenAIDecisionsLanguageModel and OpenAILanguageModel typealias advertise guidedGeneration and vision")
    func testCapabilities() {
        let model: OpenAILanguageModel = OpenAIDecisionsLanguageModel(backend: MockSystemOneBackend())
        #expect(model.capabilities.contains(.guidedGeneration))
        #expect(model.capabilities.contains(.vision))

        let proxyURL = URL(string: "https://us-central1-myapp.cloudfunctions.net/openAIProxy")!
        let proxyModel1 = OpenAILanguageModel(
            proxyEndpoint: proxyURL,
            credential: .appCheck { "token-1" }
        )
        #expect(proxyModel1.executorConfiguration.endpoint.url == proxyURL)

        let proxyModel2 = OpenAILanguageModel(proxyEndpoint: proxyURL) { request in
            request.setValue("token-2", forHTTPHeaderField: "X-Firebase-AppCheck")
        }
        #expect(proxyModel2.executorConfiguration.endpoint.url == proxyURL)
    }

    @Test("OpenAIDecisionsLanguageModel supports PNG, JPEG, and WebP data attachments")
    func testSupportedDataAttachmentTypes() async throws {
        let model = OpenAIDecisionsLanguageModel(backend: MockSystemOneBackend())

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
        let supportsPDFDataEntry = try await model.supportsDataEntryType(.pdf)
        #expect(supportsDataEntry == true)
        #expect(supportsPDFDataEntry == false)
    }

    @Test("End-to-end: Evaluates @Generable struct via LanguageModelSession with MockSystemOneBackend")
    func testLanguageModelSessionEvaluation() async throws {
        let mockBackend = MockSystemOneBackend { _ in
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

    @Test("End-to-end: OpenAI 1-based @Guide(.range(1...5)) score answers are NOT shifted off-by-one (C4)")
    func testOpenAIOneBasedScoreRangeNotShiftedOffByOne() async throws {
        let backend = MockSystemOneBackend { _ in
            let wireResponse = OpenAIDecisionsResponse(
                id: "dec_1based",
                object: "decision",
                model: "gpt-6-luna",
                answers: [
                    OpenAIDecisionsAnswer(
                        name: "isApproved",
                        type: "predicate",
                        probability: 0.95,
                        confidence: 0.95
                    ),
                    OpenAIDecisionsAnswer(
                        name: "category",
                        type: "choice",
                        choice: "meals",
                        confidence: 0.91,
                        probabilities: [
                            .init(value: "meals", probability: 0.91),
                            .init(value: "travel", probability: 0.09)
                        ]
                    ),
                    OpenAIDecisionsAnswer(
                        name: "riskScore",
                        type: "score",
                        score: 3.0,
                        confidence: 0.85,
                        probabilities: [
                            .init(value: "1", probability: 0.02, label: "Level 1"),
                            .init(value: "2", probability: 0.05, label: "Level 2"),
                            .init(value: "3", probability: 0.85, label: "Level 3"),
                            .init(value: "4", probability: 0.05, label: "Level 4"),
                            .init(value: "5", probability: 0.03, label: "Level 5")
                        ]
                    )
                ],
                usage: .init(inputTokens: 48, outputTokens: 0)
            )
            return try OpenAIDecisionsPayloadAdapter.adaptResponse(
                wireResponse,
                transportDurationMs: 14.0,
                serverDurationMs: 10.0
            )
        }

        let session = LanguageModelSession(model: OpenAIDecisionsLanguageModel(backend: backend))
        let response = try await session.respond(to: "Team dinner receipt $142.50", generating: ExpenseAuditDecision.self)

        #expect(response.content.riskScore == 3)
        let scoreVal = try #require(response.scoreValue(for: "riskScore"))
        #expect(scoreVal.rounded == 3)
        #expect(abs(scoreVal.value - 3.0) < 0.0001)
        #expect(scoreVal.probabilities[3] == 0.85)
        #expect(scoreVal.legend[3] == "Level 3")
    }

    @Test("End-to-end: Evaluates @Generable struct with image attachment")
    func testLanguageModelSessionWithAttachment() async throws {
        let mockBackend = MockSystemOneBackend { request in
            let openAIReq = try OpenAIDecisionsPayloadAdapter.adaptRequest(request)
            if case .multimodal(let messages) = openAIReq.input {
                #expect(messages.count == 1)
                #expect(messages[0].content.count == 2)
            } else {
                Issue.record("Expected multimodal message payload for attachment")
            }
            return SystemOneResponse(
                model: "gpt-6-luna",
                answers: [
                    "isApproved": SystemOneAnswer(type: "noul", noul: 0.92, confidence: 0.92),
                    "category": SystemOneAnswer(type: "choice", choice: "meals", confidence: 0.90),
                    "riskScore": SystemOneAnswer(type: "score", score: 0.0, confidence: 0.88, probabilities: ["0": 0.88, "1": 0.12])
                ],
                usage: SystemOneUsage(inputTokens: 120, outputTokens: 0)
            )
        }
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
        #expect(response.content.riskScore == 1)
    }

    @available(*, deprecated)
    @Test("Deprecated MockOpenAIDecisionsBackend remains source-compatible and reset() clears custom handler")
    func testDeprecatedMockOpenAIDecisionsBackendCompatibility() async throws {
        try await verifyDeprecatedMockBackend()
    }

    @available(*, deprecated)
    private func verifyDeprecatedMockBackend() async throws {
        let mock = MockOpenAIDecisionsBackend { _ in
            throw SystemOneError.networkError("custom handler fail")
        }
        await #expect(throws: SystemOneError.self) {
            _ = try await mock.evaluate(request: SystemOneRequest(state: "S", questions: ["q": .noul(instructions: "I")]))
        }
        mock.reset()
        let fallback = try await mock.evaluate(request: SystemOneRequest(state: "S", questions: ["q": .noul(instructions: "I")]))
        #expect(fallback.answers["q"]?.noul == 0.95)
        #expect(mock.lastOpenAIRequest != nil)
    }

    @Test("OpenAIDecisionsExecutor rejects unstructured free-form text requests")
    func testStructuredOutputRequired() async throws {
        let model = OpenAIDecisionsLanguageModel(backend: MockSystemOneBackend())
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

    @Test("OpenAIDecisionsExecutor rejects absent answer array and throws decodingError instead of fabricating fallbacks")
    func testLanguageModelSessionWithAbsentAnswersThrows() async throws {
        let mockBackend = MockSystemOneBackend(
            fixedResponse: SystemOneResponse(
                model: "gpt-6-luna",
                answers: [:],
                usage: SystemOneUsage(inputTokens: 50, outputTokens: 0)
            )
        )

        let model = OpenAIDecisionsLanguageModel(backend: mockBackend)
        let session = LanguageModelSession(model: model)

        do {
            _ = try await session.respond(to: "Audit expense receipt", generating: ExpenseAuditDecision.self)
            Issue.record("Expected decodingError for absent answers")
        } catch let error as SystemOneError {
            if case .decodingError(let message) = error {
                #expect(message.contains("Missing answer for expected question"))
            } else {
                Issue.record("Expected .decodingError, got: \(error)")
            }
        }
    }

    @Test("OpenAIDecisionsExecutor rejects partial answer array and throws decodingError instead of fabricating fallbacks")
    func testLanguageModelSessionWithPartialAnswersThrows() async throws {
        let mockBackend = MockSystemOneBackend(
            fixedResponse: SystemOneResponse(
                model: "gpt-6-luna",
                answers: [
                    "isApproved": SystemOneAnswer(
                        type: "noul",
                        noul: 0.95,
                        confidence: 0.95
                    )
                ],
                usage: SystemOneUsage(inputTokens: 50, outputTokens: 0)
            )
        )

        let model = OpenAIDecisionsLanguageModel(backend: mockBackend)
        let session = LanguageModelSession(model: model)

        do {
            _ = try await session.respond(to: "Audit expense receipt", generating: ExpenseAuditDecision.self)
            Issue.record("Expected decodingError for partial answers")
        } catch let error as SystemOneError {
            if case .decodingError(let message) = error {
                #expect(message == "Missing answer for expected question 'category'")
            } else {
                Issue.record("Expected .decodingError, got: \(error)")
            }
        }
    }
}
