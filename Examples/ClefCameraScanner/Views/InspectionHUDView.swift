import SwiftUI
import SystemOneCore
import ClefFoundationModels

// MARK: - Inspection Telemetry & Decision Result Bundle

public struct VisualInspectionResult: Sendable, Equatable {
    public var decision: VisualInspectionDecision
    public var conditionScoreValue: ScoreValue?
    public var recognizedJudgement: NoulJudgement
    public var safetyJudgement: NoulJudgement
    public var categoryDecision: Decision
    public var categoryConfidence: Double?
    public var serverDurationMs: Double?
    public var transportDurationMs: Double?
    public var totalDurationMs: Double
    public var timestamp: Date

    public init(
        decision: VisualInspectionDecision,
        conditionScoreValue: ScoreValue?,
        recognizedJudgement: NoulJudgement,
        safetyJudgement: NoulJudgement,
        categoryDecision: Decision,
        categoryConfidence: Double? = nil,
        serverDurationMs: Double?,
        transportDurationMs: Double?,
        totalDurationMs: Double,
        timestamp: Date = Date()
    ) {
        self.decision = decision
        self.conditionScoreValue = conditionScoreValue
        self.recognizedJudgement = recognizedJudgement
        self.safetyJudgement = safetyJudgement
        self.categoryDecision = categoryDecision
        self.categoryConfidence = categoryConfidence
        self.serverDurationMs = serverDurationMs
        self.transportDurationMs = transportDurationMs
        self.totalDurationMs = totalDurationMs
        self.timestamp = timestamp
    }
}

// MARK: - Backend Target Selection

public enum InspectionBackendSelection: String, CaseIterable, Identifiable, Sendable {
    case workersAIFlash = "workers-ai-flash"
    case workersAIClef = "workers-ai-clef"
    case localRunner = "local-runner"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .workersAIFlash: return "Cloudflare Clef-Flash (9B)"
        case .workersAIClef: return "Cloudflare Clef (27B)"
        case .localRunner: return "Local Runner (localhost:8000)"
        }
    }

    public var shortBadge: String {
        switch self {
        case .workersAIFlash: return "Workers AI 9B"
        case .workersAIClef: return "Workers AI 27B"
        case .localRunner: return "Local 8000"
        }
    }

    /// Computes the ClefEndpoint using explicit overrides, stored @AppStorage settings, or environment variables.
    public func endpoint(accountID: String? = nil, localRunnerURL: String? = nil) -> ClefEndpoint {
        let resolvedAccountID: String = {
            if let accountID, !accountID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return accountID.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            if let stored = UserDefaults.standard.string(forKey: "cloudflareAccountID"),
               !stored.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return stored.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            return ProcessInfo.processInfo.environment["CLOUDFLARE_ACCOUNT_ID"] ?? ""
        }()

        let resolvedRunner: String = {
            if let localRunnerURL, !localRunnerURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return localRunnerURL.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            if let stored = UserDefaults.standard.string(forKey: "localRunnerURL"),
               !stored.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return stored.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            return ProcessInfo.processInfo.environment["LOCAL_RUNNER_URL"] ?? "http://127.0.0.1:8000"
        }()

        switch self {
        case .workersAIFlash:
            return .workersAI(accountID: resolvedAccountID, model: .clefFlash)
        case .workersAIClef:
            return .workersAI(accountID: resolvedAccountID, model: .clef)
        case .localRunner:
            if let url = URL(string: resolvedRunner), let host = url.host, (host == "localhost" || host == "127.0.0.1"), let port = url.port {
                return .local(port: port, model: .clefFlash)
            } else if let url = URL(string: resolvedRunner) {
                let evalURL = url.path.hasSuffix("/v1/evaluate") ? url : url.appendingPathComponent("v1/evaluate")
                return .custom(evalURL, model: .clefFlash)
            }
            return .local(port: 8000, model: .clefFlash)
        }
    }

    /// Factory method creating a ClefLanguageModel configured with stored settings or explicit overrides.
    public func makeModel(
        accountID: String? = nil,
        apiToken: String? = nil,
        localRunnerURL: String? = nil
    ) -> ClefLanguageModel {
        let resolvedToken: String? = {
            if let apiToken, !apiToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return apiToken.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            if let stored = KeychainHelper.string(forKey: "cloudflareAPIToken") ?? UserDefaults.standard.string(forKey: "cloudflareAPIToken"),
               !stored.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return stored.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            if let env = ProcessInfo.processInfo.environment["CLOUDFLARE_API_TOKEN"], !env.isEmpty {
                return env
            }
            return nil
        }()

        return ClefLanguageModel(
            endpoint: endpoint(accountID: accountID, localRunnerURL: localRunnerURL),
            apiToken: resolvedToken
        )
    }
}

