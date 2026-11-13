import SwiftUI
import FoundationModels
import SystemOneCore
import JevFoundationModels
import LayaFoundationModels
import ClefFoundationModels
import OpenAIFoundationModels
import GeminiFoundationModels

// MARK: - Choosable Triage Category

enum SecureTriageCategory: String, Choosable, CaseIterable {
    case dataBreach = "Data Breach / Security"
    case systemOutage = "System Outage"
    case billingDispute = "Billing Dispute"
    case featureRequest = "Feature Request"

    var optionIdentifier: String {
        rawValue
    }

    var optionDescription: String? {
        switch self {
        case .dataBreach:
            return "Potential security leaks, credential exposure, or unauthorized access"
        case .systemOutage:
            return "API degradation, database failure, or service downtime"
        case .billingDispute:
            return "Payment issues, chargebacks, or credit card failures"
        case .featureRequest:
            return "Product improvement ideas and general user feedback"
        }
    }
}

// MARK: - Proxied System One Provider Selection (Pattern A & Pattern B)

enum SecureProxyProvider: String, CaseIterable, Identifiable, Sendable {
    case jev = "jev"
    case laya = "laya"
    case clef = "clef"
    case openai = "openai"
    case gemini = "gemini"
    case gateway = "gateway"

    var id: String { rawValue }

    var displayTitle: String {
        switch self {
        case .jev:
            return "Jev (Pattern A — JevLanguageModel)"
        case .laya:
            return "Laya Serve (Pattern A — LayaLanguageModel)"
        case .clef:
            return "Cloudflare Clef (Pattern A — ClefLanguageModel)"
        case .openai:
            return "OpenAI gpt-6-luna (Pattern A — OpenAILanguageModel)"
        case .gemini:
            return "Google Gemini (Pattern A — GeminiLanguageModel)"
        case .gateway:
            return "Agnostic Gateway (Pattern B — SystemOneLanguageModel)"
        }
    }

    var shortName: String {
        switch self {
        case .jev: return "Jev"
        case .laya: return "Laya"
        case .clef: return "Clef"
        case .openai: return "OpenAI"
        case .gemini: return "Gemini"
        case .gateway: return "Gateway (DEFAULT_PROVIDER)"
        }
    }

    var proxyPathSuffix: String {
        switch self {
        case .jev, .laya, .clef, .openai, .gemini:
            return "/\(rawValue)"
        case .gateway:
            return ""
        }
    }

    var requiredServerSecretSummary: String {
        switch self {
        case .jev:
            return "TYPESAFE_API_KEY"
        case .laya:
            return "LAYA_UPSTREAM_URL (+ optional LAYA_API_KEY)"
        case .clef:
            return "CLOUDFLARE_ACCOUNT_ID + CLOUDFLARE_API_TOKEN (or CLEF_UPSTREAM_URL)"
        case .openai:
            return "OPENAI_API_KEY"
        case .gemini:
            return "GEMINI_API_KEY"
        case .gateway:
            return "DEFAULT_PROVIDER secret on proxy (defaults to TYPESAFE_API_KEY)"
        }
    }

    func makeSession(
        proxyEndpoint: URL,
        credential: ProxyCredential,
        urlSession: URLSession = .shared
    ) -> LanguageModelSession {
        switch self {
        case .jev:
            return LanguageModelSession(
                model: JevLanguageModel(
                    proxyEndpoint: proxyEndpoint,
                    credential: credential,
                    session: urlSession
                )
            )
        case .laya:
            return LanguageModelSession(
                model: LayaLanguageModel(
                    proxyEndpoint: proxyEndpoint,
                    credential: credential,
                    session: urlSession
                )
            )
        case .clef:
            return LanguageModelSession(
                model: ClefLanguageModel(
                    proxyEndpoint: proxyEndpoint,
                    credential: credential,
                    session: urlSession
                )
            )
        case .openai:
            return LanguageModelSession(
                model: OpenAILanguageModel(
                    proxyEndpoint: proxyEndpoint,
                    credential: credential,
                    session: urlSession
                )
            )
        case .gemini:
            return LanguageModelSession(
                model: GeminiLanguageModel(
                    proxyEndpoint: proxyEndpoint,
                    credential: credential,
                    session: urlSession
                )
            )
        case .gateway:
            return LanguageModelSession(
                model: SystemOneLanguageModel(
                    proxyEndpoint: proxyEndpoint,
                    credential: credential,
                    session: urlSession
                )
            )
        }
    }
}

// MARK: - Proxy Gateway Environment

enum ProxyEnvironment: String, CaseIterable, Identifiable, Sendable {
    case localEmulator = "Local Emulator (Port 5001)"
    case production = "Production Cloud Functions"

    var id: String { rawValue }

    func endpoint(projectID: String, provider: SecureProxyProvider = .jev) throws -> URL {
        let trimmed = projectID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              trimmed.range(of: #"^[a-zA-Z0-9][a-zA-Z0-9-]*$"#, options: .regularExpression) != nil else {
            throw SystemOneError.networkError("Invalid Firebase Project ID '\(projectID)'.")
        }
        var components = URLComponents()
        switch self {
        case .localEmulator:
            components.scheme = "http"
            components.host = "127.0.0.1"
            components.port = 5001
            components.path = "/\(trimmed)/us-central1/systemone\(provider.proxyPathSuffix)"
        case .production:
            components.scheme = "https"
            components.host = "us-central1-\(trimmed).cloudfunctions.net"
            components.path = "/systemone\(provider.proxyPathSuffix)"
        }
        guard let url = components.url else {
            throw SystemOneError.networkError("Could not construct proxy URL for project '\(trimmed)'.")
        }
        try ProxyEndpointValidator.validate(url)
        return url
    }
}

