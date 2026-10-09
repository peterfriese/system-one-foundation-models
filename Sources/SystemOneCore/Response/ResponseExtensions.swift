import Foundation
import FoundationModels

// MARK: - LanguageModelSession.Response Extensions for System One Telemetry & Routing

public extension LanguageModelSession.Response {
    /// The response metadata emitted by `SystemOneExecutor`, containing model ID, confidence scores, scores, and calibrated probabilities.
    var metadata: [String: GeneratedContent] {
        for entry in transcriptEntries.reversed() {
            if case .response(let r) = entry {
                return r.metadata
            }
        }
        return [:]
    }

    /// Calibrated probability distributions per question, parsed from response metadata.
    var probabilities: [String: [String: Double]] {
        guard let content = metadata["probabilities"] else { return [:] }
        let rawJSON: String
        if let str = try? content.value(String.self) {
            rawJSON = str
        } else {
            rawJSON = content.jsonString
        }

        guard let data = rawJSON.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: [String: Double]] else {
            return [:]
        }
        return dict
    }

    /// Calibrated confidence scores (0.0 to 1.0) per question, parsed from response metadata.
    var confidenceScores: [String: Double] {
        guard let content = metadata["confidence"] else { return [:] }
        let rawJSON: String
        if let str = try? content.value(String.self) {
            rawJSON = str
        } else {
            rawJSON = content.jsonString
        }

        guard let data = rawJSON.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Double] else {
            return [:]
        }
        return dict
    }

    /// Decoded rubric score values per question, parsed from response metadata.
    var scoreValues: [String: ScoreValue] {
        guard let content = metadata["scores"] else { return [:] }
        let rawJSON: String
        if let str = try? content.value(String.self) {
            rawJSON = str
        } else {
            rawJSON = content.jsonString
        }

        guard let data = rawJSON.data(using: .utf8),
              let dict = try? JSONDecoder().decode([String: ScoreValue].self, from: data) else {
            return [:]
        }
        return dict
    }

    /// Returns the calibrated probability of `true` for a boolean (`noul`) question.
    func probability(for question: String) -> Double? {
        if let questionProbs = probabilities[question], let trueProb = questionProbs["true"] {
            return trueProb
        }
        return nil
    }

    /// Returns the calibrated `Probability` wrapper for a boolean (`noul`) question.
    func typedProbability(for question: String) -> Probability? {
        probability(for: question).map(Probability.init(clamping:))
    }

    /// Returns the confidence score for a given categorical or scored question.
    func confidence(for question: String) -> Double? {
        confidenceScores[question]
    }

    /// Returns the parsed `ScoreValue` for a given rubric score question.
    func scoreValue(for question: String) -> ScoreValue? {
        scoreValues[question]
    }

    /// Evaluates the confidence score of a categorical or scored question against a `RoutingPolicy`.
    func decision(for question: String, policy: RoutingPolicy = .default) -> Decision {
        policy.decide(confidence: confidence(for: question))
    }

    /// Evaluates a boolean (`noul`) question against a `RoutingPolicy`, accounting for the undecided band.
    func judgement(for question: String, policy: RoutingPolicy = .default) -> NoulJudgement {
        policy.decide(typedProbability(for: question))
    }

    /// The server-side inference time (in milliseconds) reported by the gateway.
    var serverDurationMs: Double? {
        guard let content = metadata["serverDurationMs"] else { return nil }
        if let str = try? content.value(String.self), let val = Double(str) {
            return val
        }
        return Double(content.jsonString)
    }

    /// The client-side transport/network round-trip time (in milliseconds).
    var transportDurationMs: Double? {
        guard let content = metadata["transportDurationMs"] else { return nil }
        if let str = try? content.value(String.self), let val = Double(str) {
            return val
        }
        return Double(content.jsonString)
    }
}
