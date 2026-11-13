import SwiftUI
import FoundationModels
import SystemOneCore
import ClefFoundationModels
import OpenAIFoundationModels
import GeminiFoundationModels

// MARK: - Inspection Telemetry & Decision Result Bundle

public struct VisualInspectionResult: Sendable, Equatable {
    public var decision: VisualInspectionDecision
    public var conditionScoreValue: ScoreValue?
    public var recognizedJudgement: NoulJudgement
    public var safetyJudgement: NoulJudgement
    public var categoryDecision: Decision
    public var categoryConfidence: Double?
    public var providerBadge: String
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
        providerBadge: String = "Clef 9B",
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
        self.providerBadge = providerBadge
        self.serverDurationMs = serverDurationMs
        self.transportDurationMs = transportDurationMs
        self.totalDurationMs = totalDurationMs
        self.timestamp = timestamp
    }
}

// MARK: - Principle 7 Configuration Error

public enum VisionBackendConfigurationError: LocalizedError, Sendable {
    case missingCloudflareCredentials
    case invalidLocalRunnerURL(String)
    case missingOpenAIAPIKey
    case missingGeminiAPIKey
    case missingReverseProxyURL
    case invalidReverseProxyURL(String)

    public var errorDescription: String? {
        switch self {
        case .missingCloudflareCredentials:
            return "Cloudflare Workers AI requires Account ID and API Token. Open Settings (gear icon) or export CLOUDFLARE_ACCOUNT_ID and CLOUDFLARE_API_TOKEN."
        case .invalidLocalRunnerURL(let raw):
            return "Invalid Local Clef Runner URL ('\(raw)'). Enter http://127.0.0.1:8000 in Settings or export LOCAL_RUNNER_URL."
        case .missingOpenAIAPIKey:
            return "OpenAI Decisions (gpt-6-luna) requires OPENAI_API_KEY. Open Settings (gear icon) or export OPENAI_API_KEY=\"sk-...\"."
        case .missingGeminiAPIKey:
            return "Google Gemini Decisions (gemini-decision-1) requires GEMINI_API_KEY (or GOOGLE_API_KEY). Open Settings (gear icon) or export GEMINI_API_KEY=\"...\"."
        case .missingReverseProxyURL:
            return "Authenticated Reverse Proxy requires SYSTEM_ONE_PROXY_URL. Open Settings (gear icon) or export SYSTEM_ONE_PROXY_URL=\"https://...\"."
        case .invalidReverseProxyURL(let detail):
            return detail
        }
    }
}

// MARK: - Vision-Capable Backend Selection (All 6 Modes)

