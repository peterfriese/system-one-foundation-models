import SwiftUI
import ClefFoundationModels
import SystemOneCore

#if canImport(UIKit) && !os(macOS)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

// MARK: - In-App Scanner Settings Sheet

/// A settings sheet for managing Cloudflare Workers AI credentials and local runner topology.
public struct SettingsSheetView: View {
    @Environment(\.dismiss) private var dismiss

    @AppStorage("cloudflareAccountID") private var cloudflareAccountID: String = ""
    @AppStorage("cloudflareAPIToken") private var cloudflareAPIToken: String = ""
    @AppStorage("localRunnerURL") private var localRunnerURL: String = "http://127.0.0.1:8000"

    @State private var isTokenVisible: Bool = false
    @State private var isTestingCloudflare: Bool = false
    @State private var cloudflareTestResult: ConnectionTestResult?
    @State private var isTestingLocalRunner: Bool = false
    @State private var localRunnerTestResult: ConnectionTestResult?

    public init() {}

    public var body: some View {
        NavigationStack {
            Form {
                // Section 1: Cloudflare Credentials
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Account ID")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        HStack {
                            TextField("Enter Cloudflare Account ID", text: $cloudflareAccountID)
                                .autocorrectionDisabled()
                                #if !os(macOS)
                                .textInputAutocapitalization(.never)
                                #endif
                                .font(.callout)

                            if !cloudflareAccountID.isEmpty {
                                Button {
                                    cloudflareAccountID = ""
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundStyle(.secondary)
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Clear Account ID")
                            }

                            Button {
                                if let clip = getClipboardText(), !clip.isEmpty {
                                    cloudflareAccountID = clip.trimmingCharacters(in: .whitespacesAndNewlines)
                                }
                            } label: {
                                Label("Paste", systemImage: "doc.on.clipboard")
                                    .labelStyle(.iconOnly)
                                    .foregroundStyle(.cyan)
                            }
                            .buttonStyle(.plain)
                            .help("Paste Account ID from clipboard")
                            .accessibilityLabel("Paste Account ID")
                        }
                    }
                    .padding(.vertical, 2)

                    VStack(alignment: .leading, spacing: 6) {
                        Text("API Token")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        HStack {
                            Group {
                                if isTokenVisible {
                                    TextField("Enter Cloudflare API Token", text: $cloudflareAPIToken)
                                } else {
                                    SecureField("Enter Cloudflare API Token", text: $cloudflareAPIToken)
                                }
                            }
                            .autocorrectionDisabled()
                            #if !os(macOS)
                            .textInputAutocapitalization(.never)
                            #endif
                            .font(.callout)

                            Button {
                                isTokenVisible.toggle()
                            } label: {
                                Image(systemName: isTokenVisible ? "eye.slash" : "eye")
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                            .help(isTokenVisible ? "Hide token" : "Show token")
                            .accessibilityLabel(isTokenVisible ? "Hide API Token" : "Show API Token")

                            if !cloudflareAPIToken.isEmpty {
                                Button {
                                    cloudflareAPIToken = ""
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundStyle(.secondary)
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Clear API Token")
                            }

                            Button {
                                if let clip = getClipboardText(), !clip.isEmpty {
                                    cloudflareAPIToken = clip.trimmingCharacters(in: .whitespacesAndNewlines)
                                }
                            } label: {
                                Label("Paste", systemImage: "doc.on.clipboard")
                                    .labelStyle(.iconOnly)
                                    .foregroundStyle(.cyan)
                            }
                            .buttonStyle(.plain)
                            .help("Paste API Token from clipboard")
                            .accessibilityLabel("Paste API Token")
                        }
                    }
                    .padding(.vertical, 2)

                    Button {
                        Task { await testCloudflareConnection() }
                    } label: {
                        HStack(spacing: 8) {
                            if isTestingCloudflare {
                                ProgressView()
                                    .controlSize(.small)
                                    .tint(.white)
                            } else {
                                Image(systemName: "network")
                            }
                            Text(isTestingCloudflare ? "Testing Cloudflare..." : "Test Connection")
                                .fontWeight(.medium)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .disabled(isTestingCloudflare)
                    .buttonStyle(.borderedProminent)
                    .tint(.cyan)

                    if let result = cloudflareTestResult {
                        TestResultBanner(result: result)
                    }
                } header: {
                    Text("Cloudflare Workers AI")
                } footer: {
                    Text("Used for remote inference with Clef (27B) and Clef-Flash (9B). If empty, values fall back to CLOUDFLARE_ACCOUNT_ID and CLOUDFLARE_API_TOKEN environment variables.")
                }

                // Section 2: Local Inference Runner
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Runner Endpoint URL")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        HStack {
                            TextField("http://127.0.0.1:8000", text: $localRunnerURL)
                                .autocorrectionDisabled()
                                #if !os(macOS)
                                .textInputAutocapitalization(.never)
                                .keyboardType(.URL)
                                #endif
                                .font(.callout)

                            if localRunnerURL != "http://127.0.0.1:8000" {
                                Button {
                                    localRunnerURL = "http://127.0.0.1:8000"
                                } label: {
                                    Image(systemName: "arrow.counterclockwise")
                                        .foregroundStyle(.secondary)
                                }
                                .buttonStyle(.plain)
                                .help("Reset to default")
                                .accessibilityLabel("Reset URL to default")
                            }

                            Button {
                                if let clip = getClipboardText(), !clip.isEmpty {
                                    localRunnerURL = clip.trimmingCharacters(in: .whitespacesAndNewlines)
                                }
                            } label: {
                                Label("Paste", systemImage: "doc.on.clipboard")
                                    .labelStyle(.iconOnly)
                                    .foregroundStyle(.cyan)
                            }
                            .buttonStyle(.plain)
                            .help("Paste URL from clipboard")
                            .accessibilityLabel("Paste Local Runner URL")
                        }
                    }
                    .padding(.vertical, 2)

                    Button {
                        Task { await testLocalRunnerConnection() }
                    } label: {
                        HStack(spacing: 8) {
                            if isTestingLocalRunner {
                                ProgressView()
                                    .controlSize(.small)
                            } else {
                                Image(systemName: "server.rack")
                            }
                            Text(isTestingLocalRunner ? "Connecting to Runner..." : "Test Local Runner")
                                .fontWeight(.medium)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .disabled(isTestingLocalRunner)
                    .buttonStyle(.bordered)

                    if let result = localRunnerTestResult {
                        TestResultBanner(result: result)
                    }
                } header: {
                    Text("Local Runner Configuration")
                } footer: {
                    Text("Endpoint for Docker Model Runner, vLLM, or MLX running Clef locally on your machine.")
                }

                // Section 3: Credential Resolution Diagnostics
                Section {
                    LabeledContent("Account ID Source") {
                        if !cloudflareAccountID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            Label("AppStorage (Saved)", systemImage: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                                .font(.caption)
                        } else if let env = ProcessInfo.processInfo.environment["CLOUDFLARE_ACCOUNT_ID"], !env.isEmpty {
                            Label("Environment Variable", systemImage: "terminal.fill")
                                .foregroundStyle(.cyan)
                                .font(.caption)
                        } else {
                            Label("Not Set", systemImage: "exclamationmark.triangle.fill")
                                .foregroundStyle(.red)
                                .font(.caption)
                        }
                    }

                    LabeledContent("API Token Source") {
                        if !cloudflareAPIToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            Label("AppStorage (Saved)", systemImage: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                                .font(.caption)
                        } else if let env = ProcessInfo.processInfo.environment["CLOUDFLARE_API_TOKEN"], !env.isEmpty {
                            Label("Environment Variable", systemImage: "terminal.fill")
                                .foregroundStyle(.cyan)
                                .font(.caption)
                        } else {
                            Label("Not Set", systemImage: "exclamationmark.triangle.fill")
                                .foregroundStyle(.red)
                                .font(.caption)
                        }
                    }
                } header: {
                    Text("Active Configuration")
                } footer: {
                    Text("Credentials stored in AppStorage take precedence over environment variables.")
                }
            }
            .navigationTitle("Scanner Settings")
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
        .frame(minWidth: 460, minHeight: 520)
        #endif
    }

    // MARK: - Connection Probes

    private func testCloudflareConnection() async {
        guard !isTestingCloudflare else { return }
        isTestingCloudflare = true
        cloudflareTestResult = nil
        defer { isTestingCloudflare = false }

        let effectiveAccountID = cloudflareAccountID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? (ProcessInfo.processInfo.environment["CLOUDFLARE_ACCOUNT_ID"] ?? "")
            : cloudflareAccountID.trimmingCharacters(in: .whitespacesAndNewlines)

        let effectiveToken = cloudflareAPIToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? (ProcessInfo.processInfo.environment["CLOUDFLARE_API_TOKEN"] ?? "")
            : cloudflareAPIToken.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !effectiveAccountID.isEmpty else {
            cloudflareTestResult = .failure("Missing Account ID. Enter your Cloudflare Account ID or set CLOUDFLARE_ACCOUNT_ID.")
            return
        }

        guard !effectiveToken.isEmpty else {
            cloudflareTestResult = .failure("Missing API Token. Enter your Cloudflare API Token or set CLOUDFLARE_API_TOKEN.")
            return
        }

        // Lightweight validation probe against Cloudflare Workers AI endpoint
        let endpointURL = URL(string: "https://api.cloudflare.com/client/v4/accounts/\(effectiveAccountID)/ai/run/@cf/cloudflare/clef-flash")!
        var request = URLRequest(url: endpointURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(effectiveToken)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 12.0

        let probePayload = SystemOneRequest(
            state: "Connection probe",
            model: ClefModel.clefFlash.rawValue,
            questions: [
                "ready": .noul(instructions: "Verify endpoint readiness and authorization.")
            ]
        )

        do {
            request.httpBody = try JSONEncoder().encode(probePayload)
            let startTime = CFAbsoluteTimeGetCurrent()
            let (data, response) = try await URLSession.shared.data(for: request)
            let elapsedMs = Int((CFAbsoluteTimeGetCurrent() - startTime) * 1000)

            guard let httpResponse = response as? HTTPURLResponse else {
                cloudflareTestResult = .failure("Invalid response received from Cloudflare.")
                return
            }

            switch httpResponse.statusCode {
            case 200...299:
                cloudflareTestResult = .success("Cloudflare Workers AI reachable & authenticated (\(elapsedMs)ms).")
            case 401:
                cloudflareTestResult = .failure("HTTP 401 Unauthorized: Invalid Cloudflare API token.")
            case 403:
                cloudflareTestResult = .failure("HTTP 403 Forbidden: API token lacks Workers AI permissions for account \(effectiveAccountID).")
            case 404:
                cloudflareTestResult = .failure("HTTP 404 Not Found: Check Account ID (\(effectiveAccountID)).")
            default:
                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let errors = json["errors"] as? [[String: Any]],
                   let firstError = errors.first?["message"] as? String {
                    cloudflareTestResult = .failure("Cloudflare error (HTTP \(httpResponse.statusCode)): \(firstError)")
                } else {
                    let preview = String(data: data.prefix(100), encoding: .utf8) ?? ""
                    cloudflareTestResult = .warning("HTTP \(httpResponse.statusCode): \(preview)")
                }
            }
        } catch is CancellationError {
            // Task cancelled
        } catch {
            cloudflareTestResult = .failure("Connection failed: \(error.localizedDescription)")
        }
    }

    private func testLocalRunnerConnection() async {
        guard !isTestingLocalRunner else { return }
        isTestingLocalRunner = true
        localRunnerTestResult = nil
        defer { isTestingLocalRunner = false }

        let rawURL = localRunnerURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "http://127.0.0.1:8000"
            : localRunnerURL.trimmingCharacters(in: .whitespacesAndNewlines)

        guard let targetURL = URL(string: rawURL) else {
            localRunnerTestResult = .failure("Invalid URL format.")
            return
        }

        let probeURL = targetURL.path.hasSuffix("/v1/evaluate")
            ? targetURL
            : targetURL.appendingPathComponent("v1/evaluate")

        var request = URLRequest(url: probeURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 5.0

        let probePayload = SystemOneRequest(
            state: "Ping",
            model: "clef-flash",
            questions: ["ping": .noul(instructions: "Ping test")]
        )

        do {
            request.httpBody = try JSONEncoder().encode(probePayload)
            let startTime = CFAbsoluteTimeGetCurrent()
            let (data, response) = try await URLSession.shared.data(for: request)
            let elapsedMs = Int((CFAbsoluteTimeGetCurrent() - startTime) * 1000)

            guard let httpResponse = response as? HTTPURLResponse else {
                localRunnerTestResult = .failure("Invalid response from local runner.")
                return
            }

            if (200...299).contains(httpResponse.statusCode) {
                localRunnerTestResult = .success("Local runner reachable (\(elapsedMs)ms).")
            } else {
                let preview = String(data: data.prefix(80), encoding: .utf8) ?? ""
                localRunnerTestResult = .warning("HTTP \(httpResponse.statusCode): \(preview)")
            }
        } catch {
            localRunnerTestResult = .failure("Local runner unreachable at \(rawURL): \(error.localizedDescription)")
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

// MARK: - Connection Test Status Types

private enum ConnectionTestResult: Sendable, Equatable {
    case success(String)
    case warning(String)
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
            case .warning(let msg):
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text(msg)
                    .font(.caption)
                    .foregroundStyle(.orange)
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
