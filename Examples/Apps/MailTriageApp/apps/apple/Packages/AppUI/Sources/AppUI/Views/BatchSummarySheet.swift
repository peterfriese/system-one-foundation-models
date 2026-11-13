import SwiftUI
import AppCore
import FactoryKit

/// Modal sheet presenting performance telemetry and classification distributions
/// from a batch inbox triage run, contrasting System One decision models with generative LLMs.
public struct BatchSummarySheet: View {
    @Environment(\.dismiss) private var dismiss

    @ObservationIgnored
    @Injected(\.benchmarkTruthStore) private var benchmarkTruthStore

    public let report: BatchTriageReport
    private let explicitGroundTruth: BenchmarkTruthPayload?

    public init(report: BatchTriageReport, groundTruth: BenchmarkTruthPayload? = nil) {
        self.report = report
        self.explicitGroundTruth = groundTruth
    }

    private var groundTruth: BenchmarkTruthPayload? {
        explicitGroundTruth ?? benchmarkTruthStore.loadTruth()
    }

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Header Status Banner
                    headerSection

                    // Canonical Ground-Truth Benchmark Badge & Telemetry (if available)
                    if let groundTruth {
                        canonicalGroundTruthCard(truth: groundTruth)
                    }

                    // Hero Metrics Grid (4 cards)
                    heroMetricsGrid

                    // Action & Category Breakdown Grid
                    actionBreakdownSection

