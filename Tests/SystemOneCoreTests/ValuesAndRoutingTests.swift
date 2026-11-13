import Testing
import Foundation
@testable import SystemOneCore

@Suite("Domain Values & Confidence Routing Tests")
struct ValuesAndRoutingTests {

    // MARK: - Probability Tests

    @Test("Probability clamps values into 0...1 and computes decisiveness correctly")
    func testProbabilityBasics() {
        let pHigh = Probability(clamping: 1.5)
        #expect(pHigh.value == 1.0)
        #expect(pHigh.decisiveness == 1.0)

        let pLow = Probability(clamping: -0.2)
        #expect(pLow.value == 0.0)
        #expect(pLow.decisiveness == 1.0)

        let pMid = Probability(clamping: 0.5)
        #expect(pMid.value == 0.5)
        #expect(pMid.decisiveness == 0.5)

        let pNo = Probability(clamping: 0.05)
        #expect(pNo.decisiveness == 0.95)

        let pYes = Probability(clamping: 0.95)
        #expect(pYes.decisiveness == 0.95)
    }

    @Test("Probability exact initializer rejects out-of-range values and NaN")
    func testProbabilityExactInit() {
        #expect(Probability(exactly: 0.5) != nil)
        #expect(Probability(exactly: 0.0) != nil)
        #expect(Probability(exactly: 1.0) != nil)
        #expect(Probability(exactly: 1.001) == nil)
        #expect(Probability(exactly: -0.001) == nil)
        #expect(Probability(exactly: Double.nan) == nil)
    }

