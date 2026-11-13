import SwiftUI
import FoundationModels
import SystemOneCore
import ClefFoundationModels
import OpenAIFoundationModels
import GeminiFoundationModels

#if canImport(UIKit) && !os(macOS)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

@Generable
private struct ConnectionProbeDecision: Sendable {
    @Guide(description: "Confirm endpoint readiness and authentication")
    var isReady: Bool
}

// MARK: - In-App Multi-Provider Vision Scanner Settings Sheet

/// Settings sheet for configuring all vision-capable System One providers and authenticated reverse proxies.
public struct SettingsSheetView: View {
    @Environment(\.dismiss) private var dismiss

    // 1. Cloudflare Clef / Clef-Flash
    @AppStorage("cloudflareAccountID") private var cloudflareAccountID: String = ""
    @AppStorage("cloudflareGatewayID") private var cloudflareGatewayID: String = ""
    @KeychainStorage("cloudflareAPIToken") private var cloudflareAPIToken: String = ""

    // 2. Local Clef Runner
    @AppStorage("localRunnerURL") private var localRunnerURL: String = "http://127.0.0.1:8000"

    // 3. OpenAI Decisions (gpt-6-luna)
    @KeychainStorage("openAIAPIKey") private var openAIAPIKey: String = ""

    // 4. Google Gemini Decisions (gemini-decision-1)
    @KeychainStorage("geminiAPIKey") private var geminiAPIKey: String = ""

    // 5. Authenticated Reverse Proxy
    @AppStorage("systemOneProxyURL") private var systemOneProxyURL: String = ""
    @AppStorage("systemOneProxyModelID") private var systemOneProxyModelID: String = "systemone-default"
    @KeychainStorage("systemOneProxyBearerToken") private var systemOneProxyBearerToken: String = ""
    @KeychainStorage("firebaseAppCheckToken") private var firebaseAppCheckToken: String = ""

    @State private var testingBackend: InspectionBackendSelection?
    @State private var testResults: [InspectionBackendSelection: ConnectionTestResult] = [:]

    public init() {}