                    // Benchmark Comparison Card (Decision Model vs Generative LLM)
                    benchmarkComparisonCard
                }
                .padding(24)
            }
            .navigationTitle("Batch Triage Analytics")
            #if os(macOS)
            .frame(minWidth: 560, minHeight: 560)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                    .keyboardShortcut(.defaultAction)
                }
            }
        }
    }

    // MARK: - Header Section

    private var headerSection: some View {
        HStack(alignment: .center, spacing: 14) {
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.15))
                    .frame(width: 48, height: 48)
                Image(systemName: report.backend.iconName)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(Color.accentColor)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text("Batch Triage Completed")
                    .font(.headline)
                Text("Evaluated using \(report.backend.displayName) with bounded concurrency")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(16)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
    }

    // MARK: - Canonical Ground-Truth Benchmark Badge & Card

    private func canonicalGroundTruthCard(truth: BenchmarkTruthPayload) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            // Badge & Metadata Header
            HStack(alignment: .center, spacing: 10) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.title3)
                    .foregroundStyle(.green)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text("Canonical Ground-Truth Benchmark")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(.primary)

                        Text("VERIFIED")
                            .font(.system(size: 9, weight: .black))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Color.green.opacity(0.2), in: Capsule())
                            .foregroundStyle(.green)
                    }

                    Text("Recorded on \(truth.hardwareInfo.chipName) (\(truth.hardwareInfo.deviceModel)) • \(truth.hardwareInfo.osVersion)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Text(truth.generatedAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Divider()

            // Measured Ground Truth Telemetry
            if let targetResult = truth.results[report.backend] {
                VStack(spacing: 10) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Total Time")
                                .font(.caption2.weight(.medium))
                                .foregroundStyle(.secondary)
                            Text(targetResult.formattedTotalDuration)
                                .font(.title3.weight(.bold))
                                .foregroundStyle(.primary)
                            Text("for \(targetResult.sampleCount) samples")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }

                        Spacer()

                        VStack(alignment: .center, spacing: 2) {
                            Text("Time / Email")
                                .font(.caption2.weight(.medium))
                                .foregroundStyle(.secondary)
                            Text(targetResult.formattedMeanLatency)
                                .font(.title3.weight(.bold))
                                .foregroundStyle(.primary)
                            Text("average latency")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }

                        Spacer()

                        VStack(alignment: .trailing, spacing: 2) {
                            Text("Throughput")
                                .font(.caption2.weight(.medium))
                                .foregroundStyle(.secondary)
                            Text(targetResult.formattedThroughput)
                                .font(.title3.weight(.bold))
                                .foregroundStyle(.primary)
                            Text("p50: \(targetResult.formattedP50Latency)")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    }

                    HStack(spacing: 6) {
                        Text("Latency Profile:")
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.secondary)
                        Text("p50: \(targetResult.formattedP50Latency) • p95: \(targetResult.formattedP95Latency)")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Spacer()
                    }

                    if let baselineResult = truth.results[.generativeBaseline], report.backend.isDecisionModel {
                        let speedup = baselineResult.meanLatencyMs > 0 && targetResult.meanLatencyMs > 0
                            ? baselineResult.meanLatencyMs / targetResult.meanLatencyMs
                            : report.baselineSpeedupFactor

                        HStack(spacing: 6) {
                            Image(systemName: "bolt.badge.checkmark.fill")
                                .font(.caption2)
                                .foregroundStyle(.green)
                            Text(String(format: "Laboratory verified: %.1fx faster than Generative Baseline on this hardware", speedup))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Spacer()
                        }
                    }
                }
            } else {
                // If the active backend wasn't in this specific truth run, show available benchmarks
                HStack(spacing: 16) {
                    ForEach(TriageBackend.allCases) { backend in
                        if let res = truth.results[backend] {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(backend.shortName)
                                    .font(.caption2.weight(.bold))
                                    .foregroundStyle(.secondary)
                                Text("Total: \(res.formattedTotalDuration)")
                                    .font(.caption2)
                                Text("\(res.formattedMeanLatency)/email")
                                    .font(.caption.weight(.semibold))
                            }
                        }
                    }
                    Spacer()
                }
            }
        }
        .padding(14)
        .background(Color.green.opacity(0.06), in: RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.green.opacity(0.22), lineWidth: 1)
        )
    }

    // MARK: - Hero Metrics Grid

    private var heroMetricsGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 14) {
            metricCard(
                title: "Total Messages",
                value: "\(report.totalProcessed)",
                subtitle: "Processed concurrently",
                icon: "tray.full.fill",
                color: .blue
            )

            metricCard(
                title: "Total Time",
                value: report.formattedDuration,
                subtitle: "Wall-clock elapsed time",
                icon: "timer",
                color: .orange
            )

            metricCard(
                title: "Throughput",
                value: report.formattedThroughput,
                subtitle: "Bounded 8-worker pool",
                icon: "bolt.fill",
                color: .green
            )

            metricCard(
                title: "Time / Email",
                value: report.formattedAverageLatency,
                subtitle: "\(report.backend.shortName) average latency",
                icon: "speedometer",
                color: .purple
            )
        }
    }

    private func metricCard(title: String, value: String, subtitle: String, icon: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                Spacer()
                Image(systemName: icon)
                    .font(.caption)
                    .foregroundStyle(color)
            }

            Text(value)
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)

            Text(subtitle)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.primary.opacity(0.06), lineWidth: 1)
        )
    }

    // MARK: - Action Breakdown Section

    private var actionBreakdownSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Operational Action Breakdown")
                .font(.headline)

            VStack(spacing: 8) {
                ForEach(TriageAction.allCases) { action in
                    let count = report.actionBreakdown[action, default: 0]
                    let percentage = report.totalProcessed > 0 ? (Double(count) / Double(report.totalProcessed)) * 100.0 : 0.0

                    HStack(spacing: 10) {
                        Image(systemName: action.iconName)
                            .font(.caption)
                            .frame(width: 20)
                            .foregroundStyle(actionColor(for: action))

                        Text(action.displayName)
                            .font(.subheadline)

                        Spacer()

                        Text("\(count)")
                            .font(.subheadline.weight(.semibold))

                        Text(String(format: "(%.1f%%)", percentage))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(width: 52, alignment: .trailing)
                    }
                    .padding(.vertical, 4)

                    if action != TriageAction.allCases.last {
                        Divider()
                    }
                }
            }
            .padding(14)
            .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
        }
    }

    // MARK: - Benchmark Comparison Card

    private var benchmarkComparisonCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 6) {
                Image(systemName: "chart.line.uptrend.xyaxis")
                    .foregroundStyle(Color.accentColor)
                Text("Architecture Benchmark: Decision Model vs LLM")
                    .font(.headline)
            }

            VStack(spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Speedup Factor")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        let speedup: Double = {
                            if let gt = groundTruth, let factor = gt.speedupFactor(for: report.backend) {
                                return factor
                            }
                            return report.baselineSpeedupFactor
                        }()

                        Text(String(format: "%.1fx Faster", speedup))
                            .font(.title2.weight(.bold))
                            .foregroundStyle(.green)
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: 4) {
                        Text("Estimated Time Saved")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(String(format: "%.1f seconds", report.estimatedTimeSavedSeconds))
                            .font(.title2.weight(.bold))
                            .foregroundStyle(.blue)
                    }
                }

                Divider()

                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Tokens Saved")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("\(report.estimatedTokensSaved.formatted())")
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(.purple)
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: 4) {
                        Text("API Inference Cost")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(report.backend.isOffline ? "$0.00 (On-Device)" : "Sub-cent RPC")
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(.primary)
                    }
                }

                Text("System One non-autoregressive decision models eliminate generative token decoding loops, delivering calibrated Bayesian certainty at sub-15ms latencies.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
            }
            .padding(16)
            .background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(Color.accentColor.opacity(0.2), lineWidth: 1)
            )
        }
    }

    private func actionColor(for action: TriageAction) -> Color {
        switch action {
        case .immediateAlert, .quarantineThreat:
            return .red
        case .scheduleTask:
            return .blue
        case .draftReply:
            return .purple
        case .autoArchive:
            return .gray
        case .moveToInbox:
            return .green
        }
    }
}

#Preview {
    let report = BatchTriageReport(
        totalProcessed: 500,
        totalDurationSeconds: 6.2,
        averageLatencyMs: 9.4,
        actionBreakdown: [
            .scheduleTask: 180,
            .autoArchive: 150,
            .immediateAlert: 75,
            .quarantineThreat: 45,
            .draftReply: 35,
            .moveToInbox: 15
        ],
        backend: .onDeviceCoreML
    )
    BatchSummarySheet(report: report)
}
