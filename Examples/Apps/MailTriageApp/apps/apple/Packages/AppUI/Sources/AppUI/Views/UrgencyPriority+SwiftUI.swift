import SwiftUI
import AppCore

extension UrgencyPriority {
    /// Canonical SwiftUI Color representing urgency priority.
    public var color: Color {
        switch self {
        case .p0Critical:
            return .red
        case .p1High:
            return .orange
        case .p2Medium:
            return .blue
        case .p3Low:
            return .secondary
        }
    }
}

extension Int {
    /// Canonical SwiftUI Color mapped from urgency score.
    public var urgencyColor: Color {
        urgencyPriority.color
    }
}
