import Foundation

/// Performance and classification analytics generated from a batch inbox triage run.
public struct BatchTriageReport: Sendable, Hashable, Codable, Identifiable {
    public let id: UUID
    public let totalProcessed: Int
    public let totalDurationSeconds: Double
    public let averageLatencyMs: Double
    public let actionBreakdown: [TriageAction: Int]
    public let routingBreakdown: [RoutingPolicy: Int]
    public let backend: TriageBackend
    public let timestamp: Date

    public init(
        id: UUID = UUID(),
        totalProcessed: Int,
        totalDurationSeconds: Double,
        averageLatencyMs: Double,
        actionBreakdown: [TriageAction: Int],
        routingBreakdown: [RoutingPolicy: Int] = [:],
        backend: TriageBackend,
        timestamp: Date = Date()
    ) {
        self.id = id
        self.totalProcessed = totalProcessed
        self.totalDurationSeconds = totalDurationSeconds
        self.averageLatencyMs = averageLatencyMs
        self.actionBreakdown = actionBreakdown
        self.routingBreakdown = routingBreakdown
        self.backend = backend
        self.timestamp = timestamp
    }

    /// Aggregate throughput in messages processed per second.
    public var throughputPerSecond: Double {
        guard totalDurationSeconds > 0 else { return 0 }
        return Double(totalProcessed) / totalDurationSeconds
    }

    /// Formatted throughput string (e.g. "84.2 msgs/sec").
    public var formattedThroughput: String {
        String(format: "%.1f msgs/sec", throughputPerSecond)
    }

    /// Formatted total duration string (e.g. "5.82 s" or "1m 12.4s").
    public var formattedDuration: String {
        if totalDurationSeconds >= 60.0 {
            let minutes = Int(totalDurationSeconds / 60.0)
            let seconds = totalDurationSeconds.truncatingRemainder(dividingBy: 60.0)
            return String(format: "%dm %.1fs", minutes, seconds)
        } else {
            return String(format: "%.2f s", totalDurationSeconds)
        }
    }

    /// Formatted average latency (e.g. "9.4 ms").
    public var formattedAverageLatency: String {
        if averageLatencyMs >= 1000.0 {
            return String(format: "%.2f s", averageLatencyMs / 1000.0)
        } else {
            return String(format: "%.1f ms", averageLatencyMs)
        }
    }

    // MARK: - Benchmark Comparison vs Generative Baseline

    /// Assumed average latency for Apple Intelligence / Generative 3B LLM baseline (~950 ms).
    public static let baselineGenerativeLatencyMs: Double = 950.0

    /// Calculated speedup multiplier over the generative baseline.
    public var baselineSpeedupFactor: Double {
        guard averageLatencyMs > 0 else { return 1.0 }
        return Self.baselineGenerativeLatencyMs / averageLatencyMs
    }

    /// Estimated wall-clock time saved compared to running generative LLMs for the same batch.
    public var estimatedTimeSavedSeconds: Double {
        let baselineTotalSec = (Double(totalProcessed) * Self.baselineGenerativeLatencyMs) / 1000.0
        return max(0, baselineTotalSec - totalDurationSeconds)
    }

    /// Estimated LLM tokens saved (assuming ~450 prompt + output tokens per email).
    public var estimatedTokensSaved: Int {
        totalProcessed * 450
    }
}