    @Test("Probability Codable roundtrip and corruption handling")
    func testProbabilityCodable() throws {
        let original = Probability(clamping: 0.88)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(Probability.self, from: data)
        #expect(decoded == original)

        let invalidJSON = Data("1.5".utf8)
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(Probability.self, from: invalidJSON)
        }
    }

    // MARK: - ScoreValue Tests

    @Test("ScoreValue computes rounded level and normalized score correctly")
    func testScoreValueCalculations() {
        let score = ScoreValue(
            value: 1.6,
            legend: [0: "Low", 1: "Medium", 2: "High"],
            probabilities: [0: 0.05, 1: 0.30, 2: 0.65],
            confidence: 0.78
        )

        #expect(score.rounded == 2)
        #expect(score.normalized == 0.8)
        #expect(score.confidence == 0.78)

        let singleLevel = ScoreValue(value: 0.5, legend: [0: "Single"], probabilities: [0: 1.0])
        #expect(singleLevel.normalized == nil)
    }

    @Test("ScoreValue.rounded clamps extreme finite Doubles safely without Int overflow trap")
    func testScoreValueRoundedExtremeClamping() {
        let hugePositive = ScoreValue(value: 1e30)
        #expect(hugePositive.rounded == Int.max)

        let atIntMax = ScoreValue(value: Double(Int.max))
        #expect(atIntMax.rounded == Int.max)

        let hugeNegative = ScoreValue(value: -1e30)
        #expect(hugeNegative.rounded == Int.min)
    }

    @Test("ScoreValue normalized correctly maps 1-based and sparse rubric keys")
    func testScoreValueNonZeroBasedAndSparseKeys() {
        let oneBased = ScoreValue(
            value: 1.0,
            legend: [1: "Low", 2: "Med", 3: "High"],
            probabilities: [1: 1.0, 2: 0.0, 3: 0.0]
        )
        #expect(oneBased.normalized == 0.0)

        let oneBasedMid = ScoreValue(
            value: 2.0,
            legend: [1: "Low", 2: "Med", 3: "High"],
            probabilities: [1: 0.0, 2: 1.0, 3: 0.0]
        )
        #expect(oneBasedMid.normalized == 0.5)

        let oneBasedMax = ScoreValue(
            value: 3.0,
            legend: [1: "Low", 2: "Med", 3: "High"],
            probabilities: [1: 0.0, 2: 0.0, 3: 1.0]
        )
        #expect(oneBasedMax.normalized == 1.0)

        let sparse = ScoreValue(
            value: 2.0,
            legend: [0: "Zero", 2: "Two"],
            probabilities: [0: 0.0, 2: 1.0]
        )
        #expect(sparse.normalized == 1.0)
    }

    @Test("ScoreValue validating initializer safely rejects non-finite values and out-of-range confidence")
    func testScoreValueNonFiniteSafety() {
        #expect(ScoreValue(validatingValue: .infinity) == nil)
        #expect(ScoreValue(validatingValue: -.infinity) == nil)
        #expect(ScoreValue(validatingValue: .nan) == nil)
        #expect(ScoreValue(validatingValue: 1.0, confidence: 1.2) == nil)
        #expect(ScoreValue(validatingValue: 1.0, confidence: -0.1) == nil)
        #expect(ScoreValue(validatingValue: 1.0, confidence: .nan) == nil)
        #expect(ScoreValue(validatingValue: 1.0, confidence: 0.95) != nil)
    }

    @Test("ScoreValue Codable encodes and decodes accurately")
    func testScoreValueCodable() throws {
        let original = ScoreValue(
            value: 2.3,
            legend: [0: "P0", 1: "P1", 2: "P2", 3: "P3"],
            probabilities: [0: 0.02, 1: 0.08, 2: 0.70, 3: 0.20],
            confidence: 0.85
        )

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(ScoreValue.self, from: data)

        #expect(decoded.value == 2.3)
        #expect(decoded.rounded == 2)
        #expect(decoded.normalized != nil)
        #expect(decoded.confidence == 0.85)
        #expect(decoded.legend[0] == "P0")
        #expect(decoded.probabilities[2] == 0.70)
    }

    @Test("ScoreValue telemetry remaps zero-based score indices into integer rubric ranges")
    func testScoreValueTelemetryForNonZeroBasedIntegerRange() throws {
        let synthesizer = ResponseSynthesizer()
        let layout = SchemaRootLayout.object(
            properties: [
                "priority": SchemaPropertyDescriptor(
                    name: "priority",
                    questionKey: "priority",
                    kind: .score(minimum: 1, maximum: 5, isInteger: true),
                    instructions: "Priority"
                )
            ],
            propertyOrder: ["priority"]
        )
        let answers = [
            "priority": SystemOneAnswer(
                type: "score",
                score: 2.0,
                confidence: 0.9,
                probabilities: ["0": 0.05, "1": 0.10, "2": 0.70, "3": 0.10, "4": 0.05],
                legend: ["0": "P1", "1": "P2", "2": "P3", "3": "P4", "4": "P5"]
            )
        ]

        let json = try #require(synthesizer.extractScoresJSON(from: answers, layout: layout))
        let decoded = try JSONDecoder().decode([String: ScoreValue].self, from: Data(json.utf8))
        let score = try #require(decoded["priority"])

        #expect(score.value == 3.0)
        #expect(score.rounded == 3)
        #expect(score.legend[3] == "P3")
        #expect(score.probabilities[3] == 0.70)
    }

    @Test("ScoreValue preserves 1-based OpenAI score answers without off-by-one +minimum corruption")
    func testScoreValuePreservesOneBasedOpenAIScoreAnswers() throws {
        let synthesizer = ResponseSynthesizer()
        let layout = SchemaRootLayout.object(
            properties: [
                "riskScore": SchemaPropertyDescriptor(
                    name: "riskScore",
                    questionKey: "riskScore",
                    kind: .score(minimum: 1, maximum: 5, isInteger: true),
                    instructions: "Risk score"
                )
            ],
            propertyOrder: ["riskScore"]
        )
        let answers = [
            "riskScore": SystemOneAnswer(
                type: "score",
                score: 3.0,
                confidence: 0.92,
                probabilities: ["1": 0.02, "2": 0.05, "3": 0.85, "4": 0.05, "5": 0.03],
                legend: ["1": "Level 1", "2": "Level 2", "3": "Level 3", "4": "Level 4", "5": "Level 5"]
            )
        ]

        let synthesized = try synthesizer.synthesize(answers: answers, layout: layout)
        #expect(synthesized == "{\"riskScore\":3}")

        let json = try #require(synthesizer.extractScoresJSON(from: answers, layout: layout))
        let decoded = try JSONDecoder().decode([String: ScoreValue].self, from: Data(json.utf8))
        let score = try #require(decoded["riskScore"])
        #expect(score.value == 3.0)
        #expect(score.rounded == 3)
        #expect(score.probabilities[3] == 0.85)
    }

    // MARK: - RoutingPolicy Tests

    @Test("RoutingPolicy maps confidence to decisions at calibrated thresholds")
    func testChoiceRoutingThresholds() {
        let policy = RoutingPolicy.default

        #expect(policy.decide(confidence: 0.0) == .escalate)
        #expect(policy.decide(confidence: 0.59) == .escalate)
        #expect(policy.decide(confidence: 0.60) == .confirm)
        #expect(policy.decide(confidence: 0.84) == .confirm)
        #expect(policy.decide(confidence: 0.85) == .auto)
        #expect(policy.decide(confidence: 1.00) == .auto)
        #expect(policy.decide(confidence: nil) == .escalate)
    }

    @Test("RoutingPolicy clamps out-of-range and inverted thresholds safely")
    func testRoutingPolicyThresholdClamping() {
        let inverted = RoutingPolicy(escalateBelow: 0.9, autoAtOrAbove: 0.4, undecidedBand: -0.5...1.5)
        #expect(inverted.escalateBelow == 0.9)
        #expect(inverted.autoAtOrAbove == 0.9)
        #expect(inverted.undecidedBand == 0.0...1.0)
    }

    @Test("Noul inside undecided band (0.35...0.65) returns nil answer and escalates")
    func testNoulUndecidedBand() {
        let policy = RoutingPolicy.default

        for p in [0.35, 0.45, 0.50, 0.55, 0.65] {
            let judgement = policy.decide(Probability(clamping: p))
            #expect(judgement.answer == nil)
            #expect(judgement.decision == .escalate)
        }
    }

    @Test("Noul confident Yes and confident No both resolve to .auto")
    func testNoulDecisiveJudgements() {
        let policy = RoutingPolicy.default

        let yesJudgement = policy.decide(Probability(clamping: 0.95))
        #expect(yesJudgement.answer == true)
        #expect(yesJudgement.decision == .auto)
        #expect(yesJudgement.decisiveness == 0.95)

        let noJudgement = policy.decide(Probability(clamping: 0.05))
        #expect(noJudgement.answer == false)
        #expect(noJudgement.decision == .auto)
        #expect(noJudgement.decisiveness == 0.95)
    }

    @Test("Noul leaning answers outside undecided band resolve to .confirm")
    func testNoulLeaningJudgements() {
        let policy = RoutingPolicy.default

        let leaningYes = policy.decide(Probability(clamping: 0.75))
        #expect(leaningYes.answer == true)
        #expect(leaningYes.decision == .confirm)

        let leaningNo = policy.decide(Probability(clamping: 0.25))
        #expect(leaningNo.answer == false)
        #expect(leaningNo.decision == .confirm)
    }

    @Test("Missing noul probability safely escalates")
    func testMissingNoulProbabilityEscalates() {
        let policy = RoutingPolicy.default
        let judgement = policy.decide(nil as Probability?)
        #expect(judgement.answer == nil)
        #expect(judgement.decisiveness == 0.0)
        #expect(judgement.decision == .escalate)
    }

    // MARK: - SystemOneError Taxonomy Tests

    @Test("SystemOneError remains Equatable and preserves HTTP & remediation diagnostics")
    func testSystemOneErrorDiagnostics() {
        let err401 = SystemOneError.apiError(statusCode: 401, message: "Invalid API key")
        #expect(err401.localizedDescription.contains("401"))
        #expect(err401 == SystemOneError.apiError(statusCode: 401, message: "Invalid API key"))

        let missingKey = SystemOneError.missingAPIKey
        #expect(missingKey.localizedDescription.contains("TYPESAFE_API_KEY"))

        let networkError = SystemOneError.networkError("connection lost")
        #expect(networkError.localizedDescription.contains("Network error"))
    }
}
