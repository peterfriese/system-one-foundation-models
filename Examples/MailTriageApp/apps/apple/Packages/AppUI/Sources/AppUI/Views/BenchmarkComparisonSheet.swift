import SwiftUI
import UniformTypeIdentifiers
import AppCore
import FactoryKit
#if os(macOS)
import AppKit
#elseif os(iOS)
import UIKit
#endif

/// Columns available for sorting the comparative benchmark table.
public enum BenchmarkSortColumn: String, CaseIterable, Identifiable, Sendable {
    case backend = "Backend"
    case mode = "Mode"
    case samples = "Samples"
    case meanLatency = "Mean Latency"
    case p50 = "P50"
    case p95 = "P95"
    case autoRate = "Auto %"
    case escalateRate = "Escalate %"

    public var id: String { rawValue }
    public var title: String { rawValue }

    /// Default sort direction when selecting this column.
    /// Latencies and text default to ascending; counts and rates default to descending.
    public var defaultAscending: Bool {
        switch self {
        case .backend, .mode, .meanLatency, .p50, .p95:
            return true
        case .samples, .autoRate, .escalateRate:
            return false
        }
    }
}

/// Comprehensive modal comparison sheet analyzing latency distributions, routing accuracy,
/// and automated decision confidence across all evaluated backends in the active session.
public struct BenchmarkComparisonSheet: View {
    @Environment(\.dismiss) private var dismiss

    @ObservationIgnored
    @Injected(\.benchmarkSessionStore) private var sessionStore

    @State private var copiedMarkdown: Bool = false
    @State private var copiedCSV: Bool = false
    @State private var showingClearConfirmation: Bool = false
    @State private var selectedDetailFilter: TriageBackend? = nil
    @State private var sortColumn: BenchmarkSortColumn = .meanLatency
    @State private var sortAscending: Bool = true

    public init() {
        self.init(sortColumn: .meanLatency, sortAscending: true)
    }

    init(sortColumn: BenchmarkSortColumn = .meanLatency, sortAscending: Bool = true) {
        _sortColumn = State(initialValue: sortColumn)
        _sortAscending = State(initialValue: sortAscending)
    }

    var sortedStatistics: [BackendBenchmarkStats] {
        sessionStore.backendStatistics.sorted { a, b in
            // Prioritize backends with recorded samples over 0-sample backends
            if (a.sampleCount > 0) != (b.sampleCount > 0) {
                return a.sampleCount > 0
            }

            let isOrderedBefore: Bool
            switch sortColumn {
            case .backend:
                let cmp = a.backend.displayName.localizedCaseInsensitiveCompare(b.backend.displayName)
                if cmp != .orderedSame {
                    isOrderedBefore = cmp == .orderedAscending
                } else {
                    return a.backend.displayName < b.backend.displayName
                }
            case .mode:
                let cmp = a.backend.privacyLevel.rawValue.localizedCaseInsensitiveCompare(b.backend.privacyLevel.rawValue)
                if cmp != .orderedSame {
                    isOrderedBefore = cmp == .orderedAscending
                } else {
                    return a.backend.displayName < b.backend.displayName
                }
            case .samples:
                if a.sampleCount != b.sampleCount {
                    isOrderedBefore = a.sampleCount < b.sampleCount
                } else {
                    return a.backend.displayName < b.backend.displayName
                }
            case .meanLatency:
                if a.meanLatencyMs != b.meanLatencyMs {
                    isOrderedBefore = a.meanLatencyMs < b.meanLatencyMs
                } else {
                    return a.backend.displayName < b.backend.displayName
                }
            case .p50:
                if a.p50LatencyMs != b.p50LatencyMs {
                    isOrderedBefore = a.p50LatencyMs < b.p50LatencyMs
                } else {
                    return a.backend.displayName < b.backend.displayName
                }
            case .p95:
                if a.p95LatencyMs != b.p95LatencyMs {
                    isOrderedBefore = a.p95LatencyMs < b.p95LatencyMs
                } else {
                    return a.backend.displayName < b.backend.displayName
                }
            case .autoRate:
                if a.autoPercentage != b.autoPercentage {
                    isOrderedBefore = a.autoPercentage < b.autoPercentage
                } else {
                    return a.backend.displayName < b.backend.displayName
                }
            case .escalateRate:
                if a.escalatePercentage != b.escalatePercentage {
                    isOrderedBefore = a.escalatePercentage < b.escalatePercentage
                } else {
                    return a.backend.displayName < b.backend.displayName
                }
            }

            return sortAscending ? isOrderedBefore : !isOrderedBefore
        }
    }

