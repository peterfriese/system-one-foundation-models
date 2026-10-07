import Foundation
import Observation

/// Individual email triage evaluation record captured during the active application launch.
public struct EvaluationRecord: Identifiable, Sendable, Hashable, Codable {
    public let id: UUID
    public let timestamp: Date
    public let backend: TriageBackend
    public let emailSubject: String
    public let latencyMs: Double
    public let category: EmailCategory
    public let urgency: UrgencyPriority
    public let routingTier: RoutingPolicy
    public let confidence: Double?

    public init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        backend: TriageBackend,
        emailSubject: String,
        latencyMs: Double,
        category: EmailCategory,
        urgency: UrgencyPriority,
        routingTier: RoutingPolicy,
        confidence: Double? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.backend = backend
        self.emailSubject = emailSubject
        self.latencyMs = latencyMs
        self.category = category
        self.urgency = urgency
        self.routingTier = routingTier
        self.confidence = confidence
    }

    public init(email: Email, result: TriageResult, timestamp: Date = Date()) {
        self.id = UUID()
        self.timestamp = timestamp
        self.backend = result.backendUsed
        self.emailSubject = email.subject
        self.latencyMs = result.latencyMs
        self.category = result.decision.category
        self.urgency = result.decision.priority
        self.routingTier = result.routingTier
        self.confidence = result.confidenceScore
    }
}

/// Aggregated statistical metrics and latency distribution for a specific triage backend.
public struct BackendBenchmarkStats: Identifiable, Sendable, Hashable, Codable {
    public var id: TriageBackend { backend }
    public let backend: TriageBackend
    public let sampleCount: Int
    public let meanLatencyMs: Double
    public let p50LatencyMs: Double
    public let p95LatencyMs: Double
    public let minLatencyMs: Double
    public let maxLatencyMs: Double
    public let autoPercentage: Double
    public let escalatePercentage: Double

    public init(
        backend: TriageBackend,
        sampleCount: Int,
        meanLatencyMs: Double,
        p50LatencyMs: Double,
        p95LatencyMs: Double,
        minLatencyMs: Double,
        maxLatencyMs: Double,
        autoPercentage: Double,
        escalatePercentage: Double
    ) {
        self.backend = backend
        self.sampleCount = sampleCount
        self.meanLatencyMs = meanLatencyMs
        self.p50LatencyMs = p50LatencyMs
        self.p95LatencyMs = p95LatencyMs
        self.minLatencyMs = minLatencyMs
        self.maxLatencyMs = maxLatencyMs
        self.autoPercentage = autoPercentage
        self.escalatePercentage = escalatePercentage
    }

    public init(backend: TriageBackend, records: [EvaluationRecord]) {
        self.backend = backend
        let matching = records.filter { $0.backend == backend }
        self.sampleCount = matching.count

        guard !matching.isEmpty else {
            self.meanLatencyMs = 0
            self.p50LatencyMs = 0
            self.p95LatencyMs = 0
            self.minLatencyMs = 0
            self.maxLatencyMs = 0
            self.autoPercentage = 0
            self.escalatePercentage = 0
            return
        }

        let latencies = matching.map(\.latencyMs).sorted()
        let count = Double(matching.count)
        self.minLatencyMs = latencies.first ?? 0
        self.maxLatencyMs = latencies.last ?? 0
        self.meanLatencyMs = latencies.reduce(0, +) / count

        let p50Index = Int((Double(latencies.count - 1) * 0.50).rounded())
        let p95Index = Int((Double(latencies.count - 1) * 0.95).rounded())
        self.p50LatencyMs = latencies[p50Index]
        self.p95LatencyMs = latencies[p95Index]

        let autoCount = matching.filter { $0.routingTier == .auto }.count
        let escalateCount = matching.filter { $0.routingTier == .escalate }.count
        self.autoPercentage = (Double(autoCount) / count) * 100.0
        self.escalatePercentage = (Double(escalateCount) / count) * 100.0
    }

    public var formattedMeanLatency: String {
        formatLatency(meanLatencyMs)
    }

    public var formattedP50Latency: String {
        formatLatency(p50LatencyMs)
    }

    public var formattedP95Latency: String {
        formatLatency(p95LatencyMs)
    }

    public var formattedAutoPercentage: String {
        String(format: "%.1f%%", autoPercentage)
    }

    public var formattedEscalatePercentage: String {
        String(format: "%.1f%%", escalatePercentage)
    }

