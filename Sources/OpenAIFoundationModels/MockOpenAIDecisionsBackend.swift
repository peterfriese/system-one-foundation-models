import Foundation
import SystemOneCore

/// A mock backend enabling offline, deterministic automated testing of OpenAI Decisions models.
public final class MockOpenAIDecisionsBackend: SystemOneBackend, @unchecked Sendable {
    private let lock = NSLock()
    private var _lastRequest: SystemOneRequest?
    private var _lastOpenAIRequest: OpenAIDecisionsRequest?
    private var _evaluationCount: Int = 0
    private var _handler: (@Sendable (SystemOneRequest) async throws -> SystemOneResponse)?

    /// The most recent `SystemOneRequest` dispatched to this mock backend.
    public var lastRequest: SystemOneRequest? {
        lock.withLock { _lastRequest }
    }

    /// The adapted `OpenAIDecisionsRequest` from the most recent dispatch.
    public var lastOpenAIRequest: OpenAIDecisionsRequest? {
        lock.withLock { _lastOpenAIRequest }
    }

    /// Total number of evaluation calls received.
    public var evaluationCount: Int {
        lock.withLock { _evaluationCount }
    }

    /// Custom response handler to override default evaluation behavior.
    public var handler: (@Sendable (SystemOneRequest) async throws -> SystemOneResponse)? {
        get { lock.withLock { _handler } }
        set { lock.withLock { _handler = newValue } }
    }

    public init(
        handler: (@Sendable (SystemOneRequest) async throws -> SystemOneResponse)? = nil
    ) {
        self._handler = handler
    }

    public func evaluate(request: SystemOneRequest) async throws -> SystemOneResponse {
        let adapted = try? OpenAIDecisionsPayloadAdapter.adaptRequest(request)
        lock.withLock {
            _lastRequest = request
            _lastOpenAIRequest = adapted
            _evaluationCount += 1
        }

        let currentHandler = lock.withLock { _handler }
        if let currentHandler {
            return try await currentHandler(request)
        }

        // Generate deterministic, sensible default answers for all questions
        var answers: [String: SystemOneAnswer] = [:]
        for (name, question) in request.questions {
            switch question {
            case .noul:
                answers[name] = SystemOneAnswer(
                    type: "noul",
                    noul: 0.95,
                    confidence: 0.95,
                    probabilities: ["true": 0.95, "false": 0.05]
                )
            case .choice(_, let criteria):
                let choice = criteria.keys.sorted().first ?? "default"
                var probs: [String: Double] = [choice: 0.95]
                for other in criteria.keys where other != choice {
                    probs[other] = 0.05 / Double(max(1, criteria.count - 1))
                }
                answers[name] = SystemOneAnswer(
                    type: "choice",
                    choice: choice,
                    confidence: 0.95,
                    probabilities: probs
                )
            case .score(_, let criteria):
                let score = criteria.isEmpty ? 4.5 : Double(criteria.count)
                var probs: [String: Double] = [:]
                for (i, c) in criteria.enumerated() {
                    probs[c] = (i == criteria.count - 1) ? 0.90 : (0.10 / Double(max(1, criteria.count - 1)))
                }
                answers[name] = SystemOneAnswer(
                    type: "score",
                    score: score,
                    confidence: 0.95,
                    probabilities: probs.isEmpty ? nil : probs
                )
            }
        }

        return SystemOneResponse(
            model: request.model.isEmpty ? "gpt-6-luna" : request.model,
            answers: answers,
            usage: SystemOneUsage(inputTokens: 120, outputTokens: 0),
            serverDurationMs: 14.2,
            transportDurationMs: 18.5
        )
    }

    /// Resets captured state and request counters.
    public func reset() {
        lock.withLock {
            _lastRequest = nil
            _lastOpenAIRequest = nil
            _evaluationCount = 0
        }
    }
}
