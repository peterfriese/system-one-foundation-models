import SwiftUI
import UniformTypeIdentifiers
import UIKit

// MARK: - Multi-Provider Configuration Sheet (All 6 Providers + Reverse Proxy)

public struct ProviderSettingsSheetView: View {
    @Bindable var viewModel: ScannerViewModel
    @Environment(\.dismiss) private var dismiss

    // 1. On-Device Laya Core ML
    @AppStorage("layaModelPath") private var layaModelPath: String = ""
    @State private var isCoreMLImporterPresented: Bool = false
    @State private var modelImportMessage: String?

    // 2. Local Laya Server (laya-serve)
    @AppStorage("layaServeURL") private var layaServeURL: String = "http://127.0.0.1:8000"
    @KeychainStorage("layaServeAPIKey") private var layaServeAPIKey: String = ""

    // 3. TypeSafe Jev Cloud
    @KeychainStorage("typesafeAPIKey") private var typesafeAPIKey: String = ""

    // 4. Cloudflare Clef
    @AppStorage("cloudflareAccountID") private var cloudflareAccountID: String = ""
    @AppStorage("cloudflareGatewayID") private var cloudflareGatewayID: String = ""
    @KeychainStorage("cloudflareAPIToken") private var cloudflareAPIToken: String = ""
    @AppStorage("clefLocalPort") private var clefLocalPort: String = ""
    @AppStorage("clefUse27BModel") private var clefUse27BModel: Bool = false

    // 5. OpenAI Decisions (gpt-6-luna)
    @KeychainStorage("openAIAPIKey") private var openAIAPIKey: String = ""

    // 6. Google Gemini Decisions (gemini-decision-1)
    @KeychainStorage("geminiAPIKey") private var geminiAPIKey: String = ""

    // 7. Authenticated Reverse Proxy
    @AppStorage("nutritionProxyURL") private var nutritionProxyURL: String = ""
    @AppStorage("nutritionProxyModelID") private var nutritionProxyModelID: String = "systemone-default"
    @AppStorage("nutritionProxySupportsVision") private var nutritionProxySupportsVision: Bool = true
    @KeychainStorage("systemOneProxyBearerToken") private var proxyBearerToken: String = ""
    @KeychainStorage("firebaseAppCheckToken") private var firebaseAppCheckToken: String = ""