    private func formatLatency(_ ms: Double) -> String {
        if ms >= 1000.0 {
            return String(format: "%.2f s", ms / 1000.0)
        } else {
            return String(format: "%.1f ms", ms)
        }
    }
}

/// `@Observable @MainActor` store maintaining in-memory evaluation records and comparative
/// benchmark statistics across all triage backends evaluated during the current application launch.
@Observable
@MainActor
public final class BenchmarkSessionStore {
    public private(set) var records: [EvaluationRecord] = []

    public init(records: [EvaluationRecord] = []) {
        self.records = records
    }

    /// Total count of evaluations recorded during the current app session.
    public var totalEvaluations: Int {
        records.count
    }

    /// Distinct backends that have at least one evaluation recorded in this session.
    public var activeBackends: [TriageBackend] {
        let set = Set(records.map(\.backend))
        return TriageBackend.allCases.filter { set.contains($0) }
    }

    /// Number of distinct backends active in this session.
    public var activeBackendCount: Int {
        activeBackends.count
    }

    /// Summary statistics for all active backends with evaluation records.
    public var backendStatistics: [BackendBenchmarkStats] {
        activeBackends.map { statistics(for: $0) }
    }

    /// Returns calculated statistics for a specific backend.
    public func statistics(for backend: TriageBackend) -> BackendBenchmarkStats {
        BackendBenchmarkStats(backend: backend, records: records)
    }

    /// Records a single evaluation into the session store.
    public func record(email: Email, result: TriageResult) {
        let record = EvaluationRecord(email: email, result: result)
        records.append(record)
    }

    /// Records a batch of evaluations into the session store.
    public func recordBatch(results: [(Email, TriageResult)]) {
        for (email, result) in results {
            record(email: email, result: result)
        }
    }

    /// Resets all accumulated session records.
    public func clearSession() {
        records.removeAll()
    }

    /// Generates a GitHub-flavored Markdown report comparing performance across backends.
    public func exportMarkdown() -> String {
        let hw = BenchmarkHardwareInfo.current
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        formatter.timeZone = TimeZone.current
        let dateString = formatter.string(from: Date())

        var md = """
        # Mail Triage Benchmark Comparison

        - **Date:** \(dateString)
        - **Device:** \(hw.deviceModel)
        - **Chip:** \(hw.chipName)
        - **OS Version:** \(hw.osVersion)
        - **Total Evaluations:** \(records.count)
        - **Active Backends:** \(activeBackendCount)

        ## Performance Summary

        | Backend | Mode | Samples | Mean Latency | P50 (Median) | P95 | Auto % | Escalate % |
        |:---|:---|:---:|:---:|:---:|:---:|:---:|:---:|

        """

        let stats = backendStatistics
        if stats.isEmpty {
            md += "| — | — | 0 | — | — | — | — | — |\n"
        } else {
            for stat in stats {
                let mean = stat.formattedMeanLatency
                let p50 = stat.formattedP50Latency
                let p95 = stat.formattedP95Latency
                let auto = stat.formattedAutoPercentage
                let esc = stat.formattedEscalatePercentage
                md += "| \(stat.backend.displayName) | \(stat.backend.privacyLevel.rawValue) | \(stat.sampleCount) | \(mean) | \(p50) | \(p95) | \(auto) | \(esc) |\n"
            }
        }

        return md
    }

    /// Generates comma-separated values (CSV) representation of all session evaluation records.
    public func exportCSV() -> String {
        let formatter = ISO8601DateFormatter()
        var csv = "id,timestamp,backend,emailSubject,latencyMs,category,urgency,routingTier,confidence\n"

        for record in records {
            let timestampStr = formatter.string(from: record.timestamp)
            let escapedSubject = escapeCSV(record.emailSubject)
            let confidenceStr = record.confidence.map { String(format: "%.4f", $0) } ?? ""
            let latencyStr = String(format: "%.2f", record.latencyMs)

            csv += "\(record.id.uuidString),\(timestampStr),\(record.backend.rawValue),\(escapedSubject),\(latencyStr),\(record.category.rawValue),\(record.urgency.displayName),\(record.routingTier.rawValue),\(confidenceStr)\n"
        }

        return csv
    }

    private func escapeCSV(_ value: String) -> String {
        if value.contains(",") || value.contains("\"") || value.contains("\n") || value.contains("\r") {
            let escaped = value.replacingOccurrences(of: "\"", with: "\"\"")
            return "\"\(escaped)\""
        }
        return value
    }
}
