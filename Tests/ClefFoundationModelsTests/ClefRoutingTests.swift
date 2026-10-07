import Testing
import Foundation
import FoundationModels
import SystemOneCore
import ClefFoundationModels

// MARK: - Visual Defect Triage Schema

@Generable
enum SurfaceAnomalyKind: String, Sendable, CaseIterable {
    case clean
    case hairlineCrack
    case bubble
    case discoloration
}

@Generable
struct VisualTriageDecision: Sendable {
    @Guide(description: "Is the part rejected due to critical visual defect?")
    var isRejected: Bool

    @Guide(description: "Identified anomaly type on the lens surface")
    var anomalyKind: SurfaceAnomalyKind

    @Guide(description: "Quality grade rubric from 0 (reject) to 3 (flawless)", .range(0...3))
    var qualityGrade: Int
}

// MARK: - Mock URLProtocol for ClefRoutingTests

final class MockClefRoutingProtocol: URLProtocol {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var _responseQueue: [Result<(statusCode: Int, headers: [String: String], body: Data), any Error>] = []

    static func reset() {
        lock.withLock {
            _responseQueue = []
        }
    }

    static func enqueue(statusCode: Int, headers: [String: String] = [:], body: Data = Data()) {
        lock.withLock {
            _responseQueue.append(.success((statusCode, headers, body)))
        }
    }

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        let nextItem: Result<(statusCode: Int, headers: [String: String], body: Data), any Error>? = Self.lock.withLock {
            guard !Self._responseQueue.isEmpty else { return nil }
            return Self._responseQueue.removeFirst()
        }

        guard let next = nextItem else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }

        switch next {
        case .success(let item):
            let response = HTTPURLResponse(
                url: request.url ?? URL(string: "https://api.cloudflare.com")!,
                statusCode: item.statusCode,
                httpVersion: "HTTP/1.1",
                headerFields: item.headers
            )!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: item.body)
            client?.urlProtocolDidFinishLoading(self)

        case .failure(let error):
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

// MARK: - Test Suite

@Suite("Clef Calibrated Visual Confidence Routing Tests", .serialized)
struct ClefRoutingTests {

