import Testing
import Foundation
import FoundationModels
@testable import SystemOneCore

@Suite("System One Ergonomic Shortcuts & Dynamic Decision Schemas")
struct ErgonomicShortcutTests {

    // MARK: - Choosable Types

    enum TicketPriority: String, Choosable {
        case critical = "CRITICAL"
        case high = "HIGH"
        case normal = "NORMAL"
        case low = "LOW"

        var optionDescription: String? {
            switch self {
            case .critical: "Outage affecting all users"
            case .high: "Core workflow degraded"
            case .normal: "Standard request"
            case .low: "Minor cosmetic issue"
            }
        }
    }

    enum ServiceTier: Choosable {
        case premium
        case standard
        case free
    }

    // MARK: - Choosable Protocol Tests

    @Test("Choosable defaults conform to string raw values or description")
    func testChoosableProtocolDefaults() {
        #expect(TicketPriority.critical.optionIdentifier == "CRITICAL")
        #expect(TicketPriority.critical.optionDescription == "Outage affecting all users")

        #expect(ServiceTier.premium.optionIdentifier == "premium")
        #expect(ServiceTier.premium.optionDescription == nil)
    }

    // MARK: - Probability Shortcut Tests

    @Test(".probability(of:state:) evaluates truth probability using MockSystemOneBackend")
    func testProbabilityShortcut() async throws {
        let mockBackend = MockSystemOneBackend { request in
            #expect(request.questions.count == 1)
            let question = try #require(request.questions["decision"])
            if case .noul(let instructions) = question {
                #expect(instructions.contains("Is this database connection leaking memory?"))
            } else {
                Issue.record("Expected noul question")
            }

            return SystemOneResponse(
                model: "systemone-mock-v1",
                answers: [
                    "decision": SystemOneAnswer(
                        type: "noul",
                        noul: 0.94,
                        confidence: 0.88,
                        probabilities: ["true": 0.94, "false": 0.06]
                    )
                ]
            )
        }

        let model = SystemOneLanguageModel(backend: mockBackend, modelID: "systemone-mock-v1")
        let session = LanguageModelSession(model: model)

        let prob = try await session.probability(
            of: "Is this database connection leaking memory?",
            state: "Worker pool thread #4 holding 1.2 GB unreleased allocations."
        )

        #expect(prob == 0.94)
    }

    @Test(".probability(of:state:criteria:) includes qualifications in schema instructions")
    func testProbabilityWithCriteria() async throws {
        let mockBackend = MockSystemOneBackend { request in
            let question = try #require(request.questions["decision"])
            if case .noul(let instructions) = question {
                #expect(instructions.contains("True if: allocations grow continuously"))
                #expect(instructions.contains("False if: steady state memory usage"))
            } else {
                Issue.record("Expected noul question")
            }

            return SystemOneResponse(
                model: "systemone-mock-v1",
                answers: [
                    "decision": SystemOneAnswer(
                        type: "noul",
                        noul: 0.12,
                        confidence: 0.85,
                        probabilities: ["true": 0.12, "false": 0.88]
                    )
                ]
            )
        }

        let model = SystemOneLanguageModel(backend: mockBackend, modelID: "systemone-mock-v1")
        let session = LanguageModelSession(model: model)

        let prob = try await session.probability(
            of: "Is this memory leak active?",
            state: "Heap stable at 45MB over 24 hours.",
            criteria: (
                whenTrue: "allocations grow continuously",
                whenFalse: "steady state memory usage"
            )
        )

        #expect(prob == 0.12)
    }

    // MARK: - Choosable Enum Choice Shortcut Tests

    @Test(".choice(_:from:state:) evaluates Choosable enum and returns Choice with distribution")
    func testChoiceFromChoosableEnum() async throws {
        let mockBackend = MockSystemOneBackend { request in
            let question = try #require(request.questions["choice"])
            if case .choice(let instructions, let criteria) = question {
                #expect(instructions.contains("Triage incoming issue"))
                #expect(criteria.keys.contains("CRITICAL"))
                #expect(criteria.keys.contains("HIGH"))
                #expect(criteria.keys.contains("NORMAL"))
                #expect(criteria.keys.contains("LOW"))
            } else {
                Issue.record("Expected choice question")
            }

            return SystemOneResponse(
                model: "systemone-mock-v1",
                answers: [
                    "choice": SystemOneAnswer(
                        type: "choice",
                        choice: "CRITICAL",
                        confidence: 0.96,
                        probabilities: [
                            "CRITICAL": 0.96,
                            "HIGH": 0.03,
                            "NORMAL": 0.01,
                            "LOW": 0.00
                        ]
                    )
                ]
            )
        }

        let model = SystemOneLanguageModel(backend: mockBackend, modelID: "systemone-mock-v1")
        let session = LanguageModelSession(model: model)

        let choice = try await session.choice(
            "Triage incoming issue priority",
            from: TicketPriority.self,
            state: "Authentication microservice returning 500 across all regions"
        )

        #expect(choice.value == .critical)
        #expect(choice.confidence == 0.96)
        #expect(choice.probability(of: .critical) == 0.96)
        #expect(choice.probability(of: .high) == 0.03)
        #expect(choice.probability(of: .low) == 0.00)
    }

