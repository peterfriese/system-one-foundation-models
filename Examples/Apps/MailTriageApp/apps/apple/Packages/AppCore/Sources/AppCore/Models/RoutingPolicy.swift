import Foundation

/// Represents the operational tier and programmatic automation action for a triage decision.
public enum RoutingPolicy: String, Sendable, Hashable, Codable, CaseIterable, Identifiable {
    /// High confidence (>= 0.85): Adopt and execute the triage action automatically.
    case auto

    /// Moderate confidence (0.60 ..< 0.85): Prompt the user for 1-click confirmation or preview.
    case confirm

    /// Low confidence (< 0.60) or epistemic uncertainty: Retain safely in inbox for human review.
    case escalate

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .auto: return "Auto Executed"
        case .confirm: return "Confirmation Needed"
        case .escalate: return "Escalated to Inbox"
        }
    }

    public var statusBadgeText: String {
        switch self {
        case .auto: return "AUTO EXECUTED"
        case .confirm: return "CONFIRMATION NEEDED"
        case .escalate: return "ESCALATED TO INBOX"
        }
    }

    public var iconName: String {
        switch self {
        case .auto: return "bolt.shield.fill"
        case .confirm: return "checkmark.circle.badge.questionmark.fill"
        case .escalate: return "exclamationmark.triangle.fill"
        }
    }

    /// Evaluates calibrated choice confidence and noul probability into an operational routing tier.
    ///
    /// - Parameters:
    ///   - confidence: Calibrated confidence score in [0.0, 1.0].
    ///   - probability: Optional boolean noul probability in [0.0, 1.0].
    ///   - autoThreshold: Minimum confidence / decisiveness required for automated execution (default: 0.85).
    ///   - confirmThreshold: Minimum confidence / decisiveness required for interactive confirmation (default: 0.60).
    ///   - undecidedBand: Range of boolean probability representing maximum epistemic uncertainty (default: 0.35...0.65).
    public static func evaluate(
        confidence: Double,
        probability: Double? = nil,
        autoThreshold: Double = 0.85,
        confirmThreshold: Double = 0.60,
        undecidedBand: ClosedRange<Double> = 0.35...0.65
    ) -> RoutingPolicy {
        // If noul probability is present, check epistemic uncertainty band first
        if let p = probability {
            if undecidedBand.contains(p) {
                return .escalate
            }
            let decisiveness = max(p, 1.0 - p)
            if decisiveness < confirmThreshold || confidence < confirmThreshold {
                return .escalate
            }
            if decisiveness >= autoThreshold && confidence >= autoThreshold {
                return .auto
            }
            return .confirm
        }

        // Standard choice / score confidence evaluation
        if confidence >= autoThreshold {
            return .auto
        } else if confidence >= confirmThreshold {
            return .confirm
        } else {
            return .escalate
        }
    }
}

/// Alias for compatibility with architectural naming conventions.
public typealias RoutingTier = RoutingPolicy