    private func makeSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockClefRoutingProtocol.self]
        return URLSession(configuration: config)
    }

    // MARK: - Calibrated Routing Policy Primitive Tests

    @Test("Calibrated Noul routing maps decisive, leaning, and undecided probabilities accurately")
    func testCalibratedNoulRouting() {
        let policy = RoutingPolicy.default

        // 1. Decisive Yes (p = 0.95 -> decisiveness = 0.95 >= 0.85) -> .auto, true
        let decisiveYes = policy.decide(Probability(clamping: 0.95))
        #expect(decisiveYes.answer == true)
        #expect(decisiveYes.decision == .auto)
        #expect(decisiveYes.decisiveness == 0.95)

        // 2. Decisive No (p = 0.05 -> decisiveness = 0.95 >= 0.85) -> .auto, false
        let decisiveNo = policy.decide(Probability(clamping: 0.05))
        #expect(decisiveNo.answer == false)
        #expect(decisiveNo.decision == .auto)
        #expect(decisiveNo.decisiveness == 0.95)

        // 3. Leaning Yes (p = 0.75 -> decisiveness = 0.75 >= 0.60 and < 0.85) -> .confirm, true
        let leaningYes = policy.decide(Probability(clamping: 0.75))
        #expect(leaningYes.answer == true)
        #expect(leaningYes.decision == .confirm)

        // 4. Leaning No (p = 0.25 -> decisiveness = 0.75 >= 0.60 and < 0.85) -> .confirm, false
        let leaningNo = policy.decide(Probability(clamping: 0.25))
        #expect(leaningNo.answer == false)
        #expect(leaningNo.decision == .confirm)

        // 5. Undecided Band (p = 0.50 inside 0.35...0.65) -> .escalate, nil answer
        let undecided = policy.decide(Probability(clamping: 0.50))
        #expect(undecided.answer == nil)
        #expect(undecided.decision == .escalate)

        // 6. Missing probability -> .escalate, nil answer
        let missing = policy.decide(nil as Probability?)
        #expect(missing.answer == nil)
        #expect(missing.decision == .escalate)
    }

    @Test("Calibrated Choice and Score confidence routing maps to auto, confirm, and escalate")
    func testChoiceAndScoreRouting() {
        let policy = RoutingPolicy.default

        #expect(policy.decide(confidence: 0.95) == .auto)
        #expect(policy.decide(confidence: 0.85) == .auto)
        #expect(policy.decide(confidence: 0.84) == .confirm)
        #expect(policy.decide(confidence: 0.60) == .confirm)
        #expect(policy.decide(confidence: 0.59) == .escalate)
        #expect(policy.decide(confidence: 0.20) == .escalate)
        #expect(policy.decide(confidence: nil) == .escalate)
    }

    // MARK: - End-to-End Clef Evaluation + Routing Scenarios

    @Test("Scenario A: High confidence defect triggers automated rejection (.auto)")
    func testHighConfidenceAutomatedRejection() async throws {
        let responseJSON = """
        {
          "model": "@cf/cloudflare/clef",
          "answers": {
            "isRejected": { "type": "noul", "noul": 0.98, "confidence": 0.98, "probabilities": { "true": 0.98, "false": 0.02 } },
            "anomalyKind": { "type": "choice", "choice": "hairlineCrack", "confidence": 0.94, "probabilities": { "hairlineCrack": 0.94, "clean": 0.06 } },
            "qualityGrade": { "type": "score", "score": 0.0, "confidence": 0.96, "probabilities": { "0": 0.96, "1": 0.04 } }
          },
          "usage": { "input_tokens": 512, "output_tokens": 14 }
        }
        """.data(using: .utf8)!

        MockClefRoutingProtocol.reset()
        MockClefRoutingProtocol.enqueue(statusCode: 200, body: responseJSON)

        let backend = ClefHTTPBackend(endpoint: .workersAI(accountID: "cf-acc", model: .clef), session: makeSession())
        let model = ClefLanguageModel(configuration: .init(backend: backend))
        let session = LanguageModelSession(model: model)

        let response = try await session.respond(to: "Lens scan inspection unit #42", generating: VisualTriageDecision.self)

        #expect(response.content.isRejected == true)
        #expect(response.content.anomalyKind == .hairlineCrack)
        #expect(response.content.qualityGrade == 0)

        // Route using RoutingPolicy
        let policy = RoutingPolicy.default
        let prob = response.probability(for: "isRejected")
        let judgement = policy.decide(prob.flatMap(Probability.init(exactly:)))

        #expect(judgement.decision == .auto)
        #expect(judgement.answer == true)

        let anomalyConf = response.confidence(for: "anomalyKind")
        #expect(policy.decide(confidence: anomalyConf) == .auto)
    }

    @Test("Scenario B: Leaning confidence defect requires human reviewer confirmation (.confirm)")
    func testBorderlineConfirmationRouting() async throws {
        let responseJSON = """
        {
          "model": "@cf/cloudflare/clef-flash",
          "answers": {
            "isRejected": { "type": "noul", "noul": 0.72, "confidence": 0.72, "probabilities": { "true": 0.72, "false": 0.28 } },
            "anomalyKind": { "type": "choice", "choice": "bubble", "confidence": 0.68, "probabilities": { "bubble": 0.68, "clean": 0.32 } },
            "qualityGrade": { "type": "score", "score": 1.0, "confidence": 0.70 }
          },
          "usage": { "input_tokens": 400, "output_tokens": 14 }
        }
        """.data(using: .utf8)!

        MockClefRoutingProtocol.reset()
        MockClefRoutingProtocol.enqueue(statusCode: 200, body: responseJSON)

        let backend = ClefHTTPBackend(endpoint: .local(), session: makeSession())
        let model = ClefLanguageModel(configuration: .init(backend: backend))
        let session = LanguageModelSession(model: model)

        let response = try await session.respond(to: "Low contrast surface scan #109", generating: VisualTriageDecision.self)

        let policy = RoutingPolicy.default
        let prob = response.probability(for: "isRejected")
        let judgement = policy.decide(prob.flatMap(Probability.init(exactly:)))

        // Decisiveness is 0.72 -> .confirm (safe for secondary operator review)
        #expect(judgement.decision == .confirm)
        #expect(judgement.answer == true)

        let kindRouting = policy.decide(confidence: response.confidence(for: "anomalyKind"))
        #expect(kindRouting == .confirm)
    }

    @Test("Scenario C: Ambiguous scan in undecided band escalates to engineering (.escalate)")
    func testAmbiguousScanEscalates() async throws {
        let responseJSON = """
        {
          "model": "@cf/cloudflare/clef-flash",
          "answers": {
            "isRejected": { "type": "noul", "noul": 0.52, "confidence": 0.52, "probabilities": { "true": 0.52, "false": 0.48 } },
            "anomalyKind": { "type": "choice", "choice": "discoloration", "confidence": 0.45, "probabilities": { "discoloration": 0.45, "clean": 0.55 } },
            "qualityGrade": { "type": "score", "score": 2.0, "confidence": 0.50 }
          },
          "usage": { "input_tokens": 300, "output_tokens": 14 }
        }
        """.data(using: .utf8)!

        MockClefRoutingProtocol.reset()
        MockClefRoutingProtocol.enqueue(statusCode: 200, body: responseJSON)

        let backend = ClefHTTPBackend(endpoint: .local(), session: makeSession())
        let model = ClefLanguageModel(configuration: .init(backend: backend))
        let session = LanguageModelSession(model: model)

        let response = try await session.respond(to: "Ambiguous reflection on curved edge #302", generating: VisualTriageDecision.self)

        let policy = RoutingPolicy.default
        let prob = response.probability(for: "isRejected")
        let judgement = policy.decide(prob.flatMap(Probability.init(exactly:)))

        // 0.52 is in undecided band 0.35...0.65 -> must escalate without guessing
        #expect(judgement.decision == .escalate)
        #expect(judgement.answer == nil)

        let kindRouting = policy.decide(confidence: response.confidence(for: "anomalyKind"))
        #expect(kindRouting == .escalate)
    }
}