public enum InspectionBackendSelection: String, CaseIterable, Identifiable, Sendable {
    case workersAIFlash = "workers-ai-flash"
    case workersAIClef = "workers-ai-clef"
    case localRunner = "local-runner"
    case openAIDecisions = "openai-decisions"
    case geminiDecisions = "gemini-decisions"
    case reverseProxy = "reverse-proxy"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .workersAIFlash: return "Cloudflare Clef-Flash (9B)"
        case .workersAIClef: return "Cloudflare Clef (27B)"
        case .localRunner: return "Local Clef Runner (localhost:8000)"
        case .openAIDecisions: return "OpenAI Decisions (gpt-6-luna)"
        case .geminiDecisions: return "Google Gemini Decisions (gemini-decision-1)"
        case .reverseProxy: return "Authenticated Reverse Proxy"
        }
    }

    public var shortBadge: String {
        switch self {
        case .workersAIFlash: return "Clef-Flash 9B"
        case .workersAIClef: return "Clef 27B"
        case .localRunner: return "Local Clef"
        case .openAIDecisions: return "OpenAI Luna"
        case .geminiDecisions: return "Gemini Decision"
        case .reverseProxy: return "Reverse Proxy"
        }
    }

    public var systemImageName: String {
        switch self {
        case .workersAIFlash: return "bolt.horizontal.icloud.fill"
        case .workersAIClef: return "icloud.fill"
        case .localRunner: return "desktopcomputer"
        case .openAIDecisions: return "sparkles"
        case .geminiDecisions: return "wand.and.stars"
        case .reverseProxy: return "lock.shield.fill"
        }
    }

    /// Auto-detects the first configured vision provider on launch from Keychain, AppStorage, or environment variables.
    public static var autoDetectedDefault: InspectionBackendSelection {
        if hasNonEmpty(appStorageKey: "systemOneProxyURL", envKeys: ["SYSTEM_ONE_PROXY_URL", "TYPESAFE_PROXY_URL"]) {
            return .reverseProxy
        }
        if hasNonEmpty(appStorageKey: "cloudflareAccountID", envKeys: ["CLOUDFLARE_ACCOUNT_ID"]) &&
           hasNonEmptyKeychainOrEnv(keychainKey: "cloudflareAPIToken", envKeys: ["CLOUDFLARE_API_TOKEN"]) {
            return .workersAIFlash
        }
        if hasNonEmptyKeychainOrEnv(keychainKey: "openAIAPIKey", envKeys: ["OPENAI_API_KEY"]) {
            return .openAIDecisions
        }
        if hasNonEmptyKeychainOrEnv(keychainKey: "geminiAPIKey", envKeys: ["GEMINI_API_KEY", "GOOGLE_API_KEY"]) {
            return .geminiDecisions
        }
        if hasNonEmpty(appStorageKey: nil, envKeys: ["LOCAL_RUNNER_URL", "CLEF_LOCAL_PORT", "CLEF_ENDPOINT"]) {
            return .localRunner
        }
        return .workersAIFlash
    }

    /// Resolves a concrete `any LanguageModel` for the selected vision backend, throwing a typed
    /// Principle 7 `VisionBackendConfigurationError` whenever required credentials or endpoints are missing.
    public func resolveLanguageModel(
        accountID: String? = nil,
        gatewayID: String? = nil,
        cloudflareAPIToken: String? = nil,
        localRunnerURL: String? = nil,
        openAIAPIKey: String? = nil,
        geminiAPIKey: String? = nil,
        proxyURLString: String? = nil,
        proxyBearerToken: String? = nil,
        appCheckToken: String? = nil,
        proxyModelID: String? = nil
    ) throws -> any LanguageModel {
        switch self {
        case .workersAIFlash:
            return try makeCloudflareModel(
                model: .clefFlash,
                accountID: accountID,
                gatewayID: gatewayID,
                apiToken: cloudflareAPIToken
            )
        case .workersAIClef:
            return try makeCloudflareModel(
                model: .clef,
                accountID: accountID,
                gatewayID: gatewayID,
                apiToken: cloudflareAPIToken
            )
        case .localRunner:
            return try makeLocalClefModel(localRunnerURL: localRunnerURL)
        case .openAIDecisions:
            guard let key = Self.resolveSecret(
                explicit: openAIAPIKey,
                keychainKey: "openAIAPIKey",
                envKeys: ["OPENAI_API_KEY"]
            ) else {
                throw VisionBackendConfigurationError.missingOpenAIAPIKey
            }
            return OpenAIDecisionsLanguageModel(apiKey: key)
        case .geminiDecisions:
            guard let key = Self.resolveSecret(
                explicit: geminiAPIKey,
                keychainKey: "geminiAPIKey",
                envKeys: ["GEMINI_API_KEY", "GOOGLE_API_KEY"]
            ) else {
                throw VisionBackendConfigurationError.missingGeminiAPIKey
            }
            return GeminiDecisionsLanguageModel(apiKey: key)
        case .reverseProxy:
            guard let rawProxyURL = Self.resolveSetting(
                explicit: proxyURLString,
                appStorageKey: "systemOneProxyURL",
                envKeys: ["SYSTEM_ONE_PROXY_URL", "TYPESAFE_PROXY_URL"]
            ) else {
                throw VisionBackendConfigurationError.missingReverseProxyURL
            }
            guard let candidateURL = URL(string: rawProxyURL) else {
                throw VisionBackendConfigurationError.invalidReverseProxyURL(
                    "Invalid proxy URL '\(rawProxyURL)'. Provide an https:// endpoint (or http://127.0.0.1:<port> for local dev)."
                )
            }
            do {
                try ProxyEndpointValidator.validate(candidateURL)
            } catch {
                throw VisionBackendConfigurationError.invalidReverseProxyURL(error.localizedDescription)
            }

            let resolvedAppCheck = Self.resolveSecret(
                explicit: appCheckToken,
                keychainKey: "firebaseAppCheckToken",
                envKeys: ["FIREBASE_APPCHECK_TOKEN"]
            )
            let resolvedBearer = Self.resolveSecret(
                explicit: proxyBearerToken,
                keychainKey: "systemOneProxyBearerToken",
                envKeys: ["SYSTEM_ONE_PROXY_TOKEN", "TYPESAFE_PROXY_TOKEN"]
            )

            let credential: ProxyCredential
            if let resolvedAppCheck {
                credential = .appCheck { resolvedAppCheck }
            } else if let resolvedBearer {
                credential = .bearer { resolvedBearer }
            } else {
                credential = .custom { _ in }
            }

            let resolvedModelID = Self.resolveSetting(
                explicit: proxyModelID,
                appStorageKey: "systemOneProxyModelID",
                envKeys: ["SYSTEM_ONE_PROXY_MODEL"]
            ) ?? "systemone-default"

            return SystemOneLanguageModel(
                proxyEndpoint: candidateURL,
                credential: credential,
                modelID: resolvedModelID,
                supportsVision: true
            )
        }
    }

    // MARK: - Provider Builders & Lookup Helpers

    private func makeCloudflareModel(
        model: ClefModel,
        accountID: String?,
        gatewayID: String?,
        apiToken: String?
    ) throws -> ClefLanguageModel {
        let resolvedToken = Self.resolveSecret(
            explicit: apiToken,
            keychainKey: "cloudflareAPIToken",
            envKeys: ["CLOUDFLARE_API_TOKEN"]
        )

        if let customEndpoint = Self.resolveSetting(explicit: nil, appStorageKey: nil, envKeys: ["CLEF_ENDPOINT"]),
           let customURL = URL(string: customEndpoint) {
            return ClefLanguageModel(endpoint: .custom(customURL, model: model), apiToken: resolvedToken)
        }

        guard let resolvedAccountID = Self.resolveSetting(
            explicit: accountID,
            appStorageKey: "cloudflareAccountID",
            envKeys: ["CLOUDFLARE_ACCOUNT_ID"]
        ), let resolvedToken else {
            throw VisionBackendConfigurationError.missingCloudflareCredentials
        }

        let endpoint: ClefEndpoint
        if let resolvedGatewayID = Self.resolveSetting(
            explicit: gatewayID,
            appStorageKey: "cloudflareGatewayID",
            envKeys: ["CLOUDFLARE_GATEWAY_ID"]
        ) {
            endpoint = .gateway(accountID: resolvedAccountID, gatewayID: resolvedGatewayID, model: model)
        } else {
            endpoint = .workersAI(accountID: resolvedAccountID, model: model)
        }

        return ClefLanguageModel(endpoint: endpoint, apiToken: resolvedToken)
    }

    private func makeLocalClefModel(localRunnerURL: String?) throws -> ClefLanguageModel {
        let resolvedRunner: String = {
            if let explicit = Self.trimmedNonEmpty(localRunnerURL) {
                return explicit
            }
            if let stored = Self.trimmedNonEmpty(UserDefaults.standard.string(forKey: "localRunnerURL")) {
                return stored
            }
            if let envURL = Self.resolveSetting(explicit: nil, appStorageKey: nil, envKeys: ["LOCAL_RUNNER_URL", "CLEF_ENDPOINT"]) {
                return envURL
            }
            if let rawPort = Self.resolveSetting(explicit: nil, appStorageKey: nil, envKeys: ["CLEF_LOCAL_PORT"]),
               let port = Int(rawPort) {
                return "http://127.0.0.1:\(port)"
            }
            return "http://127.0.0.1:8000"
        }()

        guard let url = URL(string: resolvedRunner),
              let scheme = url.scheme?.lowercased(), (scheme == "http" || scheme == "https"),
              let host = url.host, !host.isEmpty else {
            throw VisionBackendConfigurationError.invalidLocalRunnerURL(resolvedRunner)
        }

        if (host == "localhost" || host == "127.0.0.1"), let port = url.port, (url.path.isEmpty || url.path == "/") {
            return ClefLanguageModel(endpoint: .local(port: port, model: .clefFlash), apiToken: nil)
        }

        let evalURL = url.path.hasSuffix("/v1/evaluate") ? url : url.appendingPathComponent("v1/evaluate")
        return ClefLanguageModel(endpoint: .custom(evalURL, model: .clefFlash), apiToken: nil)
    }

    private static func resolveSetting(
        explicit: String?,
        appStorageKey: String?,
        envKeys: [String]
    ) -> String? {
        if let val = trimmedNonEmpty(explicit) {
            return val
        }
        if let appStorageKey, let stored = trimmedNonEmpty(UserDefaults.standard.string(forKey: appStorageKey)) {
            return stored
        }
        for envKey in envKeys {
            if let env = trimmedNonEmpty(ProcessInfo.processInfo.environment[envKey]) {
                return env
            }
        }
        return nil
    }

    private static func resolveSecret(
        explicit: String?,
        keychainKey: String,
        envKeys: [String]
    ) -> String? {
        if let val = trimmedNonEmpty(explicit) {
            return val
        }
        if let stored = trimmedNonEmpty(KeychainHelper.string(forKey: keychainKey)) {
            return stored
        }
        for envKey in envKeys {
            if let env = trimmedNonEmpty(ProcessInfo.processInfo.environment[envKey]) {
                return env
            }
        }
        return nil
    }

    private static func hasNonEmpty(appStorageKey: String?, envKeys: [String]) -> Bool {
        resolveSetting(explicit: nil, appStorageKey: appStorageKey, envKeys: envKeys) != nil
    }

    private static func hasNonEmptyKeychainOrEnv(keychainKey: String, envKeys: [String]) -> Bool {
        resolveSecret(explicit: nil, keychainKey: keychainKey, envKeys: envKeys) != nil
    }

    private static func trimmedNonEmpty(_ raw: String?) -> String? {
        guard let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        return trimmed
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
    public let onOpenSettings: (() -> Void)?

    public init(
        result: VisualInspectionResult?,
        isInspecting: Bool,
        errorMessage: String?,
        selectedBackend: Binding<InspectionBackendSelection>,
        isAutoScanEnabled: Binding<Bool>,
        onInspectTapped: @escaping () -> Void,
        onOpenSettings: (() -> Void)? = nil
    ) {
        self.result = result
        self.isInspecting = isInspecting
        self.errorMessage = errorMessage
        self._selectedBackend = selectedBackend
        self._isAutoScanEnabled = isAutoScanEnabled
        self.onInspectTapped = onInspectTapped
        self.onOpenSettings = onOpenSettings
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
                            Label {
                                HStack {
                                    Text(backend.displayName)
                                    if selectedBackend == backend {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            } icon: {
                                Image(systemName: backend.systemImageName)
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: selectedBackend.systemImageName)
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
                .accessibilityLabel("Select Vision Provider, currently \(selectedBackend.displayName)")

                Spacer()

                // Latency & Provider Telemetry Pill
                if let result = result {
                    HStack(spacing: 8) {
                        Text(result.providerBadge)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.8))

                        if let serverMs = result.serverDurationMs {
                            Label(String(format: "%.0fms", serverMs), systemImage: "bolt.fill")
                                .font(.caption.monospaced().weight(.semibold))
                                .foregroundStyle(.cyan)
                        } else {
                            Label(String(format: "%.0fms", result.totalDurationMs), systemImage: "clock.fill")
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
                    ErrorContentStateView(message: error, onOpenSettings: onOpenSettings)
                        .transition(.opacity)
                } else if let result = result {
                    ZStack {
                        ResultCardContent(result: result)
                            .opacity(isInspecting ? 0.45 : 1.0)
                            .animation(.easeInOut(duration: 0.2), value: isInspecting)

                        if isInspecting {
                            InspectingOverlayView(providerName: selectedBackend.shortBadge)
                                .transition(.opacity)
                        }
                    }
                    .transition(.opacity)
                } else if isInspecting {
                    InspectingEmptyStateView(providerName: selectedBackend.displayName)
                        .transition(.opacity)
                } else {
                    EmptyHUDStateView(providerName: selectedBackend.displayName)
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
    let providerName: String

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
                Text("Active backend: \(providerName)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct InspectingEmptyStateView: View {
    let providerName: String

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
                Text("Evaluating Visual Frame")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                Text("Running \(providerName)...")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            ScanningProgressBar()
                .frame(width: 140, height: 2)
                .padding(.top, 2)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct InspectingOverlayView: View {
    let providerName: String

    var body: some View {
        ZStack {
            HStack(spacing: 8) {
                ProgressView()
                    .tint(.cyan)
                    .scaleEffect(0.85)
                Text("Evaluating with \(providerName)...")
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
    let onOpenSettings: (() -> Void)?

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.rose)
                Text("Configuration / Inspection Issue")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.rose)
            }

            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(3)
                .padding(.horizontal, 14)

            if let onOpenSettings {
                Button(action: onOpenSettings) {
                    Label("Configure Provider Settings", systemImage: "gearshape.fill")
                        .font(.caption.weight(.semibold))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .tint(.cyan)
                .padding(.top, 2)
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
            DetectedItemRow(result: result)

            HStack(alignment: .top, spacing: 8) {
                DecisionMetricPill(
                    title: "Recognition",
                    value: result.decision.isRecognized ? "Recognized" : "Uncertain",
                    icon: result.decision.isRecognized ? "checkmark.circle.fill" : "questionmark.circle.fill",
                    tint: result.decision.isRecognized ? .emerald : .amber
                )

                ConditionMetricPill(
                    score: result.decision.conditionScore,
                    scoreValue: result.conditionScoreValue
                )

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
                providerBadge: "OpenAI Luna",
                serverDurationMs: 42.0,
                transportDurationMs: 18.0,
                totalDurationMs: 60.0
            ),
            isInspecting: false,
            errorMessage: nil,
            selectedBackend: .constant(.openAIDecisions),
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
            errorMessage: "OpenAI Decisions (gpt-6-luna) requires OPENAI_API_KEY. Open Settings (gear icon) or export OPENAI_API_KEY=\"sk-...\".",
            selectedBackend: .constant(.openAIDecisions),
            isAutoScanEnabled: .constant(false),
            onInspectTapped: {},
            onOpenSettings: {}
        )
        .padding()
    }
}