    private var fastestBackend: TriageBackend? {
        let statsWithSamples = sessionStore.backendStatistics.filter { $0.sampleCount > 0 }
        return statsWithSamples.min(by: { $0.meanLatencyMs < $1.meanLatencyMs })?.backend
    }

    private var filteredRecords: [EvaluationRecord] {
        if let selectedDetailFilter {
            return sessionStore.records.filter { $0.backend == selectedDetailFilter }
        }
        return sessionStore.records
    }

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Top Summary Card
                    sessionSummaryHeader

                    // Comparative Performance Table
                    comparativeTableSection

                    // Detailed Evaluations Table
                    detailedEvaluationsSection
                }
                .padding(.horizontal, 32)
                .padding(.vertical, 24)
                .frame(maxWidth: .infinity)
            }
            .navigationTitle("Model Benchmark Comparison")
            #if os(macOS)
            .frame(minWidth: 960, idealWidth: 1040, minHeight: 680, idealHeight: 760)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                    .keyboardShortcut(.defaultAction)
                }
            }
            .confirmationDialog(
                "Clear Benchmark Session?",
                isPresented: $showingClearConfirmation,
                titleVisibility: .visible
            ) {
                Button("Clear Session Data", role: .destructive) {
                    sessionStore.clearSession()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This will delete all \(sessionStore.totalEvaluations) evaluation records collected during this application launch.")
            }
        }
    }

    // MARK: - Header Session Summary

    private var sessionSummaryHeader: some View {
        VStack(spacing: 14) {
            HStack(alignment: .center, spacing: 20) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Image(systemName: "gauge.with.needle.fill")
                            .font(.title2)
                            .foregroundStyle(Color.accentColor)
                        Text("Application Launch Benchmark")
                            .font(.title3.weight(.bold))
                    }
                    Text("Real execution telemetry across System One decision models, Core ML, and Cloudflare Workers AI edge models.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                // Metric Counters
                HStack(spacing: 12) {
                    metricCounter(
                        title: "Total Evaluations",
                        value: "\(sessionStore.totalEvaluations)",
                        icon: "tray.full.fill",
                        color: .blue
                    )

                    metricCounter(
                        title: "Active Backends",
                        value: "\(sessionStore.activeBackendCount)",
                        icon: "server.rack",
                        color: .purple
                    )

                    if let fastest = fastestBackend,
                       let fastestStats = sessionStore.backendStatistics.first(where: { $0.backend == fastest }) {
                        metricCounter(
                            title: "Fastest Model",
                            value: fastestStats.formattedP50Latency,
                            subtitle: fastest.shortName,
                            icon: "bolt.fill",
                            color: .green
                        )
                    }
                }
            }

            Divider()

            // Prominent Top Action Bar
            HStack(spacing: 10) {
                // Copy Markdown Button
                Button {
                    handleCopyMarkdown()
                } label: {
                    Label(
                        copiedMarkdown ? "Copied Markdown" : "Copy Markdown",
                        systemImage: copiedMarkdown ? "checkmark.circle.fill" : "doc.on.doc"
                    )
                }
                .buttonStyle(.bordered)
                .tint(copiedMarkdown ? .green : nil)
                .help("Copy GitHub-flavored Markdown benchmark table to clipboard")

                // Copy CSV Button
                Button {
                    handleCopyCSV()
                } label: {
                    Label(
                        copiedCSV ? "Copied CSV" : "Copy CSV",
                        systemImage: copiedCSV ? "checkmark.circle.fill" : "tablecells"
                    )
                }
                .buttonStyle(.bordered)
                .tint(copiedCSV ? .green : nil)
                .help("Copy evaluation records as CSV to clipboard")

                // Export Menu
                #if os(macOS)
                Menu {
                    Button("Export Markdown (.md)...", systemImage: "doc.text") {
                        exportMarkdownFile()
                    }
                    Button("Export CSV (.csv)...", systemImage: "tablecells") {
                        exportCSVFile()
                    }
                } label: {
                    Label("Export...", systemImage: "square.and.arrow.up")
                }
                .menuStyle(.borderedButton)
                .help("Export benchmark telemetry to a file")
                #elseif os(iOS)
                Menu {
                    ShareLink(item: sessionStore.exportMarkdown()) {
                        Label("Share Markdown (.md)", systemImage: "doc.text")
                    }
                    ShareLink(item: sessionStore.exportCSV()) {
                        Label("Share CSV (.csv)", systemImage: "tablecells")
                    }
                } label: {
                    Label("Export...", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(.bordered)
                #endif

                Spacer()

                // Clear Session Button
                Button(role: .destructive) {
                    showingClearConfirmation = true
                } label: {
                    Label("Clear Session", systemImage: "trash")
                }
                .buttonStyle(.bordered)
                .tint(.red)
                .help("Reset session benchmark evaluations")
            }
            .controlSize(.regular)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .background(Color.secondary.opacity(0.07), in: RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.primary.opacity(0.06), lineWidth: 1)
        )
    }

    private func metricCounter(title: String, value: String, subtitle: String? = nil, icon: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(color)
                Text(title)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value)
                    .font(.headline.weight(.bold).monospacedDigit())
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                if let subtitle {
                    Text("(\(subtitle))")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(color)
                        .lineLimit(1)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(width: 150, height: 56, alignment: .leading)
        .background(color.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(color.opacity(0.2), lineWidth: 1)
        )
    }

    // MARK: - Comparative Table Section

    private var comparativeTableSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Comparative Architecture Performance", systemImage: "chart.bar.xaxis")
                    .font(.headline.weight(.bold))
                Spacer()
                if sessionStore.backendStatistics.isEmpty {
                    Text("No evaluations yet")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("\(sessionStore.backendStatistics.count) architectures evaluated")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if sessionStore.backendStatistics.isEmpty {
                ContentUnavailableView {
                    Label("No Telemetry Recorded", systemImage: "chart.xyaxis.line")
                } description: {
                    Text("Triage emails or run 'Triage All' to populate comparative latency percentiles and routing rates.")
                }
                .padding(.vertical, 32)
                .background(Color.secondary.opacity(0.04), in: RoundedRectangle(cornerRadius: 12))
            } else {
                VStack(spacing: 0) {
                    // Header Row
                    comparativeTableHeader

                    Divider()

                    // Data Rows
                    ForEach(sortedStatistics) { stat in
                        comparativeTableRow(stat: stat)
                        Divider()
                    }
                }
                .background(Color.secondary.opacity(0.04), in: RoundedRectangle(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                )
            }
        }
    }

    private func columnWidth(for column: BenchmarkSortColumn) -> CGFloat {
        switch column {
        case .backend: return 195
        case .mode: return 75
        case .samples: return 65
        case .meanLatency: return 105
        case .p50: return 70
        case .p95: return 70
        case .autoRate: return 65
        case .escalateRate: return 75
        }
    }

    private var comparativeTableHeader: some View {
        HStack(spacing: 12) {
            tableHeaderButton(column: .backend, width: columnWidth(for: .backend), alignment: .leading)
            tableHeaderButton(column: .mode, width: columnWidth(for: .mode), alignment: .leading)
            tableHeaderButton(column: .samples, width: columnWidth(for: .samples), alignment: .trailing)
            tableHeaderButton(column: .meanLatency, width: columnWidth(for: .meanLatency), alignment: .trailing)
            tableHeaderButton(column: .p50, width: columnWidth(for: .p50), alignment: .trailing)
            tableHeaderButton(column: .p95, width: columnWidth(for: .p95), alignment: .trailing)
            tableHeaderButton(column: .autoRate, width: columnWidth(for: .autoRate), alignment: .trailing)
            tableHeaderButton(column: .escalateRate, width: columnWidth(for: .escalateRate), alignment: .trailing)
            Spacer()
        }
        .font(.caption.weight(.bold))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .background(Color.secondary.opacity(0.06))
    }

    private func tableHeaderButton(column: BenchmarkSortColumn, width: CGFloat, alignment: Alignment) -> some View {
        Button {
            handleColumnTap(column)
        } label: {
            HStack(spacing: 4) {
                Text(column.title)
                    .lineLimit(1)

                Image(systemName: (sortColumn == column && !sortAscending) ? "chevron.down" : "chevron.up")
                    .font(.system(size: 8, weight: .bold))
                    .opacity(sortColumn == column ? 1 : 0)
            }
            .frame(width: width, alignment: alignment)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(sortColumn == column ? Color.primary : Color.secondary)
        .help("Sort by \(column.title)")
    }

    private func handleColumnTap(_ column: BenchmarkSortColumn) {
        withAnimation(.easeInOut(duration: 0.15)) {
            if sortColumn == column {
                sortAscending.toggle()
            } else {
                sortColumn = column
                sortAscending = column.defaultAscending
            }
        }
    }

    private func comparativeTableRow(stat: BackendBenchmarkStats) -> some View {
        let isFastest = stat.backend == fastestBackend && stat.sampleCount > 0
        let rowBackground = isFastest ? Color.green.opacity(0.06) : Color.clear

        return HStack(spacing: 12) {
            // Backend Name + Badge
            HStack(spacing: 6) {
                Image(systemName: stat.backend.iconName)
                    .foregroundStyle(isFastest ? Color.green : Color.accentColor)
                    .frame(width: 16)

                Text(stat.backend.displayName)
                    .font(.subheadline.weight(isFastest ? .bold : .medium))
                    .lineLimit(1)

                if isFastest {
                    Text("FASTEST")
                        .font(.system(size: 8, weight: .black))
                        .foregroundStyle(.green)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Color.green.opacity(0.18), in: Capsule())
                }
            }
            .frame(width: columnWidth(for: .backend), alignment: .leading)

            // Mode / Privacy Topology
            Text(stat.backend.privacyLevel.rawValue)
                .font(.caption2.weight(.medium))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.secondary.opacity(0.12), in: Capsule())
                .frame(width: columnWidth(for: .mode), alignment: .leading)

            // Samples
            Text("\(stat.sampleCount)")
                .font(.subheadline.monospacedDigit())
                .frame(width: columnWidth(for: .samples), alignment: .trailing)

            // Mean Latency
            Text(stat.formattedMeanLatency)
                .font(.subheadline.monospacedDigit().weight(isFastest ? .bold : .regular))
                .foregroundStyle(isFastest ? .green : .primary)
                .frame(width: columnWidth(for: .meanLatency), alignment: .trailing)

            // P50
            Text(stat.formattedP50Latency)
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(isFastest ? .green : .primary)
                .frame(width: columnWidth(for: .p50), alignment: .trailing)

            // P95
            Text(stat.formattedP95Latency)
                .font(.subheadline.monospacedDigit())
                .frame(width: columnWidth(for: .p95), alignment: .trailing)

            // Auto %
            Text(stat.formattedAutoPercentage)
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(.green)
                .frame(width: columnWidth(for: .autoRate), alignment: .trailing)

            // Escalate %
            Text(stat.formattedEscalatePercentage)
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(stat.escalatePercentage > 15 ? .orange : .secondary)
                .frame(width: columnWidth(for: .escalateRate), alignment: .trailing)

            Spacer()
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 9)
        .background(rowBackground)
    }

    // MARK: - Detailed Evaluations Table

    private var detailedEvaluationsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Evaluation Log (\(filteredRecords.count))", systemImage: "list.bullet.rectangle.portrait")
                    .font(.headline.weight(.bold))

                Spacer()

                // Filter by backend picker
                if sessionStore.activeBackendCount > 1 {
                    Picker("Filter Backend", selection: $selectedDetailFilter) {
                        Text("All Backends").tag(nil as TriageBackend?)
                        ForEach(sessionStore.activeBackends) { backend in
                            Text(backend.displayName).tag(backend as TriageBackend?)
                        }
                    }
                    .pickerStyle(.menu)
                    .controlSize(.small)
                }
            }

            if filteredRecords.isEmpty {
                Text("No individual evaluations recorded in this session.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 24)
            } else {
                VStack(spacing: 0) {
                    detailedEvaluationsHeader

                    Divider()

                    LazyVStack(spacing: 0) {
                        ForEach(Array(filteredRecords.suffix(100).enumerated()), id: \.element.id) { index, record in
                            detailedEvaluationRow(record: record, index: index)
                            Divider()
                        }
                    }
                }
                .background(Color.secondary.opacity(0.04), in: RoundedRectangle(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                )
            }
        }
    }

    private var detailedEvaluationsHeader: some View {
        HStack(spacing: 8) {
            Text("Time")
                .frame(width: 65, alignment: .leading)
            Text("Backend")
                .frame(width: 95, alignment: .leading)
            Text("Subject")
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("Latency")
                .frame(width: 75, alignment: .trailing)
            Text("Category")
                .frame(width: 95, alignment: .leading)
            Text("Urgency")
                .frame(width: 75, alignment: .leading)
            Text("Routing")
                .frame(width: 85, alignment: .leading)
            Text("Confidence")
                .frame(width: 65, alignment: .trailing)
        }
        .font(.caption.weight(.bold))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 18)
        .padding(.vertical, 8)
        .background(Color.secondary.opacity(0.06))
    }

    private func detailedEvaluationRow(record: EvaluationRecord, index: Int) -> some View {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        let timeStr = formatter.string(from: record.timestamp)

        let confText: String = {
            if let c = record.confidence {
                return String(format: "%.1f%%", c * 100.0)
            }
            return "N/A"
        }()

        let latencyText = record.latencyMs >= 1000.0
            ? String(format: "%.2f s", record.latencyMs / 1000.0)
            : String(format: "%.1f ms", record.latencyMs)

        return HStack(spacing: 8) {
            // Time
            Text(timeStr)
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 65, alignment: .leading)

            // Backend
            HStack(spacing: 4) {
                Image(systemName: record.backend.iconName)
                    .font(.caption2)
                    .foregroundStyle(Color.accentColor)
                Text(record.backend.shortName)
                    .font(.caption2.weight(.medium))
                    .lineLimit(1)
            }
            .frame(width: 95, alignment: .leading)

            // Email Subject
            Text(record.emailSubject)
                .font(.caption)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)

            // Latency
            Text(latencyText)
                .font(.caption.monospacedDigit().weight(.medium))
                .frame(width: 75, alignment: .trailing)

            // Category
            Text(record.category.displayName)
                .font(.caption2.weight(.medium))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.secondary.opacity(0.12), in: Capsule())
                .frame(width: 95, alignment: .leading)

            // Urgency
            HStack(spacing: 3) {
                Image(systemName: record.urgency.iconName)
                    .font(.caption2)
                    .foregroundStyle(record.urgency.color)
                Text(record.urgency.displayName)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(record.urgency.color)
            }
            .frame(width: 75, alignment: .leading)

            // Routing
            Text(record.routingTier.statusBadgeText)
                .font(.system(size: 8, weight: .bold))
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(routingTierColor(record.routingTier).opacity(0.15), in: Capsule())
                .foregroundStyle(routingTierColor(record.routingTier))
                .frame(width: 85, alignment: .leading)

            // Confidence
            Text(confText)
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 65, alignment: .trailing)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 6)
        .background(index.isMultiple(of: 2) ? Color.clear : Color.secondary.opacity(0.02))
    }

    private func routingTierColor(_ tier: RoutingPolicy) -> Color {
        switch tier {
        case .auto: return .green
        case .confirm: return .orange
        case .escalate: return .red
        }
    }

    // MARK: - Actions

    private func handleCopyMarkdown() {
        let markdown = sessionStore.exportMarkdown()
        copyToClipboard(markdown)
        withAnimation(.easeInOut(duration: 0.2)) {
            copiedMarkdown = true
        }
        Task {
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            withAnimation(.easeInOut(duration: 0.2)) {
                copiedMarkdown = false
            }
        }
    }

    private func handleCopyCSV() {
        let csv = sessionStore.exportCSV()
        copyToClipboard(csv)
        withAnimation(.easeInOut(duration: 0.2)) {
            copiedCSV = true
        }
        Task {
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            withAnimation(.easeInOut(duration: 0.2)) {
                copiedCSV = false
            }
        }
    }

    private func copyToClipboard(_ text: String) {
        #if os(macOS)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        #elseif os(iOS)
        UIPasteboard.general.string = text
        #endif
    }

    #if os(macOS)
    private func exportMarkdownFile() {
        let savePanel = NSSavePanel()
        savePanel.canCreateDirectories = true
        savePanel.nameFieldStringValue = "mail-triage-benchmark.md"
        savePanel.allowedContentTypes = [.plainText]
        if savePanel.runModal() == .OK, let url = savePanel.url {
            try? sessionStore.exportMarkdown().write(to: url, atomically: true, encoding: .utf8)
        }
    }

    private func exportCSVFile() {
        let savePanel = NSSavePanel()
        savePanel.canCreateDirectories = true
        savePanel.nameFieldStringValue = "mail-triage-benchmark.csv"
        savePanel.allowedContentTypes = [.commaSeparatedText]
        if savePanel.runModal() == .OK, let url = savePanel.url {
            try? sessionStore.exportCSV().write(to: url, atomically: true, encoding: .utf8)
        }
    }
    #endif
}

#Preview {
    let store = BenchmarkSessionStore()
    let _ = Container.shared.benchmarkSessionStore.register { store }
    BenchmarkComparisonSheet()
}
