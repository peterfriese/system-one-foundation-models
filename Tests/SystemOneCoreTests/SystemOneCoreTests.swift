import Testing
import Foundation
import FoundationModels
import UniformTypeIdentifiers
@testable import SystemOneCore

@Suite("SystemOneCore Unit & Pluggable Backend Tests")
struct SystemOneCoreTests {

    @Generable
    enum BugSeverity: String, Sendable {
        case critical
        case major
        case minor
    }

    @Generable
    struct BugReportDecision: Sendable {
        @Guide(description: "Is this bug security sensitive?")
        var isSecuritySensitive: Bool

        @Guide(description: "Severity level of this issue")
        var severity: BugSeverity

        @Guide(description: "Priority rating from 0 to 4", .range(0...4))
        var priority: Int
    }

    @Generable
    struct SubRouting: Sendable {
        var needsPagerDuty: Bool
    }

    @Generable
    struct OptionalFieldsDecision: Sendable {
        var isBlocking: Bool
        var optionalSeverity: BugSeverity?
        var optionalSubRouting: SubRouting?
    }

    @Test("SystemOneRequest and SystemOneResponse round-trip encoding matches protocol specification")
    func testSystemOneDTORoundTrip() throws {
        let request = SystemOneRequest(
            state: "Database connection leaking memory on pool worker #4",
            model: "systemone-fast",
            questions: [
                "isSecurity": .noul(instructions: "Is this a security vulnerability?"),
                "severity": .choice(
                    instructions: "What is the severity?",
                    criteria: ["critical": "Immediate outage", "minor": "Cosmetic issue"]
                ),
                "priority": .score(
                    instructions: "Priority score",
                    criteria: ["P0", "P1", "P2"]
                )
            ]
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(request)
        let json = try #require(String(data: data, encoding: .utf8))

        #expect(json.contains("\"type\":\"noul\""))
        #expect(json.contains("\"type\":\"choice\""))
        #expect(json.contains("\"type\":\"score\""))
        #expect(json.contains("\"model\":\"systemone-fast\""))

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(SystemOneRequest.self, from: data)
        #expect(decoded == request)
    }

    @Test("MockSystemOneBackend enables pluggable execution with SystemOneLanguageModel")
    func testMockSystemOneBackendExecution() async throws {
        let mockBackend = MockSystemOneBackend { request in
            #expect(request.questions.count == 3)
            #expect(request.state.contains("Memory leak detected"))

            return SystemOneResponse(
                model: "systemone-mock-v1",
                answers: [
                    "isSecuritySensitive": SystemOneAnswer(
                        type: "noul",
                        noul: 0.92,
                        confidence: 0.84,
                        probabilities: ["true": 0.92, "false": 0.08]
                    ),
                    "severity": SystemOneAnswer(
                        type: "choice",
                        choice: "critical",
                        confidence: 0.96,
                        probabilities: ["critical": 0.96, "major": 0.03, "minor": 0.01]
                    ),
                    "priority": SystemOneAnswer(
                        type: "score",
                        score: 4.0,
                        confidence: 0.90
                    )
                ],
                usage: SystemOneUsage(inputTokens: 140, outputTokens: 12),
                serverDurationMs: 24.5
            )
        }

        let model = SystemOneLanguageModel(backend: mockBackend, modelID: "systemone-mock-v1")
        let session = LanguageModelSession(model: model)

        let response = try await session.respond(
            to: "Alert: Memory leak detected in auth service worker",
            generating: BugReportDecision.self
        )

        #expect(response.content.isSecuritySensitive == true)
        #expect(response.content.severity == .critical)
        #expect(response.content.priority == 4)
        #expect(response.probability(for: "isSecuritySensitive") == 0.92)
        #expect(response.confidence(for: "severity") == 0.96)
        #expect(response.serverDurationMs == 24.5)
        #expect(response.usage.input.totalTokenCount == 140)
    }

    @Test("ResponseSynthesizer omits unanswered optional enum and optional nested struct keys so they decode to nil")
    func testOptionalEnumAndNestedStructSynthesizeToNilWhenUnanswered() async throws {
        let mockBackend = MockSystemOneBackend { _ in
            SystemOneResponse(
                model: "systemone-mock-v1",
                answers: [
                    "isBlocking": SystemOneAnswer(type: "noul", noul: 0.88, confidence: 0.88)
                ]
            )
        }

        let session = LanguageModelSession(model: SystemOneLanguageModel(backend: mockBackend))
        let response = try await session.respond(to: "Minor UI alignment issue", generating: OptionalFieldsDecision.self)

        #expect(response.content.isBlocking == true)
        #expect(response.content.optionalSeverity == nil)
        #expect(response.content.optionalSubRouting == nil)
    }

    @Test("SchemaTranslator rejects huge discrete integer score ranges (> 32 levels) and inverted bounds")
    func testSchemaTranslatorRejectsUnboundedOrInvertedScoreRanges() throws {
        let translator = SchemaTranslator()

        let hugeRangeSchema: [String: Any] = [
            "type": "object",
            "properties": [
                "badScore": [
                    "type": "integer",
                    "minimum": 0,
                    "maximum": 10_000_000
                ]
            ]
        ]
        #expect(throws: SystemOneError.self) {
            try translator.translate(json: hugeRangeSchema)
        }

        let invertedSchema: [String: Any] = [
            "type": "object",
            "properties": [
                "inverted": [
                    "type": "integer",
                    "minimum": 10,
                    "maximum": 2
                ]
            ]
        ]
        #expect(throws: SystemOneError.self) {
            try translator.translate(json: invertedSchema)
        }
    }

    @Test("SchemaTranslator resolves root $ref, merges multi-const anyOf variants, and rejects empty nested objects")
    func testSchemaTranslatorRootRefMultiConstAndEmptyNested() throws {
        let translator = SchemaTranslator()

        let rootRefAndConstSchema: [String: Any] = [
            "$ref": "#/$defs/RootObj",
            "$defs": [
                "RootObj": [
                    "type": "object",
                    "properties": [
                        "tier": [
                            "anyOf": [
                                ["type": "null"],
                                ["type": "string", "const": "gold"],
                                ["type": "string", "const": "silver"]
                            ]
                        ]
                    ]
                ]
            ]
        ]
        let translated = try translator.translate(json: rootRefAndConstSchema)
        if case .choice(_, let criteria) = translated.questions["tier"] {
            #expect(criteria["gold"] == "gold")
            #expect(criteria["silver"] == "silver")
        } else {
            Issue.record("Expected merged choice question for multi-const anyOf")
        }

        let emptyNestedSchema: [String: Any] = [
            "type": "object",
            "properties": [
                "emptyChild": [
                    "type": "object",
                    "properties": [String: Any]()
                ]
            ]
        ]
        #expect(throws: SystemOneError.self) {
            try translator.translate(json: emptyNestedSchema)
        }
    }

    @Test("Vision-configured SystemOneLanguageModel advertises vision capability and image attachment/entry support")
    func testVisionConfiguredSystemOneLanguageModel() async throws {
        let backend = MockSystemOneBackend()
        let textOnly = SystemOneLanguageModel(backend: backend, supportsVision: false)
        #expect(!textOnly.capabilities.contains(.vision))
        #expect(try await textOnly.supportsDataAttachmentType(.jpeg) == false)
        #expect(try await textOnly.supportsDataEntryType(.jpeg) == false)

        let multimodal = SystemOneLanguageModel(backend: backend, supportsVision: true)
        #expect(multimodal.capabilities.contains(.vision))
        #expect(try await multimodal.supportsDataAttachmentType(.jpeg) == true)
        #expect(try await multimodal.supportsDataEntryType(.png) == true)
        #expect(try await multimodal.supportsDataEntryType(.pdf) == false)
    }

    @Test("AnySystemOneBackend wraps custom backend cleanly with Hashable conformance")
    func testAnySystemOneBackendWrapping() async throws {
        let backend = MockSystemOneBackend { _ in
            SystemOneResponse(model: "test", answers: [:])
        }
        let anyBackend1 = AnySystemOneBackend(backend)
        let anyBackend2 = AnySystemOneBackend(backend)

        #expect(anyBackend1 != anyBackend2)
        #expect(anyBackend1 == anyBackend1)

        var set = Set<AnySystemOneBackend>()
        set.insert(anyBackend1)
        #expect(set.contains(anyBackend1))
    }
}