// MARK: - Interactive Inspection HUD View (Liquid Glass Styling)

public struct InspectionHUDView: View {
    public let result: VisualInspectionResult?
    public let isInspecting: Bool
    public let errorMessage: String?
    @Binding public var selectedBackend: InspectionBackendSelection
    @Binding public var isAutoScanEnabled: Bool
    public let onInspectTapped: () -> Void

    public init(
        result: VisualInspectionResult?,
        isInspecting: Bool,
        errorMessage: String?,
        selectedBackend: Binding<InspectionBackendSelection>,
        isAutoScanEnabled: Binding<Bool>,
        onInspectTapped: @escaping () -> Void
    ) {
        self.result = result
        self.isInspecting = isInspecting
        self.errorMessage = errorMessage
        self._selectedBackend = selectedBackend
        self._isAutoScanEnabled = isAutoScanEnabled
        self.onInspectTapped = onInspectTapped
    }

    public var body: some View {
        VStack(spacing: 14) {
            // Top Controls Bar: Backend Picker & Latency Telemetry (Fixed 36pt height)
            HStack {
                Menu {
                    ForEach(InspectionBackendSelection.allCases) { backend in
                        Button {
                            selectedBackend = backend
                        } label: {
                            HStack {
                                Text(backend.displayName)
                                if selectedBackend == backend {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "server.rack")
                            .font(.caption2)
                        Text(selectedBackend.shortBadge)
                            .font(.caption.weight(.semibold))
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.caption2)
                    }
                    .padding(.horizontal, 12)
                    .frame(height: 36)
                    .glassEffect(.regular, in: .capsule)
                }
                .buttonStyle(.plain)

                Spacer()

                // Latency Telemetry Pill
                if let result = result {
                    HStack(spacing: 8) {
                        if let serverMs = result.serverDurationMs {
                            Label(String(format: "%.0fms", serverMs), systemImage: "bolt.fill")
                                .font(.caption.monospaced().weight(.semibold))
                                .foregroundStyle(.cyan)
                        }
                        if let transportMs = result.transportDurationMs {
                            Label(String(format: "%.0fms", transportMs), systemImage: "network")
                                .font(.caption.monospaced().weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.horizontal, 12)
                    .frame(height: 36)
                    .glassEffect(.regular, in: .capsule)
                    .transition(.opacity)
                }
            }
            .frame(height: 36)

            // Center Content: Fixed 144pt Height Across All States (Zero HUD Pumping)
            ZStack {
                if let error = errorMessage {
                    ErrorContentStateView(message: error)
                        .transition(.opacity)
                } else if let result = result {
                    ZStack {
                        ResultCardContent(result: result)
                            .opacity(isInspecting ? 0.45 : 1.0)
                            .animation(.easeInOut(duration: 0.2), value: isInspecting)

                        if isInspecting {
                            InspectingOverlayView()
                                .transition(.opacity)
                        }
                    }
                    .transition(.opacity)
                } else if isInspecting {
                    InspectingEmptyStateView()
                        .transition(.opacity)
                } else {
                    EmptyHUDStateView()
                        .transition(.opacity)
                }
            }
            .frame(height: 144)
            .frame(maxWidth: .infinity)
            .clipped()

            // Symmetrical Equal-Size Action Buttons (48pt)
            HStack(spacing: 12) {
                // Auto-Scan Toggle Button
                Button {
                    withAnimation(.spring(duration: 0.22, bounce: 0.15)) {
                        isAutoScanEnabled.toggle()
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "repeat")
                            .font(.subheadline.weight(.semibold))
                        Text("Auto-Scan")
                            .font(.subheadline.weight(.semibold))
                    }
                }
                .buttonStyle(AutoScanToggleButtonStyle(isActive: isAutoScanEnabled))
                .accessibilityLabel("Toggle Auto-Scan")
                .accessibilityValue(isAutoScanEnabled ? "Active" : "Inactive")

                // Inspect Frame Action Button
                Button {
                    onInspectTapped()
                } label: {
                    HStack(spacing: 8) {
                        if isInspecting {
                            ProgressView()
                                .tint(.black)
                                .scaleEffect(0.85)
                            Text("Inspecting...")
                                .font(.subheadline.weight(.semibold))
                        } else {
                            Image(systemName: "camera.metering.matrix")
                                .font(.subheadline.weight(.semibold))
                            Text("Inspect Frame")
                                .font(.subheadline.weight(.semibold))
                        }
                    }
                }
                .buttonStyle(InspectActionButtonStyle(isInspecting: isInspecting))
                .disabled(isInspecting)
                .accessibilityLabel(isInspecting ? "Inspecting" : "Inspect Frame")
            }
            .frame(height: 48)
        }
        .padding(16)
        .glassEffect(.regular, in: .rect(cornerRadius: 24))
    }
}

// MARK: - Symmetrical Action Button Styles

private struct AutoScanToggleButtonStyle: ButtonStyle {
    let isActive: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(isActive ? Color.cyan : Color.white)
            .frame(maxWidth: .infinity)
            .frame(height: 48)
            .background {
                if isActive {
                    ZStack {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Color.cyan.opacity(0.18))
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(Color.cyan.opacity(0.6), lineWidth: 1)
                    }
                    .shadow(color: Color.cyan.opacity(0.4), radius: 8, x: 0, y: 0)
                } else {
                    ZStack {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Color.white.opacity(0.08))
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.75)
                    }
                }
            }
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.easeOut(duration: 0.16), value: configuration.isPressed)
    }
}

