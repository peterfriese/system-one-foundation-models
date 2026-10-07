import SwiftUI
import AppCore
import FactoryKit
import UniformTypeIdentifiers
#if os(macOS)
import AppKit
#endif

/// Modern Settings control center for System One decision backends, Core ML models, and confidence routing.
public struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss

    @Injected(\.backendConfigurationStore) private var configStore
    @Injected(\.coreMLModelManager) private var coreMLManager
    @Injected(\.backendHealthProbeService) private var healthProbe
    @Injected(\.mailStore) private var mailStore

    public enum Tab: String, CaseIterable, Identifiable {
        case backends = "Backends"
        case coreML = "On-Device Model"
        case confidenceRouting = "Confidence Routing"
        case about = "About & Telemetry"

        public var id: String { rawValue }

        public var iconName: String {
            switch self {
            case .backends: return "server.rack"
            case .coreML: return "cpu.fill"
            case .confidenceRouting: return "slider.horizontal.3"
            case .about: return "info.circle"
            }
        }
    }

    @State private var selectedTab: Tab = .backends
    @State private var probeStatuses: [TriageBackend: BackendHealthStatus] = [:]
    @State private var probingBackends: Set<TriageBackend> = []
    @State private var showingFileImporter: Bool = false

    @KeychainStorage(.cloudflareAccountId) private var cloudflareAccountId = ""
    @KeychainStorage(.cloudflareApiToken) private var cloudflareApiToken = ""
    @KeychainStorage(.typesafeApiKey) private var typesafeApiKey = ""
    @KeychainStorage(.hostedVpcToken) private var hostedVpcToken = ""

    public init() {}

    public var body: some View {
        Group {
            #if os(macOS)
            macOSLayout
                .frame(minWidth: 800, idealWidth: 860, minHeight: 540, idealHeight: 580)
            #else
            iOSLayout
            #endif
        }
        .onDisappear {
            Task { @MainActor in
                await mailStore.probeActiveBackend()
            }
        }
    }

    // MARK: - macOS 2-Column Sidebar Layout

    #if os(macOS)
    @ViewBuilder
    private var macOSLayout: some View {
        HStack(spacing: 0) {
            // Left Sidebar
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Tab.allCases) { tab in
                    let isSelected = selectedTab == tab
                    Button {
                        selectedTab = tab
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: tab.iconName)
                                .font(.system(size: 14, weight: .semibold))
                                .frame(width: 20)
                                .foregroundStyle(isSelected ? .white : .accentColor)

                            Text(tab.rawValue)
                                .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                                .foregroundStyle(isSelected ? .white : .primary)

                            Spacer()
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(
                            isSelected ? Color.accentColor : Color.clear,
                            in: RoundedRectangle(cornerRadius: 6, style: .continuous)
                        )
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }

                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.top, 20)
            .frame(width: 230)
            .background(Color(nsColor: .windowBackgroundColor).opacity(0.85))

            Divider()

            // Right Detail Pane
            VStack(spacing: 0) {
                // Top header with navigation chevrons and title
                HStack(spacing: 12) {
                    HStack(spacing: 4) {
                        Button {
                            selectPreviousTab()
                        } label: {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 12, weight: .semibold))
                                .frame(width: 24, height: 24)
                                .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 5))
                        }
                        .buttonStyle(.plain)
                        .disabled(selectedTab == Tab.allCases.first)
                        .opacity(selectedTab == Tab.allCases.first ? 0.35 : 1.0)

                        Button {
                            selectNextTab()
                        } label: {
                            Image(systemName: "chevron.right")
                                .font(.system(size: 12, weight: .semibold))
                                .frame(width: 24, height: 24)
                                .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 5))
                        }
                        .buttonStyle(.plain)
                        .disabled(selectedTab == Tab.allCases.last)
                        .opacity(selectedTab == Tab.allCases.last ? 0.35 : 1.0)
                    }

                    Text(selectedTab.rawValue)
                        .font(.title2.weight(.bold))
                        .foregroundStyle(.primary)

                    Spacer()

                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .keyboardShortcut(.cancelAction)
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 28)
                .padding(.top, 20)
                .padding(.bottom, 12)

                Divider()

                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        switch selectedTab {
                        case .backends:
                            backendsContent
                        case .coreML:
                            coreMLContent
                        case .confidenceRouting:
                            confidenceRoutingContent
                        case .about:
                            aboutContent
                        }
                    }
                    .padding(.horizontal, 28)
                    .padding(.vertical, 20)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(nsColor: .underPageBackgroundColor).opacity(0.4))
        }
    }

    private func selectPreviousTab() {
        guard let index = Tab.allCases.firstIndex(of: selectedTab), index > 0 else { return }
        selectedTab = Tab.allCases[index - 1]
    }

    private func selectNextTab() {
        guard let index = Tab.allCases.firstIndex(of: selectedTab), index < Tab.allCases.count - 1 else { return }
        selectedTab = Tab.allCases[index + 1]
    }
    #endif

    // MARK: - iOS Layout

    #if os(iOS)
    @ViewBuilder
    private var iOSLayout: some View {
        NavigationStack {
            VStack(spacing: 12) {
                Picker("", selection: $selectedTab) {
                    ForEach(Tab.allCases) { tab in
                        Label(tab.rawValue, systemImage: tab.iconName).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .padding(.horizontal)
                .padding(.top, 8)

                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        switch selectedTab {
                        case .backends:
                            backendsContent
                        case .coreML:
                            coreMLContent
                        case .confidenceRouting:
                            confidenceRoutingContent
                        case .about:
                            aboutContent
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle("Settings")
            .fileImporter(
                isPresented: $showingFileImporter,
                allowedContentTypes: [
                    UTType(filenameExtension: "mlmodel") ?? .data,
                    UTType(filenameExtension: "mlpackage") ?? .data,
                    UTType(filenameExtension: "mlmodelc") ?? .data,
                    UTType(filenameExtension: "safetensors") ?? .data,
                    .item
                ],
                allowsMultipleSelection: false
            ) { result in
                switch result {
                case .success(let urls):
                    guard let url = urls.first else { return }
                    Task {
                        try? await coreMLManager.importLocalModel(from: url)
                    }
                case .failure(let error):
                    Task { @MainActor in
                        coreMLManager.errorMessage = "Import failed: \(error.localizedDescription)"
                    }
                }
            }
        }
    }
    #endif

    // MARK: - Backends Tab Content

    @ViewBuilder
    private var backendsContent: some View {
        @Bindable var boundConfig = configStore

        // 1. TypeSafe Jev Cloud
        VStack(alignment: .leading, spacing: 8) {
            Text("TypeSafe Jev Cloud API")
                .font(.headline.weight(.bold))
                .foregroundStyle(.primary)

            SettingsCard {
                SettingsRow(title: "API Key", subtitle: "Stored securely in Keychain") {
                    SecureField("TYPESAFE_API_KEY", text: $typesafeApiKey)
                        .textFieldStyle(.roundedBorder)
                        #if os(iOS)
                        .textContentType(.password)
                        .autocapitalization(.none)
                        #endif
                }

                cardDivider

                SettingsRow(title: "Endpoint URL", subtitle: "Decision model inference route") {
                    TextField("https://api.typesafe.ai/v1/systemone", text: $boundConfig.jevCloudURL)
                        .textFieldStyle(.roundedBorder)
                        #if os(iOS)
                        .keyboardType(.URL)
                        .autocapitalization(.none)
                        #endif
                }

                cardDivider

                SettingsRow(title: "Connection Status") {
                    probeRow(for: .cloudAPI)
                }
            }
        }

        // 2. Local laya-serve (Loopback)
        VStack(alignment: .leading, spacing: 8) {
            Text("Local laya-serve (Loopback)")
                .font(.headline.weight(.bold))
                .foregroundStyle(.primary)

            SettingsCard {
                SettingsRow(title: "Local Endpoint", subtitle: "Default: http://127.0.0.1:8000/v1/systemone") {
                    TextField("http://127.0.0.1:8000/v1/systemone", text: $boundConfig.localServeURL)
                        .textFieldStyle(.roundedBorder)
                        #if os(iOS)
                        .keyboardType(.URL)
                        .autocapitalization(.none)
                        #endif
                }

                cardDivider

                SettingsRow(title: "Connection Status") {
                    probeRow(for: .localServe)
                }
            }
        }

        // 3. Enterprise Hosted VPC
        VStack(alignment: .leading, spacing: 8) {
            Text("Enterprise Hosted VPC")
                .font(.headline.weight(.bold))
                .foregroundStyle(.primary)

            SettingsCard {
                SettingsRow(title: "VPC Endpoint URL", subtitle: "Custom private cloud gateway") {
                    TextField("https://api.impossibl.com/v1/systemone", text: $boundConfig.hostedVpcURL)
                        .textFieldStyle(.roundedBorder)
                        #if os(iOS)
                        .keyboardType(.URL)
                        .autocapitalization(.none)
                        #endif
                }

                cardDivider

                SettingsRow(title: "Auth Token", subtitle: "Optional VPC bearer token") {
                    SecureField("Bearer Token", text: $hostedVpcToken)
                        .textFieldStyle(.roundedBorder)
                        #if os(iOS)
                        .textContentType(.password)
                        .autocapitalization(.none)
                        #endif
                }

                cardDivider

                SettingsRow(title: "Connection Status") {
                    probeRow(for: .hostedVPC)
                }
            }
        }

        // 4. Cloudflare Clef
        VStack(alignment: .leading, spacing: 8) {
            Text("Cloudflare Clef")
                .font(.headline.weight(.bold))
                .foregroundStyle(.primary)

            SettingsCard {
                SettingsRow(title: "Account ID", subtitle: "Cloudflare dashboard account identifier") {
                    TextField("Account ID", text: $cloudflareAccountId)
                        .textFieldStyle(.roundedBorder)
                        #if os(iOS)
                        .autocapitalization(.none)
                        #endif
                }

                cardDivider

                SettingsRow(title: "API Token", subtitle: "Workers AI API token stored securely in Keychain") {
                    SecureField("Workers AI Token", text: $cloudflareApiToken)
                        .textFieldStyle(.roundedBorder)
                        #if os(iOS)
                        .textContentType(.password)
                        .autocapitalization(.none)
                        #endif
                }

                cardDivider

                SettingsRow(title: "Connection Status") {
                    probeRow(for: .cloudflareClef)
                }
            }
        }

        // 5. Apple Intelligence Baseline
        VStack(alignment: .leading, spacing: 8) {
            Text("Apple Intelligence (Baseline)")
                .font(.headline.weight(.bold))
                .foregroundStyle(.primary)

            SettingsCard {
                SettingsRow(title: "Framework", subtitle: "FoundationModels SystemLanguageModel") {
                    Text("macOS System Model")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                cardDivider

                SettingsRow(title: "Connection Status") {
                    probeRow(for: .generativeBaseline)
                }
            }
        }

        // 5. Maintenance Actions
        VStack(alignment: .leading, spacing: 8) {
            Text("Diagnostics & Presets")
                .font(.headline.weight(.bold))
                .foregroundStyle(.primary)

            SettingsCard {
                HStack {
                    Button {
                        Task { await probeAll() }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "bolt.horizontal.fill")
                            Text("Probe All Backends")
                        }
                    }
                    .buttonStyle(.bordered)

                    Spacer()

                    Button("Reset to Defaults", role: .destructive) {
                        boundConfig.resetToDefaults()
                        typesafeApiKey = ""
                        hostedVpcToken = ""
                        cloudflareAccountId = ""
                        cloudflareApiToken = ""
                    }
                    .buttonStyle(.bordered)
                }
                .padding(.vertical, 2)
            }
        }
    }

    // MARK: - Core ML Tab Content

    @ViewBuilder
    private var coreMLContent: some View {
        @Bindable var boundConfig = configStore
        @Bindable var boundCoreML = coreMLManager

        // 1. Model Status
        VStack(alignment: .leading, spacing: 8) {
            Text("On-Device Laya Decision Model")
                .font(.headline.weight(.bold))
                .foregroundStyle(.primary)

            SettingsCard {
                SettingsRow(title: "Installation Status") {
                    HStack(spacing: 8) {
                        Image(systemName: "cpu.fill")
                            .foregroundStyle(boundCoreML.isInstalled ? .green : .orange)
                        Text(boundCoreML.isInstalled ? "Model Installed" : "Model Not Installed")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(boundCoreML.isInstalled ? .green : .orange)
                    }
                }

                cardDivider

                SettingsRow(title: "Size on Disk", subtitle: "Apple Neural Engine Optimized") {
                    Text(boundCoreML.modelSizeFormatted ?? "Not installed")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                if boundCoreML.isInstalled {
                    cardDivider

                    SettingsRow(title: "Storage Path") {
                        Text(boundCoreML.resolvedModelURL?.path ?? "Application Support/Models")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .multilineTextAlignment(.trailing)
                    }
                }
            }
        }

        // 2. Download & Package Setup
        VStack(alignment: .leading, spacing: 8) {
            Text("Model Package Download")
                .font(.headline.weight(.bold))
                .foregroundStyle(.primary)

            SettingsCard {
                SettingsRow(title: "Download URL", subtitle: "Direct .safetensors or repo URL") {
                    TextField("https://huggingface.co/aac6fef/laya-mlx/resolve/main/model.safetensors", text: $boundConfig.coreMLDownloadURL)
                        .textFieldStyle(.roundedBorder)
                        #if os(iOS)
                        .keyboardType(.URL)
                        .autocapitalization(.none)
                        #endif
                }

                cardDivider

                SettingsRow(title: "Hugging Face Token", subtitle: "Optional (public repos require none)") {
                    SecureField("hf_...", text: $boundConfig.huggingFaceToken)
                        .textFieldStyle(.roundedBorder)
                        #if os(iOS)
                        .textContentType(.password)
                        .autocapitalization(.none)
                        #endif
                }

                if boundCoreML.isDownloading || boundCoreML.isCompiling {
                    cardDivider

                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(boundCoreML.statusMessage)
                                .font(.caption.weight(.medium))
                            Spacer()
                            if boundCoreML.isDownloading {
                                Text("\(Int(boundCoreML.downloadProgress * 100))%")
                                    .font(.caption2.monospacedDigit())
                            }
                        }
                        ProgressView(value: boundCoreML.downloadProgress, total: 1.0)
                            .progressViewStyle(.linear)
                    }
                    .padding(.vertical, 4)
                }

                if let err = boundCoreML.errorMessage {
                    cardDivider

                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: "exclamationmark.circle.fill")
                            .foregroundStyle(.red)
                        Text(err)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.vertical, 2)
                }

                cardDivider

                HStack(spacing: 12) {
                    Button {
                        Task {
                            try? await boundCoreML.downloadAndCompile()
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.down.circle.fill")
                            Text(boundCoreML.isInstalled ? "Re-Download & Compile" : "Download & Compile Model")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(boundCoreML.isDownloading || boundCoreML.isCompiling)

                    Button {
                        #if os(macOS)
                        chooseLocalModelFile()
                        #else
                        showingFileImporter = true
                        #endif
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "folder.badge.plus")
                            Text("Choose Local Model File...")
                        }
                    }
                    .buttonStyle(.bordered)
                    .disabled(boundCoreML.isDownloading || boundCoreML.isCompiling)

                    if boundCoreML.isInstalled {
                        Spacer()
                        Button("Remove Model", role: .destructive) {
                            try? boundCoreML.removeInstalledModel()
                        }
                        .buttonStyle(.bordered)
                    }
                }
                .padding(.vertical, 4)
            }
        }

        // 3. Diagnostic Probe
        VStack(alignment: .leading, spacing: 8) {
            Text("Diagnostic Probe")
                .font(.headline.weight(.bold))
                .foregroundStyle(.primary)

            SettingsCard {
                SettingsRow(title: "Neural Engine Probe", subtitle: "Verifies weights on Apple Neural Engine") {
                    probeRow(for: .onDeviceCoreML)
                }
            }
        }
    }

    // MARK: - Confidence Routing Content

    @ViewBuilder
    private var confidenceRoutingContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Decision Routing Thresholds")
                .font(.headline.weight(.bold))
                .foregroundStyle(.primary)

            SettingsCard {
                SettingsRow(title: "Auto-Execute", subtitle: "≥ 85% calibrated confidence") {
                    Text("Automated Action")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.green)
                }

                cardDivider

                SettingsRow(title: "Confirmation Needed", subtitle: "60% – 84% calibrated confidence") {
                    Text("Interactive Prompt")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.orange)
                }

                cardDivider

                SettingsRow(title: "Escalate to Inbox", subtitle: "< 60% confidence or epistemic conflict") {
                    Text("Human Review")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.red)
                }

                cardDivider

                SettingsRow(title: "Uncertainty Band", subtitle: "35% – 65% boolean noul range") {
                    Text("Always Escalates")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
        }

        VStack(alignment: .leading, spacing: 8) {
            Text("Operational Tiers")
                .font(.headline.weight(.bold))
                .foregroundStyle(.primary)

            SettingsCard {
                SettingsRow(title: "Auto Executed") {
                    HStack(spacing: 8) {
                        Image(systemName: "bolt.shield.fill")
                            .foregroundStyle(.green)
                        Text("Applied without friction to spam/archive")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                cardDivider

                SettingsRow(title: "Confirmation Needed") {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.badge.questionmark.fill")
                            .foregroundStyle(.orange)
                        Text("Surfaces 1-click action chip in message view")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                cardDivider

                SettingsRow(title: "Escalated to Inbox") {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                        Text("Retained safely in inbox for manual triage")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    // MARK: - About Content

    @ViewBuilder
    private var aboutContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("System One Architecture")
                .font(.headline.weight(.bold))
                .foregroundStyle(.primary)

            SettingsCard {
                SettingsRow(title: "Application") {
                    Text("Mail Triage 1.0.0")
                        .font(.subheadline.weight(.medium))
                }

                cardDivider

                SettingsRow(title: "Framework") {
                    Text("Apple Foundation Models + TypeSafe Jev")
                        .font(.subheadline.weight(.medium))
                }

                cardDivider

                SettingsRow(title: "Concurrency") {
                    Text("Swift 6 Complete Strict Concurrency")
                        .font(.subheadline.weight(.medium))
                }

                cardDivider

                SettingsRow(title: "Hardware Target") {
                    Text("Apple Silicon Neural Engine (ANE) / GPU")
                        .font(.subheadline.weight(.medium))
                }
            }
        }

        VStack(alignment: .leading, spacing: 8) {
            Text("Privacy & Security")
                .font(.headline.weight(.bold))
                .foregroundStyle(.primary)

            SettingsCard {
                SettingsRow(title: "On-Device Privacy") {
                    Text("100% On-Device (Zero cloud leakage)")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.green)
                }

                cardDivider

                SettingsRow(title: "Credential Storage") {
                    Text("Hardware-backed Apple Keychain")
                        .font(.subheadline.weight(.medium))
                }

                cardDivider

                SettingsRow(title: "Calibration Metric") {
                    Text("Brier Scoring with Epistemic Banding")
                        .font(.subheadline.weight(.medium))
                }
            }
        }
    }

    // MARK: - Probe Row Helper

    @ViewBuilder
    private func probeRow(for backend: TriageBackend) -> some View {
        HStack(spacing: 8) {
            Button {
                Task { await probe(backend: backend) }
            } label: {
                if probingBackends.contains(backend) {
                    ProgressView().controlSize(.small)
                } else {
                    HStack(spacing: 4) {
                        Image(systemName: "waveform.path.ecg")
                        Text("Probe")
                    }
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(probingBackends.contains(backend))

            if let status = probeStatuses[backend] {
                switch status {
                case .healthy(let latencyMs):
                    HStack(spacing: 6) {
                        Circle()
                            .fill(.green)
                            .frame(width: 8, height: 8)
                        Text("Reachable (\(String(format: "%.1f", latencyMs)) ms)")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.green)
                    }
                case .unreachable(let reason, let guidance):
                    let isPreparing = status.isPreparing
                    let statusColor: Color = isPreparing ? .orange : .red
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(statusColor)
                                .frame(width: 8, height: 8)
                            Text(reason)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(statusColor)
                        }
                        Text(guidance)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                case .checking:
                    Text("Checking...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var cardDivider: some View {
        Divider()
            .padding(.vertical, 4)
    }

    private func probe(backend: TriageBackend) async {
        probingBackends.insert(backend)
        probeStatuses[backend] = .checking
        let status = await healthProbe.probe(backend: backend)
        probeStatuses[backend] = status
        probingBackends.remove(backend)

        if backend == mailStore.selectedBackend {
            mailStore.activeBackendStatus = status
            if case .unreachable(let reason, let guidance) = status {
                mailStore.activeBackendError = BackendUnreachableError(
                    backend: backend,
                    reason: reason,
                    guidance: guidance
                )
            } else {
                mailStore.activeBackendError = nil
            }
        }
    }

    private func probeAll() async {
        for backend in TriageBackend.allCases {
            probingBackends.insert(backend)
            probeStatuses[backend] = .checking
        }
        let results = await healthProbe.probeAll()
        for (backend, status) in results {
            probeStatuses[backend] = status
            probingBackends.remove(backend)

            if backend == mailStore.selectedBackend {
                mailStore.activeBackendStatus = status
                if case .unreachable(let reason, let guidance) = status {
                    mailStore.activeBackendError = BackendUnreachableError(
                        backend: backend,
                        reason: reason,
                        guidance: guidance
                    )
                } else {
                    mailStore.activeBackendError = nil
                }
            }
        }
    }

    #if os(macOS)
    @MainActor
    private func chooseLocalModelFile() {
        let panel = NSOpenPanel()
        panel.title = "Choose Local Model File"
        panel.message = "Select a Core ML model file (.mlmodel, .mlpackage, .mlmodelc, or .safetensors)"
        panel.prompt = "Import Model"
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [
            UTType(filenameExtension: "mlmodel") ?? .data,
            UTType(filenameExtension: "mlpackage") ?? .package,
            UTType(filenameExtension: "mlmodelc") ?? .folder,
            UTType(filenameExtension: "safetensors") ?? .data,
            UTType.data,
            UTType.package,
            UTType.folder
        ]

        if panel.runModal() == .OK, let selectedURL = panel.url {
            Task {
                try? await coreMLManager.importLocalModel(from: selectedURL)
            }
        }
    }
    #endif
}

// MARK: - Reusable Settings Card & Row Components

private struct SettingsCard<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(spacing: 0) {
            content()
        }
        .padding(14)
        #if os(macOS)
        .background(
            Color(nsColor: .controlBackgroundColor),
            in: RoundedRectangle(cornerRadius: 10, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
        #else
        .background(
            Color(uiColor: .secondarySystemGroupedBackground),
            in: RoundedRectangle(cornerRadius: 10, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
        #endif
    }
}

private struct SettingsRow<Accessory: View>: View {
    let title: String
    var subtitle: String? = nil
    @ViewBuilder let accessory: () -> Accessory

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)
                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 170, alignment: .leading)

            Spacer()

            accessory()
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    SettingsView()
}
