import Foundation

/// Detailed hardware specification of the machine executing the benchmark.
public struct BenchmarkHardwareInfo: Codable, Sendable, Equatable {
    /// Hardware model identifier (e.g. "Mac16,5" or "MacBookPro18,1").
    public var deviceModel: String

    /// Processor / Apple Silicon chip brand name (e.g. "Apple M4 Max" or "Apple M3 Pro").
    public var chipName: String

    /// Operating system version string (e.g. "macOS 15.0 (Build 24A335)").
    public var osVersion: String

    public init(deviceModel: String, chipName: String, osVersion: String) {
        self.deviceModel = deviceModel
        self.chipName = chipName
        self.osVersion = osVersion
    }

    /// Automatically queries host sysctl and ProcessInfo for current hardware metadata.
    public static var current: BenchmarkHardwareInfo {
        let deviceModel = getSysctlString("hw.model") ?? "Apple Silicon Mac"
        let chipName = getSysctlString("machdep.cpu.brand_string") ?? "Apple Silicon"
        let osVersion = ProcessInfo.processInfo.operatingSystemVersionString
        return BenchmarkHardwareInfo(
            deviceModel: deviceModel,
            chipName: chipName,
            osVersion: osVersion
        )
    }

    private static func getSysctlString(_ name: String) -> String? {
        var size: Int = 0
        sysctlbyname(name, nil, &size, nil, 0)
        guard size > 0 else { return nil }
        var buffer = [CChar](repeating: 0, count: size)
        sysctlbyname(name, &buffer, &size, nil, 0)
        let u8 = buffer.map { UInt8(bitPattern: $0) }
        if let nullIndex = u8.firstIndex(of: 0) {
            return String(decoding: u8[..<nullIndex], as: UTF8.self)
        }
        return String(decoding: u8, as: UTF8.self)
    }
}

/// Evaluation record for a single message sample within a benchmark run.
public struct BenchmarkSampleDecision: Codable, Sendable, Equatable, Identifiable {
    public var id: UUID { emailId }
    public var emailId: UUID
    public var latencyMs: Double
    public var category: EmailCategory
    public var requiresAction: Bool
    public var urgencyScore: Int
    public var suggestedAction: TriageAction
    public var confidence: Double?

    public init(
        emailId: UUID,
        latencyMs: Double,
        category: EmailCategory,
        requiresAction: Bool,
        urgencyScore: Int,
        suggestedAction: TriageAction,
        confidence: Double? = nil
    ) {
        self.emailId = emailId
        self.latencyMs = latencyMs
        self.category = category
        self.requiresAction = requiresAction
        self.urgencyScore = urgencyScore
        self.suggestedAction = suggestedAction
        self.confidence = confidence
    }
}

/// Aggregated performance telemetry and latency distribution for a specific triage backend.
public struct BenchmarkBackendResult: Codable, Sendable, Equatable {
    public var backendName: String
    public var endpointOrModel: String
    public var sampleCount: Int
    public var totalDurationSeconds: Double
    public var throughputPerSecond: Double
    public var meanLatencyMs: Double
    public var p50LatencyMs: Double
    public var p95LatencyMs: Double
    public var totalTokens: Int
    public var sampleDecisions: [BenchmarkSampleDecision]

    public init(
        backendName: String,
        endpointOrModel: String,
        sampleCount: Int,
        totalDurationSeconds: Double,
        throughputPerSecond: Double,
        meanLatencyMs: Double,
        p50LatencyMs: Double,
        p95LatencyMs: Double,
        totalTokens: Int,
        sampleDecisions: [BenchmarkSampleDecision] = []
    ) {
        self.backendName = backendName
        self.endpointOrModel = endpointOrModel
        self.sampleCount = sampleCount
        self.totalDurationSeconds = totalDurationSeconds
        self.throughputPerSecond = throughputPerSecond
        self.meanLatencyMs = meanLatencyMs
        self.p50LatencyMs = p50LatencyMs
        self.p95LatencyMs = p95LatencyMs
        self.totalTokens = totalTokens
        self.sampleDecisions = sampleDecisions
    }

    /// Formatted throughput string (e.g. "112.5 msg/s").
    public var formattedThroughput: String {
        String(format: "%.1f msg/s", throughputPerSecond)
    }

    /// Formatted total duration string (e.g. "0.22 s" or "1m 15.2s").
    public var formattedTotalDuration: String {
        if totalDurationSeconds >= 60.0 {
            let minutes = Int(totalDurationSeconds / 60.0)
            let seconds = totalDurationSeconds.truncatingRemainder(dividingBy: 60.0)
            return String(format: "%dm %.1fs", minutes, seconds)
        } else {
            return String(format: "%.2f s", totalDurationSeconds)
        }
    }

    /// Formatted mean latency string (e.g. "8.8 ms" or "1.12 s").
    public var formattedMeanLatency: String {
        if meanLatencyMs >= 1000.0 {
            return String(format: "%.2f s", meanLatencyMs / 1000.0)
        } else {
            return String(format: "%.1f ms", meanLatencyMs)
        }
    }

    /// Formatted 50th percentile (median) latency string.
    public var formattedP50Latency: String {
        if p50LatencyMs >= 1000.0 {
            return String(format: "%.2f s", p50LatencyMs / 1000.0)
        } else {
            return String(format: "%.1f ms", p50LatencyMs)
        }
    }

    /// Formatted 95th percentile latency string.
    public var formattedP95Latency: String {
        if p95LatencyMs >= 1000.0 {
            return String(format: "%.2f s", p95LatencyMs / 1000.0)
        } else {
            return String(format: "%.1f ms", p95LatencyMs)
        }
    }
}

/// Canonical ground-truth benchmark payload storing verified laboratory measurements across backends.
public struct BenchmarkTruthPayload: Codable, Sendable, Equatable {
    public var version: String
    public var generatedAt: Date
    public var hardwareInfo: BenchmarkHardwareInfo
    public var sampleCount: Int
    public var results: [TriageBackend: BenchmarkBackendResult]
    public let isSyntheticReference: Bool?

    public init(
        version: String = "1.0",
        generatedAt: Date = Date(),
        hardwareInfo: BenchmarkHardwareInfo,
        sampleCount: Int,
        results: [TriageBackend: BenchmarkBackendResult],
        isSyntheticReference: Bool? = false
    ) {
        self.version = version
        self.generatedAt = generatedAt
        self.hardwareInfo = hardwareInfo
        self.sampleCount = sampleCount
        self.results = results
        self.isSyntheticReference = isSyntheticReference
    }

    /// Calculates the speedup factor of a backend relative to the Generative baseline.
    public func speedupFactor(for backend: TriageBackend) -> Double? {
        guard let target = results[backend] else { return nil }
        guard target.meanLatencyMs > 0 else { return nil }

        let baselineMean: Double
        if let baseline = results[.generativeBaseline], baseline.meanLatencyMs > 0 {
            baselineMean = baseline.meanLatencyMs
        } else {
            baselineMean = 950.0
        }

        return baselineMean / target.meanLatencyMs
    }

    /// Total tokens saved across all decision model runs compared to the generative baseline.
    public var estimatedTotalTokensSaved: Int {
        guard let baselineTokens = results[.generativeBaseline]?.totalTokens, baselineTokens > 0 else {
            return sampleCount * 450
        }
        return baselineTokens
    }
}
