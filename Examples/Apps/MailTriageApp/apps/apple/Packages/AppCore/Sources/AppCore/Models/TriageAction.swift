import Foundation
import FoundationModels

/// Operational triage action suggestions evaluated as categorical choices.
@Generable
public enum TriageAction: String, Sendable, Hashable, Codable, CaseIterable, Identifiable {
    case immediateAlert
    case quarantineThreat
    case scheduleTask
    case draftReply
    case autoArchive
    case moveToInbox

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .immediateAlert:
            return "Immediate Alert"
        case .quarantineThreat:
            return "Quarantine Threat"
        case .scheduleTask:
            return "Schedule Task"
        case .draftReply:
            return "Draft Reply"
        case .autoArchive:
            return "Auto Archive"
        case .moveToInbox:
            return "Move to Inbox"
        }
    }

    public var iconName: String {
        switch self {
        case .immediateAlert:
            return "bell.badge.fill"
        case .quarantineThreat:
            return "exclamationmark.shield.fill"
        case .scheduleTask:
            return "calendar.badge.plus"
        case .draftReply:
            return "arrowshape.turn.up.left.fill"
        case .autoArchive:
            return "archivebox.fill"
        case .moveToInbox:
            return "tray.and.arrow.down.fill"
        }
    }

    /// Whether this action causes an immediate mailbox transfer or destructive isolation.
    public var isDestructive: Bool {
        switch self {
        case .quarantineThreat, .autoArchive:
            return true
        case .immediateAlert, .scheduleTask, .draftReply, .moveToInbox:
            return false
        }
    }

    /// Whether this action is considered high-impact (e.g. security threat quarantine or immediate interruption).
    public var isHighImpact: Bool {
        switch self {
        case .immediateAlert, .quarantineThreat:
            return true
        case .scheduleTask, .draftReply, .autoArchive, .moveToInbox:
            return false
        }
    }
}