private struct InspectActionButtonStyle: ButtonStyle {
    let isInspecting: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Color.black)
            .frame(maxWidth: .infinity)
            .frame(height: 48)
            .background {
                ZStack {
                    LinearGradient(
                        colors: [
                            Color(red: 0.15, green: 0.88, blue: 0.98),
                            Color(red: 0.00, green: 0.72, blue: 0.88)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.35), lineWidth: 0.75)
                }
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .shadow(color: Color.cyan.opacity(0.35), radius: 8, x: 0, y: 2)
            }
            .opacity(isInspecting ? 0.6 : 1.0)
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.easeOut(duration: 0.16), value: configuration.isPressed)
    }
}

// MARK: - State Subviews (Fixed 144pt Geometry)

private struct EmptyHUDStateView: View {
    var body: some View {
        VStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(Color.white.opacity(0.06))
                    .frame(width: 44, height: 44)
                Circle()
                    .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
                    .frame(width: 44, height: 44)

                Image(systemName: "viewfinder")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(.cyan)
            }

            VStack(spacing: 3) {
                Text("Ready to Inspect")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                Text("Point at an item to classify")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct InspectingEmptyStateView: View {
    var body: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.cyan.opacity(0.12))
                    .frame(width: 44, height: 44)
                Circle()
                    .strokeBorder(Color.cyan.opacity(0.35), lineWidth: 1)
                    .frame(width: 44, height: 44)

                ProgressView()
                    .tint(.cyan)
                    .scaleEffect(0.95)
            }

