import Foundation
import FoundationModels

@Generable
public enum EmailCategory: String, Identifiable, CaseIterable, Sendable, Codable, Hashable {
    case securityAlerts
    case billing
    case work
    case meetings
    case newsletters
    case quarantine

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .securityAlerts:
            return "Security Alert"
        case .billing:
            return "Billing & Invoices"
        case .work:
            return "Work & Tasks"
        case .meetings:
            return "Meeting"
        case .newsletters:
            return "Newsletter"
        case .quarantine:
            return "Quarantine / Threat"
        }
    }

    public var iconName: String {
        switch self {
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
        }
    }
}