// MARK: - Observable View State

@Observable
@MainActor
final class SecureTriageViewModel {
    var projectID: String = "my-secure-project"
    var environment: ProxyEnvironment = .localEmulator
    var provider: SecureProxyProvider = .jev
    var customAppCheckToken: String = "debug-app-check-token-local"
    var inputText: String = "Customer database dump leaked on public forum with session tokens."
    var isEvaluating: Bool = false
    var resultText: String?
    var errorMessage: String?
    var lastServerDurationMs: Double?
    var lastRoundTripDurationMs: Double?

    var resolvedEndpointPreview: String {
        (try? environment.endpoint(projectID: projectID, provider: provider).absoluteString)
            ?? "Invalid Firebase Project ID"
    }

    func evaluate() async {
        isEvaluating = true
        errorMessage = nil
        resultText = nil
        lastServerDurationMs = nil
        lastRoundTripDurationMs = nil

        let selectedProvider = provider
        do {
            let session = try buildSession(for: selectedProvider)
            let startTime = CFAbsoluteTimeGetCurrent()
            let choice = try await session.choice(
                "Classify the incoming alert to determine response protocol",
                from: SecureTriageCategory.self,
                state: inputText
            )
            let roundTripMs = (CFAbsoluteTimeGetCurrent() - startTime) * 1000.0

            let (serverMs, transportMs) = Self.extractTimingMetadata(from: session.transcript)
            self.lastServerDurationMs = serverMs
            self.lastRoundTripDurationMs = transportMs ?? roundTripMs

            resultText = """
            Category: \(choice.value.rawValue)
            Confidence: \(String(format: "%.1f%%", choice.confidence * 100))
            Provider: \(selectedProvider.displayTitle)
            Gateway: Verified X-Firebase-AppCheck
            """
        } catch {
            errorMessage = error.localizedDescription
        }

        isEvaluating = false
    }

    private func buildSession(for provider: SecureProxyProvider) throws -> LanguageModelSession {
        let token = customAppCheckToken
        let endpoint = try environment.endpoint(projectID: projectID, provider: provider)
        return provider.makeSession(
            proxyEndpoint: endpoint,
            credential: .appCheck { token }
        )
    }

    private static func extractTimingMetadata(from transcript: Transcript) -> (serverMs: Double?, transportMs: Double?) {
        for entry in transcript.reversed() {
            if case .response(let response) = entry {
                let serverMs = parseDouble(from: response.metadata["serverDurationMs"])
                let transportMs = parseDouble(from: response.metadata["transportDurationMs"])
                return (serverMs, transportMs)
            }
        }
        return (nil, nil)
    }

    private static func parseDouble(from content: GeneratedContent?) -> Double? {
        guard let content else { return nil }
        if let str = try? content.value(String.self), let val = Double(str) {
            return val
        }
        return Double(content.jsonString)
    }
}

// MARK: - Native SwiftUI View

public struct SecureTriageView: View {
    @State private var viewModel = SecureTriageViewModel()

    public init() {}

    public var body: some View {
        NavigationStack {
            Form {
                Section("Proxy Gateway Configuration") {
                    Picker("Target Environment", selection: $viewModel.environment) {
                        ForEach(ProxyEnvironment.allCases) { env in
                            Text(env.rawValue).tag(env)
                        }
                    }

                    Picker("Proxied Provider", selection: $viewModel.provider) {
                        ForEach(SecureProxyProvider.allCases) { prov in
                            Text(prov.displayTitle).tag(prov)
                        }
                    }

                    TextField("Firebase Project ID", text: $viewModel.projectID)

                    TextField("App Check Token / Debug Secret", text: $viewModel.customAppCheckToken)
                        .font(.caption)

                    LabeledContent("Proxy Route") {
                        Text(viewModel.resolvedEndpointPreview)
                            .font(.caption2.monospaced())
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.trailing)
                    }

                    LabeledContent("Server Secret") {
                        Text(viewModel.provider.requiredServerSecretSummary)
                            .font(.caption2.monospaced())
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Incident Report") {
                    TextEditor(text: $viewModel.inputText)
                        .frame(minHeight: 80)

                    Button {
                        Task {
                            await viewModel.evaluate()
                        }
                    } label: {
                        HStack {
                            if viewModel.isEvaluating {
                                ProgressView()
                                    .controlSize(.small)
                            }
                            Text(
                                viewModel.isEvaluating
                                    ? "Verifying & Evaluating..."
                                    : "Evaluate via \(viewModel.provider.shortName) Proxy"
                            )
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(viewModel.isEvaluating || viewModel.inputText.isEmpty)
                }

                if let result = viewModel.resultText {
                    Section("Verified Triage Result") {
                        Text(result)
                            .font(.system(.body, design: .monospaced))
                            .foregroundStyle(.green)

                        if let serverMs = viewModel.lastServerDurationMs {
                            LabeledContent(
                                "Upstream \(viewModel.provider.shortName) Latency",
                                value: String(format: "%.1f ms", serverMs)
                            )
                            .font(.caption.monospaced())
                        }

                        if let roundTripMs = viewModel.lastRoundTripDurationMs {
                            LabeledContent(
                                "Proxy Round-Trip",
                                value: String(format: "%.1f ms", roundTripMs)
                            )
                            .font(.caption.monospaced())
                        }
                    }
                }

                if let error = viewModel.errorMessage {
                    Section("Gateway Error") {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Secure App Check Triage")
        }
        .frame(minWidth: 500, minHeight: 540)
    }
}
