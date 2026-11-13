import Foundation

/// Encapsulates the output of evaluating an email with a System One or Foundation Models engine.
public struct TriageResult: Sendable, Hashable, Codable, Identifiable {
    public let id: UUID
    public let decision: EmailTriageDecision
    public let confidenceScore: Double?
    public let decisiveness: Double?
    public let routingTier: RoutingPolicy
    public let latencyMs: Double
    public let backendUsed: TriageBackend

    public init(
        id: UUID = UUID(),
        decision: EmailTriageDecision,
        confidenceScore: Double?,
        decisiveness: Double?,
        routingTier: RoutingPolicy,
        latencyMs: Double,
        backendUsed: TriageBackend
    ) {
        self.id = id
        self.decision = decision
        self.confidenceScore = confidenceScore
        self.decisiveness = decisiveness
        self.routingTier = routingTier
        self.latencyMs = latencyMs
        self.backendUsed = backendUsed
    }

    /// Formatted confidence certainty string (e.g. "96.4% Certainty" or "Uncalibrated").
    public var confidencePercentage: String {
        guard let confidenceScore else {
            return "Uncalibrated"
        }
        let percent = confidenceScore * 100.0
        return String(format: "%.1f%% Certainty", percent)
    }

    /// Formatted short confidence string (e.g. "96%" or "N/A").
    public var shortConfidence: String {
        guard let confidenceScore else {
            return "N/A"
        }
        let percent = Int(round(confidenceScore * 100.0))
        return "\(percent)%"
    }

    /// Formatted latency string (e.g. "8.4 ms").
    public var formattedLatency: String {
        if latencyMs >= 1000.0 {
            return String(format: "%.2f s", latencyMs / 1000.0)
        } else {
            return String(format: "%.1f ms", latencyMs)
        }
    }

    /// Status badge label for the decision action bar.
    public var statusBadgeText: String {
        routingTier.statusBadgeText
    }
}