            VStack(spacing: 3) {
                Text("Evaluating Camera Frame")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                Text("Running Clef forward pass...")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            ScanningProgressBar()
                .frame(width: 140, height: 2)
                .padding(.top, 2)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct InspectingOverlayView: View {
    var body: some View {
        ZStack {
            // Subtle frosted glass pill centered
            HStack(spacing: 8) {
                ProgressView()
                    .tint(.cyan)
                    .scaleEffect(0.85)
                Text("Evaluating frame...")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Color.black.opacity(0.65), in: Capsule())
            .overlay(
                Capsule()
                    .strokeBorder(Color.cyan.opacity(0.45), lineWidth: 1)
            )
            .shadow(color: Color.cyan.opacity(0.3), radius: 10)

            // Subtle scanning line across the top
            VStack {
                ScanningProgressBar()
                    .padding(.horizontal, 8)
                    .padding(.top, 2)
                Spacer()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct ScanningProgressBar: View {
    @State private var phase: CGFloat = 0

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            Capsule()
                .fill(Color.white.opacity(0.08))
                .overlay(alignment: .leading) {
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [.clear, .cyan.opacity(0.8), .clear],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: width * 0.4)
                        .offset(x: phase * (width * 0.6))
                }
                .clipShape(Capsule())
        }
        .frame(height: 2)
        .onAppear {
            withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true)) {
                phase = 1.0
            }
        }
    }
}

private struct ErrorContentStateView: View {
    let message: String

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(Color.rose.opacity(0.15))
                    .frame(width: 40, height: 40)
                Circle()
                    .strokeBorder(Color.rose.opacity(0.35), lineWidth: 1)
                    .frame(width: 40, height: 40)

                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.rose)
            }

            VStack(spacing: 3) {
                Text("Inspection Issue")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.rose)

                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .padding(.horizontal, 20)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Result Card Subviews

private struct ResultCardContent: View {
    let result: VisualInspectionResult

    var body: some View {
        VStack(spacing: 8) {
            // Line 1: Dedicated Full-Width Row for Detected Item
            DetectedItemRow(result: result)

            // Line 2: Secondary Metrics Row (Recognition, Condition, Safety)
            HStack(alignment: .top, spacing: 8) {
                // Recognition
                DecisionMetricPill(
                    title: "Recognition",
                    value: result.decision.isRecognized ? "Recognized" : "Uncertain",
                    icon: result.decision.isRecognized ? "checkmark.circle.fill" : "questionmark.circle.fill",
                    tint: result.decision.isRecognized ? .emerald : .amber
                )

                // Condition
                ConditionMetricPill(
                    score: result.decision.conditionScore,
                    scoreValue: result.conditionScoreValue
                )

                // Safety
                DecisionMetricPill(
                    title: "Safety",
                    value: result.decision.safetyApproval ? "Approved" : "Flagged",
                    icon: result.decision.safetyApproval ? "checkmark.shield.fill" : "exclamationmark.shield.fill",
                    tint: result.decision.safetyApproval ? .emerald : .rose
                )
            }
        }
    }
}

// MARK: - Line 1: Dedicated Detected Item Row

private struct DetectedItemRow: View {
    let result: VisualInspectionResult