    // MARK: - Dynamic String Choice Shortcut Tests

    @Test(".choice(_:options:state:) evaluates dynamic string options")
    func testChoiceFromDynamicOptions() async throws {
        let options = ["Billing Support", "Technical Escalation", "General Inquiry"]

        let mockBackend = MockSystemOneBackend { request in
            let question = try #require(request.questions["choice"])
            if case .choice(let instructions, let criteria) = question {
                #expect(instructions.contains("Route support ticket"))
                for opt in options {
                    #expect(criteria.keys.contains(opt))
                }
            } else {
                Issue.record("Expected choice question")
            }

            return SystemOneResponse(
                model: "systemone-mock-v1",
                answers: [
                    "choice": SystemOneAnswer(
                        type: "choice",
                        choice: "Technical Escalation",
                        confidence: 0.91,
                        probabilities: [
                            "Technical Escalation": 0.91,
                            "Billing Support": 0.07,
                            "General Inquiry": 0.02
                        ]
                    )
                ]
            )
        }

        let model = SystemOneLanguageModel(backend: mockBackend, modelID: "systemone-mock-v1")
        let session = LanguageModelSession(model: model)

        let choice = try await session.choice(
            "Route support ticket",
            options: options,
            state: "Customer database corrupted following storage volume unmount"
        )

        #expect(choice.value == "Technical Escalation")
        #expect(choice.confidence == 0.91)
        #expect(choice.probability(of: "Technical Escalation") == 0.91)
        #expect(choice.probability(of: "Billing Support") == 0.07)
        #expect(choice.probability(of: "Unknown") == 0.0)
    }

    // MARK: - Score Shortcut Tests

    @Test(".score(_:levels:state:) evaluates rubric levels and produces weighted ScoreResult")
    func testScoreShortcut() async throws {
        let levels = [
            "P0 - Outage",
            "P1 - Severe Degradation",
            "P2 - Moderate Impact",
            "P3 - Minor Issue"
        ]

        let mockBackend = MockSystemOneBackend { request in
            let question = try #require(request.questions["score"])
            if case .score(let instructions, _) = question {
                #expect(instructions.contains("Rate incident severity"))
            } else {
                Issue.record("Expected score question")
            }

            return SystemOneResponse(
                model: "systemone-mock-v1",
                answers: [
                    "score": SystemOneAnswer(
                        type: "score",
                        score: 1.8,
                        confidence: 0.89,
                        probabilities: [
                            "0": 0.05,
                            "1": 0.25,
                            "2": 0.60,
                            "3": 0.10
                        ]
                    )
                ]
            )
        }

        let model = SystemOneLanguageModel(backend: mockBackend, modelID: "systemone-mock-v1")
        let session = LanguageModelSession(model: model)

        let scoreResult = try await session.score(
            "Rate incident severity",
            levels: levels,
            state: "API latency spiked to 450ms for 3% of users during cache warming"
        )

        #expect(scoreResult.value == 1.8)
        #expect(scoreResult.confidence == 0.89)
        #expect(scoreResult.mostLikelyIndex == 2)
        #expect(scoreResult.mostLikelyLevel == "P2 - Moderate Impact")
        #expect(scoreResult.probabilities == [0.05, 0.25, 0.60, 0.10])
        #expect(scoreResult.levels == levels)
    }

    // MARK: - DynamicDecisionSchema Clean Roundtrip Tests

    @Test("DynamicDecisionSchema creates schemas that translate cleanly through SchemaTranslator")
    func testDynamicDecisionSchemaTranslation() throws {
        let translator = SchemaTranslator()

        // 1. Binary schema
        let binarySchema = try DynamicDecisionSchema.makeBinarySchema(
            instructions: "Is this sensitive?",
            whenTrue: "contains PII",
            whenFalse: "public info"
        )
        let binaryTranslation = try translator.translate(binarySchema)
        #expect(binaryTranslation.questions.count == 1)
        let binaryQ = try #require(binaryTranslation.questions["decision"])
        if case .noul(let instr) = binaryQ {
            #expect(instr.contains("Is this sensitive?"))
            #expect(instr.contains("True if: contains PII"))
        } else {
            Issue.record("Expected noul question")
        }

        // 2. Choice schema
        let choiceSchema = try DynamicDecisionSchema.makeChoiceSchema(
            instructions: "Select category",
            options: [("A", "Option A description"), ("B", "Option B description")]
        )
        let choiceTranslation = try translator.translate(choiceSchema)
        #expect(choiceTranslation.questions.count == 1)
        let choiceQ = try #require(choiceTranslation.questions["choice"])
        if case .choice(let instr, let criteria) = choiceQ {
            #expect(instr.contains("Select category"))
            #expect(criteria["A"] == "A")
            #expect(criteria["B"] == "B")
        } else {
            Issue.record("Expected choice question")
        }

        // 3. Score schema
        let scoreSchema = try DynamicDecisionSchema.makeScoreSchema(
            instructions: "Evaluate score",
            levels: ["None", "Low", "Medium", "High"]
        )
        let scoreTranslation = try translator.translate(scoreSchema)
        #expect(scoreTranslation.questions.count == 1)
        let scoreQ = try #require(scoreTranslation.questions["score"])
        if case .score(let instr, let criteria) = scoreQ {
            #expect(instr.contains("Evaluate score"))
            #expect(criteria.count == 4)
        } else {
            Issue.record("Expected score question")
        }
    }