    public var body: some View {
        NavigationStack {
            Form {
                // Section 1: Cloudflare Workers AI (Clef-Flash 9B & Clef 27B)
                Section {
                    PlainSettingField(
                        title: "Account ID",
                        placeholder: "Cloudflare Account ID",
                        text: $cloudflareAccountID,
                        onPaste: pasteClipboard(into: $cloudflareAccountID)
                    )

                    PlainSettingField(
                        title: "AI Gateway ID (Optional)",
                        placeholder: "Optional Cloudflare AI Gateway slug",
                        text: $cloudflareGatewayID,
                        onPaste: pasteClipboard(into: $cloudflareGatewayID)
                    )

                    SecretKeychainField(
                        title: "API Token",
                        placeholder: "Cloudflare Workers AI API Token",
                        text: $cloudflareAPIToken,
                        onPaste: pasteClipboard(into: $cloudflareAPIToken)
                    )

                    ProbeButton(
                        title: "Test Cloudflare Clef-Flash",
                        icon: "bolt.horizontal.icloud.fill",
                        isTesting: testingBackend == .workersAIFlash
                    ) {
                        Task { await probeBackend(.workersAIFlash) }
                    }

                    if let result = testResults[.workersAIFlash] {
                        TestResultBanner(result: result)
                    }
                } header: {
                    Text("Cloudflare Workers AI (Clef-Flash 9B & Clef 27B)")
                } footer: {
                    Text("Falls back to CLOUDFLARE_ACCOUNT_ID, CLOUDFLARE_GATEWAY_ID, and CLOUDFLARE_API_TOKEN environment variables when left empty.")
                }

                // Section 2: Local Clef Runner
                Section {
                    PlainSettingField(
                        title: "Local Clef Runner URL",
                        placeholder: "http://127.0.0.1:8000",
                        text: $localRunnerURL,
                        defaultResetValue: "http://127.0.0.1:8000",
                        onPaste: pasteClipboard(into: $localRunnerURL)
                    )

                    ProbeButton(
                        title: "Test Local Clef Runner",
                        icon: "desktopcomputer",
                        isTesting: testingBackend == .localRunner
                    ) {
                        Task { await probeBackend(.localRunner) }
                    }

                    if let result = testResults[.localRunner] {
                        TestResultBanner(result: result)
                    }
                } header: {
                    Text("Local Clef Runner (localhost:8000)")
                } footer: {
                    Text("Endpoint for Tools/ClefLocalRunner/server.py, Docker Model Runner, or MLX serving Clef locally.")
                }

                // Section 3: OpenAI Decisions (gpt-6-luna)
                Section {
                    SecretKeychainField(
                        title: "OpenAI API Key",
                        placeholder: "sk-...",
                        text: $openAIAPIKey,
                        onPaste: pasteClipboard(into: $openAIAPIKey)
                    )

                    ProbeButton(
                        title: "Test OpenAI Decisions (gpt-6-luna)",
                        icon: "sparkles",
                        isTesting: testingBackend == .openAIDecisions
                    ) {
                        Task { await probeBackend(.openAIDecisions) }
                    }

                    if let result = testResults[.openAIDecisions] {
                        TestResultBanner(result: result)
                    }
                } header: {
                    Text("OpenAI Decisions (gpt-6-luna)")
                } footer: {
                    Text("Stored in Keychain; falls back to OPENAI_API_KEY environment variable when empty.")
                }

                // Section 4: Google Gemini Decisions (gemini-decision-1)
                Section {
                    SecretKeychainField(
                        title: "Gemini API Key",
                        placeholder: "AIza...",
                        text: $geminiAPIKey,
                        onPaste: pasteClipboard(into: $geminiAPIKey)
                    )

                    ProbeButton(
                        title: "Test Gemini Decisions (gemini-decision-1)",
                        icon: "wand.and.stars",
                        isTesting: testingBackend == .geminiDecisions
                    ) {
                        Task { await probeBackend(.geminiDecisions) }
                    }

                    if let result = testResults[.geminiDecisions] {
                        TestResultBanner(result: result)
                    }
                } header: {
                    Text("Google Gemini Decisions (gemini-decision-1)")
                } footer: {
                    Text("Stored in Keychain; falls back to GEMINI_API_KEY or GOOGLE_API_KEY environment variables when empty.")
                }

                // Section 5: Authenticated Reverse Proxy
                Section {
                    PlainSettingField(
                        title: "Proxy Endpoint URL",
                        placeholder: "https://your-gateway.example.com/v1/systemone",
                        text: $systemOneProxyURL,
                        onPaste: pasteClipboard(into: $systemOneProxyURL)
                    )

                    PlainSettingField(
                        title: "Target Model ID",
                        placeholder: "systemone-default",
                        text: $systemOneProxyModelID,
                        defaultResetValue: "systemone-default",
                        onPaste: pasteClipboard(into: $systemOneProxyModelID)
                    )

                    SecretKeychainField(
                        title: "Bearer Token (Optional)",
                        placeholder: "Optional Authorization: Bearer token",
                        text: $systemOneProxyBearerToken,
                        onPaste: pasteClipboard(into: $systemOneProxyBearerToken)
                    )

                    SecretKeychainField(
                        title: "Firebase App Check Token (Optional)",
                        placeholder: "Optional X-Firebase-AppCheck attestation token",
                        text: $firebaseAppCheckToken,
                        onPaste: pasteClipboard(into: $firebaseAppCheckToken)
                    )

                    ProbeButton(
                        title: "Test Authenticated Reverse Proxy",
                        icon: "lock.shield.fill",
                        isTesting: testingBackend == .reverseProxy
                    ) {
                        Task { await probeBackend(.reverseProxy) }
                    }

                    if let result = testResults[.reverseProxy] {
                        TestResultBanner(result: result)
                    }
                } header: {
                    Text("Authenticated Reverse Proxy (Zero-Secret Production)")
                } footer: {
                    Text("Routes canonical System One multimodal requests through SystemOneLanguageModel(proxyEndpoint:supportsVision: true). Falls back to SYSTEM_ONE_PROXY_URL, SYSTEM_ONE_PROXY_TOKEN, and FIREBASE_APPCHECK_TOKEN.")
                }

                // Section 6: Active Configuration Diagnostics
                Section {
                    CredentialSourceRow(
                        label: "Cloudflare Clef",
                        hasStored: !cloudflareAccountID.trimmed.isEmpty && !cloudflareAPIToken.trimmed.isEmpty,
                        storedTitle: "AppStorage + Keychain",
                        hasEnv: hasEnv("CLOUDFLARE_ACCOUNT_ID") && hasEnv("CLOUDFLARE_API_TOKEN")
                    )
                    CredentialSourceRow(
                        label: "OpenAI Decisions",
                        hasStored: !openAIAPIKey.trimmed.isEmpty,
                        storedTitle: "Keychain (Saved)",
                        hasEnv: hasEnv("OPENAI_API_KEY")
                    )
                    CredentialSourceRow(
                        label: "Gemini Decisions",
                        hasStored: !geminiAPIKey.trimmed.isEmpty,
                        storedTitle: "Keychain (Saved)",
                        hasEnv: hasEnv("GEMINI_API_KEY") || hasEnv("GOOGLE_API_KEY")
                    )
                    CredentialSourceRow(
                        label: "Reverse Proxy",
                        hasStored: !systemOneProxyURL.trimmed.isEmpty,
                        storedTitle: "AppStorage + Keychain",
                        hasEnv: hasEnv("SYSTEM_ONE_PROXY_URL") || hasEnv("TYPESAFE_PROXY_URL")
                    )
                } header: {
                    Text("Active Configuration")
                } footer: {
                    Text("Saved values (endpoints in AppStorage, secrets in Keychain) take precedence over environment variables.")
                }
            }
            .navigationTitle("Vision Provider Settings")
            #if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 500, minHeight: 620)
        #endif
    }

    // MARK: - Live Provider Probe

    private func probeBackend(_ backend: InspectionBackendSelection) async {
        guard testingBackend == nil else { return }
        testingBackend = backend
        testResults[backend] = nil
        defer { testingBackend = nil }

        do {
            let model = try backend.resolveLanguageModel(
                accountID: cloudflareAccountID,
                gatewayID: cloudflareGatewayID,
                cloudflareAPIToken: cloudflareAPIToken,
                localRunnerURL: localRunnerURL,
                openAIAPIKey: openAIAPIKey,
                geminiAPIKey: geminiAPIKey,
                proxyURLString: systemOneProxyURL,
                proxyBearerToken: systemOneProxyBearerToken,
                appCheckToken: firebaseAppCheckToken,
                proxyModelID: systemOneProxyModelID
            )
            let startTime = CFAbsoluteTimeGetCurrent()
            _ = try await runProbeSession(using: model)
            let elapsedMs = Int((CFAbsoluteTimeGetCurrent() - startTime) * 1000)
            testResults[backend] = .success("\(backend.displayName) reachable & authenticated (\(elapsedMs)ms).")
        } catch is CancellationError {
            return
        } catch {
            testResults[backend] = .failure(error.localizedDescription)
        }
    }

    private func runProbeSession(using model: some LanguageModel) async throws -> LanguageModelSession.Response<ConnectionProbeDecision> {
        let session = LanguageModelSession(model: model)
        return try await session.respond(
            to: "Connectivity and authentication probe.",
            generating: ConnectionProbeDecision.self
        )
    }

    private func hasEnv(_ key: String) -> Bool {
        guard let val = ProcessInfo.processInfo.environment[key]?.trimmed else { return false }
        return !val.isEmpty
    }

    private func pasteClipboard(into binding: Binding<String>) -> () -> Void {
        {
            if let clip = getClipboardText()?.trimmed, !clip.isEmpty {
                binding.wrappedValue = clip
            }
        }
    }

    private func getClipboardText() -> String? {
        #if canImport(UIKit) && !os(macOS)
        return UIPasteboard.general.string
        #elseif canImport(AppKit)
        return NSPasteboard.general.string(forType: .string)
        #else
        return nil
        #endif
    }
}

// MARK: - Reusable Settings Subviews

private struct PlainSettingField: View {
    let title: String
    let placeholder: String
    @Binding var text: String
    var defaultResetValue: String? = nil
    let onPaste: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack {
                TextField(placeholder, text: $text)
                    .autocorrectionDisabled()
                    #if !os(macOS)
                    .textInputAutocapitalization(.never)
                    #endif
                    .font(.callout)

                if let defaultResetValue {
                    if text != defaultResetValue {
                        Button {
                            text = defaultResetValue
                        } label: {
                            Image(systemName: "arrow.counterclockwise")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Reset \(title)")
                    }
                } else if !text.isEmpty {
                    Button {
                        text = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear \(title)")
                }

                Button(action: onPaste) {
                    Label("Paste", systemImage: "doc.on.clipboard")
                        .labelStyle(.iconOnly)
                        .foregroundStyle(.cyan)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Paste \(title)")
            }
        }
        .padding(.vertical, 2)
    }
}

private struct SecretKeychainField: View {
    let title: String
    let placeholder: String
    @Binding var text: String
    let onPaste: () -> Void
    @State private var isVisible: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack {
                Group {
                    if isVisible {
                        TextField(placeholder, text: $text)
                    } else {
                        SecureField(placeholder, text: $text)
                    }
                }
                .autocorrectionDisabled()
                #if !os(macOS)
                .textInputAutocapitalization(.never)
                #endif
                .font(.callout)

                Button {
                    isVisible.toggle()
                } label: {
                    Image(systemName: isVisible ? "eye.slash" : "eye")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isVisible ? "Hide \(title)" : "Show \(title)")

                if !text.isEmpty {
                    Button {
                        text = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear \(title)")
                }

                Button(action: onPaste) {
                    Label("Paste", systemImage: "doc.on.clipboard")
                        .labelStyle(.iconOnly)
                        .foregroundStyle(.cyan)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Paste \(title)")
            }
        }
        .padding(.vertical, 2)
    }
}

private struct ProbeButton: View {
    let title: String
    let icon: String
    let isTesting: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if isTesting {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: icon)
                }
                Text(isTesting ? "Testing..." : title)
                    .fontWeight(.medium)
            }
            .frame(maxWidth: .infinity)
        }
        .disabled(isTesting)
        .buttonStyle(.bordered)
    }
}

private struct CredentialSourceRow: View {
    let label: String
    let hasStored: Bool
    let storedTitle: String
    let hasEnv: Bool

    var body: some View {
        LabeledContent(label) {
            if hasStored {
                Label(storedTitle, systemImage: "lock.shield.fill")
                    .foregroundStyle(.green)
                    .font(.caption)
            } else if hasEnv {
                Label("Environment Variable", systemImage: "terminal.fill")
                    .foregroundStyle(.cyan)
                    .font(.caption)
            } else {
                Label("Not Configured", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }
        }
    }
}

private enum ConnectionTestResult: Sendable, Equatable {
    case success(String)
    case failure(String)
}

private struct TestResultBanner: View {
    let result: ConnectionTestResult

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            switch result {
            case .success(let msg):
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text(msg)
                    .font(.caption)
                    .foregroundStyle(.green)
            case .failure(let msg):
                Image(systemName: "xmark.octagon.fill")
                    .foregroundStyle(.red)
                Text(msg)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .padding(.vertical, 4)
    }
}

private extension String {
    var trimmed: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
