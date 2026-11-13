import Foundation
import FoundationModels

/// Strongly-typed decision payload evaluated by System One and Foundation Models engines.
@Generable
public struct EmailTriageDecision: Sendable, Hashable, Codable {
    /// Whether the email requires explicit user intervention or action.
    /// Maps to a System One `noul` primitive (calibrated probability [0.0...1.0]).
    @Guide(description: "True if this email requires an explicit user response, decision, or action.")
    public var requiresAction: Bool

    /// Categorical classification of the email into one of 6 discrete functional buckets.
    /// Maps to a System One `choice` primitive with categorical options.
    @Guide(description: "Primary functional classification of the incoming message.")
    public var category: EmailCategory

    /// Urgency priority rating from P0 (Critical/Blocker) to P3 (Low priority).
    /// Maps to a System One `score` primitive evaluated against an ordinal rubric.
    @Guide(
        description: "Priority rubric score: 0 = P0 Critical outage/security, 1 = P1 Urgent high priority, 2 = P2 Medium regular work, 3 = P3 Low background informational.",
        .range(0...3)
    )
    public var urgencyScore: Int

    /// Specific operational workflow recommended by the triage engine.
    /// Maps to a System One `choice` primitive with discrete action keys.
    @Guide(description: "Recommended operational triage workflow to execute on this email.")
    public var suggestedAction: TriageAction

    public init(
        requiresAction: Bool,
        category: EmailCategory,
        urgencyScore: Int,
        suggestedAction: TriageAction
    ) {
        self.requiresAction = requiresAction
        self.category = category
        self.urgencyScore = urgencyScore
        self.suggestedAction = suggestedAction
    }
}

/// Canonical urgency priority rubric representing System One score values 0...3.
public enum UrgencyPriority: Int, Sendable, CaseIterable, Identifiable, Codable {
    /// P0 Critical: Outage, security incident, or executive escalation requiring immediate intervention.
    case p0Critical = 0
    /// P1 High: Urgent customer or blocker issue requiring rapid resolution.
    case p1High = 1
    /// P2 Medium: Standard operational work or task requiring routine attention.
    case p2Medium = 2
    /// P3 Low: Informational, background digest, or low-priority notice.
    case p3Low = 3

    public var id: Int { rawValue }

    public init?(score: Int) {
        self.init(rawValue: score)
    }

    /// Resolves an integer score to the canonical UrgencyPriority with clamped fallback to `.p3Low`.
    public static func from(score: Int) -> UrgencyPriority {
        switch score {
        case ...0: return .p0Critical
        case 1: return .p1High
        case 2: return .p2Medium
        default: return .p3Low
        }
    }

    /// Canonical human-readable label (e.g. "P0 Critical", "P1 High").
    public var displayName: String {
        switch self {
        case .p0Critical: return "P0 Critical"
        case .p1High: return "P1 High"
        case .p2Medium: return "P2 Medium"
        case .p3Low: return "P3 Low"
        }
    }

    public var urgencyLabel: String {
        displayName
    }

    /// Canonical SF Symbol icon name for this priority tier.
    public var iconName: String {
        switch self {
        case .p0Critical: return "exclamationmark.octagon.fill"
        case .p1High: return "exclamationmark.triangle.fill"
        case .p2Medium: return "arrow.up.circle.fill"
        case .p3Low: return "info.circle.fill"
        }
    }
}

extension EmailTriageDecision {
    /// Resolved urgency priority tier.
    public var priority: UrgencyPriority {
        UrgencyPriority.from(score: urgencyScore)
    }

    /// Human-readable urgency label.
    public var urgencyLabel: String {
        priority.displayName
    }
}

extension Int {
    /// Maps an integer urgency score to canonical UrgencyPriority.
    public var urgencyPriority: UrgencyPriority {
        UrgencyPriority.from(score: self)
    }

    /// Human-readable urgency label for an integer urgency score.
    public var urgencyLabel: String {
        urgencyPriority.displayName
    }
}