    // MARK: - Recursive / Cyclic Schema & Deprecation Shim Tests

    @Test("SchemaTranslator rejects self-referential or mutually-recursive schemas with typed error")
    func testRecursiveSchemaReferenceDetection() throws {
        let translator = SchemaTranslator()

        // 1. Direct self-referential $defs cycle (A -> A)
        let directSelfCycleJSON: [String: Any] = [
            "type": "object",
            "properties": [
                "item": ["$ref": "#/$defs/Loop"]
            ],
            "$defs": [
                "Loop": ["$ref": "#/$defs/Loop"]
            ]
        ]
        #expect(throws: SystemOneError.self) {
            try translator.translate(json: directSelfCycleJSON)
        }

        do {
            _ = try translator.translate(json: directSelfCycleJSON)
            Issue.record("Expected recursive schema error")
        } catch let SystemOneError.invalidSchema(msg) {
            #expect(msg == "Recursive or cyclic schema reference detected for 'Loop'")
        } catch {
            Issue.record("Unexpected error: \(error)")
        }

        // 2. Object containing self-referential nested property (SelfRef.next -> SelfRef)
        let selfReferentialObjectJSON: [String: Any] = [
            "type": "object",
            "properties": [
                "node": ["$ref": "#/$defs/SelfRef"]
            ],
            "$defs": [
                "SelfRef": [
                    "type": "object",
                    "properties": [
                        "next": ["$ref": "#/$defs/SelfRef"]
                    ]
                ]
            ]
        ]
        do {
            _ = try translator.translate(json: selfReferentialObjectJSON)
            Issue.record("Expected recursive schema error")
        } catch let SystemOneError.invalidSchema(msg) {
            #expect(msg == "Recursive or cyclic schema reference detected for 'SelfRef'")
        } catch {
            Issue.record("Unexpected error: \(error)")
        }

        // 3. Mutually-recursive schema (NodeA.b -> NodeB, NodeB.a -> NodeA)
        let mutuallyRecursiveJSON: [String: Any] = [
            "type": "object",
            "properties": [
                "root": ["$ref": "#/$defs/NodeA"]
            ],
            "$defs": [
                "NodeA": [
                    "type": "object",
                    "properties": [
                        "b": ["$ref": "#/$defs/NodeB"]
                    ]
                ],
                "NodeB": [
                    "type": "object",
                    "properties": [
                        "a": ["$ref": "#/$defs/NodeA"]
                    ]
                ]
            ]
        ]
        do {
            _ = try translator.translate(json: mutuallyRecursiveJSON)
            Issue.record("Expected mutually recursive schema error")
        } catch let SystemOneError.invalidSchema(msg) {
            #expect(msg == "Recursive or cyclic schema reference detected for 'NodeA'")
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Generable
    struct SimpleShimDecision: Sendable {
        @Guide(description: "Is this valid?")
        var isValid: Bool
    }

    @Test("Deprecation shims translateToQuestions and probabilityValue maintain source compatibility")
    func testDeprecationShims() async throws {
        let translator = SchemaTranslator()
        let binarySchema = try DynamicDecisionSchema.makeBinarySchema(instructions: "Is this valid?")

        // translateToQuestions shim
        let questions = try translator.translateToQuestions(binarySchema)
        #expect(questions["decision"] != nil)

        // probabilityValue shim on LanguageModelSession.Response
        let mockBackend = MockSystemOneBackend { _ in
            SystemOneResponse(
                model: "systemone-mock-v1",
                answers: [
                    "isValid": SystemOneAnswer(
                        type: "noul",
                        noul: 0.88,
                        confidence: 0.76,
                        probabilities: ["true": 0.88, "false": 0.12]
                    )
                ]
            )
        }
        let model = SystemOneLanguageModel(backend: mockBackend, modelID: "systemone-mock-v1")
        let session = LanguageModelSession(model: model)
        let response = try await session.respond(to: "Test input", generating: SimpleShimDecision.self)

        let typedProb = response.typedProbability(for: "isValid")
        let shimProb = response.probabilityValue(for: "isValid")
        #expect(typedProb != nil)
        #expect(typedProb == shimProb)
        #expect(shimProb?.value == 0.88)
    }
}
