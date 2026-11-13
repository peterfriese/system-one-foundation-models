import Foundation
import FoundationModels

// See tech-notes/0006-http-resilience-and-confidence-routing.md

/// Represents the programmatic action to take on a decision based on its calibrated confidence.
public enum Decision: String, Sendable, Hashable, Codable, CaseIterable {
    /// High confidence: adopt and execute the decision automatically.
    case auto

    /// Moderate confidence: prompt the user for confirmation or present as a suggested choice.
    case confirm

    /// Low confidence or undecided: route to human review or fallback logic.
    case escalate
}

/// The result of evaluating a boolean (`noul`) question through a `RoutingPolicy`.
public struct NoulJudgement: Sendable, Hashable, CustomStringConvertible {
    /// The judged truth value, or `nil` if the model's probability fell within the undecided band.
    public var answer: Bool?

    /// Measures distance from 0.5 maximum uncertainty (`max(p, 1 - p)`).
    public var decisiveness: Double

    /// Programmatic routing action.
    public var decision: Decision

    public init(answer: Bool?, decisiveness: Double, decision: Decision) {
        self.answer = answer
        self.decisiveness = decisiveness
        self.decision = decision
    }

    public var description: String {
        let answerStr = answer.map { String($0) } ?? "undecided"
        return "NoulJudgement(answer: \(answerStr), decisiveness: \(String(format: "%.2f", decisiveness)), decision: .\(decision.rawValue))"
    }
}

/// Policy thresholds for turning calibrated confidence scores and probabilities into actionable decisions.
///
/// It is recommended to configure a policy per action rather than one globally:
/// a confidence threshold sufficient for tagging an article is rarely sufficient for approving a financial transfer.
public struct RoutingPolicy: Sendable, Hashable {
    /// Confidence below this threshold escalates to human review or fallback.
    public var escalateBelow: Double

    /// Confidence at or above this threshold can be executed automatically.
    public var autoAtOrAbove: Double

    /// The band where a boolean probability indicates the model is genuinely undecided.
    public var undecidedBand: ClosedRange<Double>

    public init(
        escalateBelow: Double = 0.6,
        autoAtOrAbove: Double = 0.85,
        undecidedBand: ClosedRange<Double> = 0.35...0.65
    ) {
        let clampedEscalate = escalateBelow.isFinite ? min(max(escalateBelow, 0.0), 1.0) : 0.6
        let clampedAuto = autoAtOrAbove.isFinite ? min(max(autoAtOrAbove, 0.0), 1.0) : 0.85
        self.escalateBelow = clampedEscalate
        self.autoAtOrAbove = max(clampedAuto, clampedEscalate)

        let rawLower = undecidedBand.lowerBound.isFinite ? min(max(undecidedBand.lowerBound, 0.0), 1.0) : 0.35
        let rawUpper = undecidedBand.upperBound.isFinite ? min(max(undecidedBand.upperBound, 0.0), 1.0) : 0.65
        self.undecidedBand = min(rawLower, rawUpper)...max(rawLower, rawUpper)
    }

    public static let `default` = RoutingPolicy()

    // MARK: - Confidence Decision (Choice & Score)

    /// Decides the action for an optional confidence score.
    ///
    /// - Note: An unanswered or missing question resolves to `.escalate`.
    public func decide(confidence: Double?) -> Decision {
        guard let confidence else { return .escalate }
        if confidence < escalateBelow { return .escalate }
        return confidence >= autoAtOrAbove ? .auto : .confirm
    }

    // MARK: - Probability Decision (Noul)

    /// Decides the judgment and action for a boolean `Probability`.
    ///
    /// For a `noul` question, the probability itself is the signal.
    /// A probability of 0.05 is a highly decisive "no" ($p = 0.05 \implies \text{decisiveness} = 0.95 \implies \text{.auto}$),
    /// which adopts the *negative* answer with confidence.
    public func decide(_ probability: Probability?) -> NoulJudgement {
        guard let probability else {
            return NoulJudgement(answer: nil, decisiveness: 0.0, decision: .escalate)
        }

        let p = probability.value
        let decisiveness = probability.decisiveness

        guard !undecidedBand.contains(p) else {
            return NoulJudgement(answer: nil, decisiveness: decisiveness, decision: .escalate)
        }

        let answer = p > 0.5
        let decision: Decision =
            decisiveness < escalateBelow ? .escalate
            : decisiveness >= autoAtOrAbove ? .auto
            : .confirm

        return NoulJudgement(answer: answer, decisiveness: decisiveness, decision: decision)
    }

    // MARK: - Foundation Models Response Integration

    /// Decides the action for a categorical or scored question from a Foundation Models `LanguageModelSession.Response`.
    public func decide<T>(_ response: LanguageModelSession.Response<T>, of question: String) -> Decision {
        decide(confidence: response.confidence(for: question))
    }

    /// Decides the boolean judgment for a question from a Foundation Models `LanguageModelSession.Response`.
    public func decideNoul<T>(_ response: LanguageModelSession.Response<T>, of question: String) -> NoulJudgement {
        decide(response.typedProbability(for: question))
    }
}