    var body: some View {
        HStack(spacing: 12) {
            // SF Symbol Icon in a soft tinted circular container (40pt badge)
            ZStack {
                Circle()
                    .fill(categoryColor.opacity(0.18))
                    .frame(width: 40, height: 40)
                Circle()
                    .strokeBorder(categoryColor.opacity(0.35), lineWidth: 1)
                    .frame(width: 40, height: 40)

                Image(systemName: result.decision.itemCategory.systemImageName)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(categoryColor)
            }

            // Classification Header & Category Display Name
            VStack(alignment: .leading, spacing: 2) {
                Text("DETECTED ITEM")
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .tracking(0.6)

                Text(result.decision.itemCategory.displayName)
                    .font(.headline.weight(.bold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }

            Spacer(minLength: 8)

            // Category Confidence Percentage or Calibrated Decision Badge
            categoryConfidenceBadge
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 0.5)
        )
    }

    @ViewBuilder
    private var categoryConfidenceBadge: some View {
        if let confidence = result.categoryConfidence {
            let color = confidenceColor(for: confidence)
            HStack(spacing: 5) {
                Circle()
                    .fill(color)
                    .frame(width: 6, height: 6)
                Text(String(format: "%.0f%%", confidence * 100))
                    .font(.system(.subheadline, design: .monospaced, weight: .bold))
                    .foregroundStyle(.white)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(color.opacity(0.15), in: Capsule())
            .overlay(
                Capsule()
                    .strokeBorder(color.opacity(0.3), lineWidth: 0.5)
            )
        } else {
            let (badgeText, color) = decisionBadgeProps(for: result.categoryDecision)
            HStack(spacing: 5) {
                Circle()
                    .fill(color)
                    .frame(width: 6, height: 6)
                Text(badgeText)
                    .font(.system(.caption2, design: .monospaced, weight: .bold))
                    .foregroundStyle(color)
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(color.opacity(0.15), in: Capsule())
            .overlay(
                Capsule()
                    .strokeBorder(color.opacity(0.3), lineWidth: 0.5)
            )
        }
    }

    private var categoryColor: Color {
        switch result.decision.itemCategory {
        case .snack: return .amber
        case .beverage: return .cyan
        case .electronics: return .purple
        case .document: return .blue
        case .household: return .emerald
        case .person: return .indigo
        case .clothing: return .teal
        case .plant: return .green
        case .accessory: return .orange
        case .unknown: return .secondary
        }
    }

    private func confidenceColor(for confidence: Double) -> Color {
        if confidence >= 0.85 {
            return .emerald
        } else if confidence >= 0.60 {
            return .amber
        } else {
            return .rose
        }
    }

    private func decisionBadgeProps(for decision: Decision) -> (String, Color) {
        switch decision {
        case .auto:
            return ("AUTO (≥85%)", .emerald)
        case .confirm:
            return ("CONFIRM", .amber)
        case .escalate:
            return ("REVIEW", .rose)
        }
    }
}

// MARK: - Line 2: Metric Pills

private struct DecisionMetricPill: View {
    let title: String
    let value: String
    let icon: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .foregroundStyle(tint)
                    .font(.caption)
                Text(value)
                    .font(.caption.bold())
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
    }
}

private struct ConditionMetricPill: View {
    let score: Int
    let scoreValue: ScoreValue?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Condition")
                .font(.caption2)
                .foregroundStyle(.secondary)

            HStack(spacing: 3) {
                ForEach(0..<4) { index in
                    Circle()
                        .fill(index <= score ? scoreColor : Color.white.opacity(0.2))
                        .frame(width: 5, height: 5)
                }
                Spacer(minLength: 2)
                Text(shortConditionLabel)
                    .font(.caption.bold())
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
    }

    private var shortConditionLabel: String {
        switch score {
        case 0: return "Damaged"
        case 1: return "Worn"
        case 2: return "Good"
        case 3: return "Pristine"
        default: return "\(score)/3"
        }
    }

    private var scoreColor: Color {
        switch score {
        case 0: return .rose
        case 1: return .amber
        case 2: return .cyan
        default: return .emerald
        }
    }
}

// MARK: - Calibrated Confidence Badge

public struct ConfidenceBadge: View {
    public let decision: Decision

    public init(decision: Decision) {
        self.decision = decision
    }

    public var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(indicatorColor)
                .frame(width: 8, height: 8)
            Text(badgeText)
                .font(.system(.caption2, design: .monospaced, weight: .bold))
                .foregroundStyle(indicatorColor)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(indicatorColor.opacity(0.15), in: Capsule())
    }

    private var badgeText: String {
        switch decision {
        case .auto: return "AUTO-ROUTED (≥85%)"
        case .confirm: return "CONFIRMATION (60-84%)"
        case .escalate: return "ESCALATE (<60%)"
        }
    }

    private var indicatorColor: Color {
        switch decision {
        case .auto: return .emerald
        case .confirm: return .amber
        case .escalate: return .rose
        }
    }
}

// MARK: - Color Palette Extensions

extension Color {
    static let emerald = Color(red: 0.06, green: 0.73, blue: 0.51)
    static let amber = Color(red: 0.96, green: 0.62, blue: 0.04)
    static let rose = Color(red: 0.94, green: 0.27, blue: 0.27)
}

extension ShapeStyle where Self == Color {
    static var emerald: Color { Color.emerald }
    static var amber: Color { Color.amber }
    static var rose: Color { Color.rose }
}

// MARK: - Previews

#Preview("Inspection HUD - Active Result") {
    ZStack {
        Color.black.ignoresSafeArea()

        InspectionHUDView(
            result: VisualInspectionResult(
                decision: VisualInspectionDecision(
                    isRecognized: true,
                    itemCategory: .electronics,
                    conditionScore: 3,
                    safetyApproval: true
                ),
                conditionScoreValue: nil,
                recognizedJudgement: NoulJudgement(answer: true, decisiveness: 0.95, decision: .auto),
                safetyJudgement: NoulJudgement(answer: true, decisiveness: 0.92, decision: .auto),
                categoryDecision: .auto,
                categoryConfidence: 0.96,
                serverDurationMs: 42.0,
                transportDurationMs: 18.0,
                totalDurationMs: 60.0
            ),
            isInspecting: false,
            errorMessage: nil,
            selectedBackend: .constant(.workersAIFlash),
            isAutoScanEnabled: .constant(false),
            onInspectTapped: {}
        )
        .padding()
    }
}