    public init(viewModel: ScannerViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        NavigationStack {
            Form {
                // Active Provider Picker
                Section {
                    Picker("Decision Provider", selection: $viewModel.selectedProvider) {
                        ForEach(NutritionScannerProvider.allCases) { provider in
                            Label(provider.displayName, systemImage: provider.systemImageName)
                                .tag(provider)
                        }
                    }
                    .pickerStyle(.navigationLink)

                    HStack(spacing: 8) {
                        Image(systemName: viewModel.selectedProvider.effectiveSupportsVision ? "eye.fill" : "doc.plaintext.fill")
                            .foregroundStyle(viewModel.selectedProvider.effectiveSupportsVision ? .cyan : .secondary)
                        Text(
                            viewModel.selectedProvider.effectiveSupportsVision
                                ? "Multimodal Vision Enabled (sends OCR text + label photo Attachment)"
                                : "Structured Text Mode (sends OCR / Open Food Facts state)"
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Active System One Provider")
                }

                // Provider-Specific Configuration Sections
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Core ML Model Path (.mlmodelc / .mlpackage)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        HStack {
                            TextField("/path/to/LayaDecisionModel.mlmodelc", text: $layaModelPath)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .font(.callout)
                            if !layaModelPath.isEmpty {
                                Button {
                                    layaModelPath = ""
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundStyle(.secondary)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    Button {
                        isCoreMLImporterPresented = true
                    } label: {
                        Label("Import .mlmodelc / .mlpackage…", systemImage: "folder.badge.plus")
                    }

                    if let modelImportMessage {
                        Text(modelImportMessage)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("1. On-Device Laya Core ML (Offline)")
                } footer: {
                    Text("Runs 100% offline via LayaOnDeviceLanguageModel. Also checks LAYA_MODEL_PATH and bundled LayaDecisionModel.mlmodelc.")
                }

                Section {
                    EndpointTextField(title: "Server URL", placeholder: "http://127.0.0.1:8000", text: $layaServeURL)
                    KeychainSecretField(title: "Optional API Key", placeholder: "Optional LAYA_API_KEY", text: $layaServeAPIKey)
                } header: {
                    Text("2. Local Laya Server (laya-serve)")
                } footer: {
                    Text("Connects to `laya-serve` via LayaLanguageModel. Falls back to LAYA_SERVE_URL or http://127.0.0.1:8000.")
                }

                Section {
                    KeychainSecretField(title: "TypeSafe API Key", placeholder: "ts-...", text: $typesafeAPIKey)
                } header: {
                    Text("3. TypeSafe Jev Cloud")
                } footer: {
                    Text("Stored in Keychain; falls back to TYPESAFE_API_KEY environment variable.")
                }

                Section {
                    EndpointTextField(title: "Cloudflare Account ID", placeholder: "Account ID", text: $cloudflareAccountID)
                    EndpointTextField(title: "AI Gateway ID (Optional)", placeholder: "Optional Gateway slug", text: $cloudflareGatewayID)
                    KeychainSecretField(title: "Cloudflare API Token", placeholder: "Workers AI Token", text: $cloudflareAPIToken)
                    EndpointTextField(title: "Local Runner Port (Optional)", placeholder: "e.g. 8000 (CLEF_LOCAL_PORT)", text: $clefLocalPort)
                    Toggle("Use Clef 27B (instead of Clef-Flash 9B)", isOn: $clefUse27BModel)
                } header: {
                    Text("4. Cloudflare Clef (Multimodal Vision)")
                } footer: {
                    Text("Evaluates both extracted text and captured nutrition label imagery via ClefLanguageModel.")
                }

                Section {
                    KeychainSecretField(title: "OpenAI API Key", placeholder: "sk-...", text: $openAIAPIKey)
                } header: {
                    Text("5. OpenAI Decisions (gpt-6-luna, Vision)")
                } footer: {
                    Text("Stored in Keychain; falls back to OPENAI_API_KEY.")
                }

                Section {
                    KeychainSecretField(title: "Gemini API Key", placeholder: "AIza...", text: $geminiAPIKey)
                } header: {
                    Text("6. Google Gemini Decisions (gemini-decision-1, Vision)")
                } footer: {
                    Text("Stored in Keychain; falls back to GEMINI_API_KEY or GOOGLE_API_KEY.")
                }

                Section {
                    EndpointTextField(
                        title: "Proxy Endpoint URL",
                        placeholder: "https://your-gateway.example.com/v1/systemone",
                        text: $nutritionProxyURL
                    )
                    EndpointTextField(
                        title: "Target Model ID",
                        placeholder: "systemone-default",
                        text: $nutritionProxyModelID
                    )
                    Toggle("Proxy Backend Supports Vision Attachments", isOn: $nutritionProxySupportsVision)
                    KeychainSecretField(
                        title: "Bearer Token (Optional)",
                        placeholder: "SYSTEM_ONE_PROXY_TOKEN",
                        text: $proxyBearerToken
                    )
                    KeychainSecretField(
                        title: "Firebase App Check Token (Optional)",
                        placeholder: "FIREBASE_APPCHECK_TOKEN",
                        text: $firebaseAppCheckToken
                    )
                } header: {
                    Text("7. Authenticated Reverse Proxy (Production)")
                } footer: {
                    Text("Zero-secret production gateway via SystemOneLanguageModel(proxyEndpoint:supportsVision:credential:). Falls back to SYSTEM_ONE_PROXY_URL / TYPESAFE_PROXY_URL.")
                }
            }
            .navigationTitle("System One Providers")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        viewModel.triggerEvaluation()
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
            .fileImporter(
                isPresented: $isCoreMLImporterPresented,
                allowedContentTypes: [.folder, .package, .item],
                allowsMultipleSelection: false
            ) { result in
                switch result {
                case .success(let urls):
                    guard let selectedURL = urls.first else { return }
                    do {
                        let importedPath = try NutritionScannerProvider.importCoreMLModel(from: selectedURL)
                        layaModelPath = importedPath
                        modelImportMessage = "Imported \(selectedURL.lastPathComponent)"
                        viewModel.selectedProvider = .layaOnDevice
                    } catch {
                        modelImportMessage = "Import failed: \(error.localizedDescription)"
                    }
                case .failure(let error):
                    modelImportMessage = "Import cancelled/failed: \(error.localizedDescription)"
                }
            }
        }
    }
}

// MARK: - Reusable Field Components

private struct EndpointTextField: View {
    let title: String
    let placeholder: String
    @Binding var text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack {
                TextField(placeholder, text: $text)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(.callout)
                if !text.isEmpty {
                    Button {
                        text = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                Button {
                    if let pasted = UIPasteboard.general.string?.trimmingCharacters(in: .whitespacesAndNewlines),
                       !pasted.isEmpty {
                        text = pasted
                    }
                } label: {
                    Image(systemName: "doc.on.clipboard")
                        .foregroundStyle(.cyan)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 2)
    }
}

private struct KeychainSecretField: View {
    let title: String
    let placeholder: String
    @Binding var text: String
    @State private var isRevealed: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack {
                Group {
                    if isRevealed {
                        TextField(placeholder, text: $text)
                    } else {
                        SecureField(placeholder, text: $text)
                    }
                }
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .font(.callout)

                Button {
                    isRevealed.toggle()
                } label: {
                    Image(systemName: isRevealed ? "eye.slash" : "eye")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)

                if !text.isEmpty {
                    Button {
                        text = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }

                Button {
                    if let pasted = UIPasteboard.general.string?.trimmingCharacters(in: .whitespacesAndNewlines),
                       !pasted.isEmpty {
                        text = pasted
                    }
                } label: {
                    Image(systemName: "doc.on.clipboard")
                        .foregroundStyle(.cyan)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 2)
    }
}
