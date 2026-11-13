import Foundation

public enum Mailbox: String, Identifiable, CaseIterable, Sendable, Codable, Hashable {
    // Favorites
    case inbox
    case vips
    case flagged
    case drafts
    case sent

    // Decision Categories
    case securityAlerts
    case billing
    case work
    case meetings
    case newsletters
    case quarantine
    case archive

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .inbox:
            return "Inbox"
        case .vips:
            return "VIPs"
        case .flagged:
            return "Flagged"
        case .drafts:
            return "Drafts"
        case .sent:
            return "Sent"
        case .securityAlerts:
            return "Security Alerts"
        case .billing:
            return "Billing & Invoices"
        case .work:
            return "Work & Tasks"
        case .meetings:
            return "Meetings"
        case .newsletters:
            return "Newsletters & Feeds"
        case .quarantine:
            return "Quarantine"
        case .archive:
            return "Archive"
        }
    }

    public var iconName: String {
        switch self {
        case .inbox:
            return "tray.fill"
        case .vips:
            return "star.fill"
        case .flagged:
            return "flag.fill"
        case .drafts:
            return "doc.fill"
        case .sent:
            return "paperplane.fill"
        case .securityAlerts:
            return "shield.lefthalf.filled"
        case .billing:
            return "creditcard.fill"
        case .work:
            return "briefcase.fill"
        case .meetings:
            return "calendar"
        case .newsletters:
            return "newspaper.fill"
        case .quarantine:
            return "exclamationmark.shield.fill"
        case .archive:
            return "archivebox.fill"
        }
    }

    public var isFavorite: Bool {
        switch self {
        case .inbox, .vips, .flagged, .drafts, .sent:
            return true
        default:
            return false
        }
    }

    public var isCategory: Bool {
        !isFavorite
    }

    public static let favorites: [Mailbox] = [
        .inbox,
        .vips,
        .flagged,
        .drafts,
        .sent
    ]

    public static let categories: [Mailbox] = [
        .securityAlerts,
        .billing,
        .work,
        .meetings,
        .newsletters,
        .quarantine,
        .archive
    ]
}