#Preview("Inspection HUD - Inspecting Overlay") {
    ZStack {
        Color.black.ignoresSafeArea()

        InspectionHUDView(
            result: VisualInspectionResult(
                decision: VisualInspectionDecision(
                    isRecognized: true,
                    itemCategory: .snack,
                    conditionScore: 2,
                    safetyApproval: true
                ),
                conditionScoreValue: nil,
                recognizedJudgement: NoulJudgement(answer: true, decisiveness: 0.88, decision: .auto),
                safetyJudgement: NoulJudgement(answer: true, decisiveness: 0.90, decision: .auto),
                categoryDecision: .auto,
                categoryConfidence: 0.91,
                serverDurationMs: 38.0,
                transportDurationMs: 14.0,
                totalDurationMs: 52.0
            ),
            isInspecting: true,
            errorMessage: nil,
            selectedBackend: .constant(.workersAIFlash),
            isAutoScanEnabled: .constant(true),
            onInspectTapped: {}
        )
        .padding()
    }
}

#Preview("Inspection HUD - Empty Ready State") {
    ZStack {
        Color.black.ignoresSafeArea()

        InspectionHUDView(
            result: nil,
            isInspecting: false,
            errorMessage: nil,
            selectedBackend: .constant(.workersAIFlash),
            isAutoScanEnabled: .constant(false),
            onInspectTapped: {}
        )
        .padding()
    }
}

#Preview("Inspection HUD - Error State") {
    ZStack {
        Color.black.ignoresSafeArea()

        InspectionHUDView(
            result: nil,
            isInspecting: false,
            errorMessage: "Cloudflare API token missing or invalid. Check settings.",
            selectedBackend: .constant(.workersAIFlash),
            isAutoScanEnabled: .constant(false),
            onInspectTapped: {}
        )
        .padding()
    }
}
