import Foundation
import FoundationModels
@preconcurrency import CoreML
import FactoryKit
import SystemOneCore
import JevFoundationModels
import ClefFoundationModels
import OpenAIFoundationModels
import GeminiFoundationModels

/// Health status of a decision model inference backend.
public enum BackendHealthStatus: Sendable, Equatable {
    case healthy(latencyMs: Double)
    case unreachable(reason: String, guidance: String)
    case checking

    public var isHealthy: Bool {
        if case .healthy = self { return true }
        return false
    }

    public var isPreparing: Bool {
        if case .unreachable(let reason, _) = self {
            return reason.localizedCaseInsensitiveContains("Preparing") || reason.localizedCaseInsensitiveContains("Downloading")
        }
        return false
    }

    public var guidance: String? {
        if case .unreachable(_, let guidance) = self { return guidance }
        return nil
    }

    public var reason: String? {
        if case .unreachable(let reason, _) = self { return reason }
        return nil
    }

    public var latencyMs: Double? {
        if case .healthy(let ms) = self { return ms }
        return nil
    }
}

/// Typed error thrown when inference is attempted on an unreachable or misconfigured backend.
public struct BackendUnreachableError: Error, LocalizedError, Sendable, Equatable {
    public let backend: TriageBackend
    public let reason: String
    public let guidance: String

    public var isPreparing: Bool {
        reason.localizedCaseInsensitiveContains("Preparing") || reason.localizedCaseInsensitiveContains("Downloading")
    }

    public init(backend: TriageBackend, reason: String, guidance: String) {
        self.backend = backend
        self.reason = reason
        self.guidance = guidance
    }

    public var errorDescription: String? {
        "\(backend.displayName) Unreachable: \(reason). \(guidance)"
    }

    public var recoverySuggestion: String? {
        guidance
    }

    public static var modelNotAvailable: BackendUnreachableError {
        BackendUnreachableError(
            backend: .onDeviceCoreML,
            reason: "Core ML Model Load Failure: .safetensors files cannot be executed directly by Core ML",
            guidance: ".safetensors weights must be converted and compiled to Core ML format using python3 Tools/CoreMLConverter/convert_laya_to_coreml.py (coremltools or xcrun coremlc) before they can run on-device. Please open Settings (⌘,) and re-import the compiled Core ML model."
        )
    }

    public static func modelNotAvailable(reason: String, guidance: String) -> BackendUnreachableError {
        BackendUnreachableError(backend: .onDeviceCoreML, reason: reason, guidance: guidance)
    }
}

/// Service protocol for pre-flight backend health checks and diagnostic probing.
public protocol BackendHealthProbeServiceProtocol: Sendable {
    func probe(backend: TriageBackend) async -> BackendHealthStatus
    func probeAll() async -> [TriageBackend: BackendHealthStatus]
}

/// Production implementation of `BackendHealthProbeServiceProtocol`.
/// Executes real network probes, system capability queries, and on-device filesystem checks.
public final class BackendHealthProbeService: BackendHealthProbeServiceProtocol, Sendable {
    private let customConfigStore: BackendConfigurationStore?
    private let customCoreMLManager: CoreMLModelManager?

    private var configStore: BackendConfigurationStore {
        customConfigStore ?? Container.shared.backendConfigurationStore()
    }

    private var coreMLManager: CoreMLModelManager {
        customCoreMLManager ?? Container.shared.coreMLModelManager()
    }

    private let session: URLSession

    public init(session: URLSession? = nil, configStore: BackendConfigurationStore? = nil, coreMLManager: CoreMLModelManager? = nil) {
        self.customConfigStore = configStore
        self.customCoreMLManager = coreMLManager
        if let session {
            self.session = session
        } else {
            let config = URLSessionConfiguration.ephemeral
            config.timeoutIntervalForRequest = 10.0
            config.timeoutIntervalForResource = 10.0
            config.waitsForConnectivity = false
            self.session = URLSession(configuration: config)
        }
    }

    public func probe(backend: TriageBackend) async -> BackendHealthStatus {
        switch backend {
        case .localServe:
            return await probeLocalServe()
        case .cloudAPI:
            return await probeJevCloud()
        case .hostedVPC:
            return await probeHostedVPC()
        case .onDeviceCoreML:
            return await probeCoreML()
        case .cloudflareClef:
            return await probeCloudflareClef()
        case .openaiDecisions:
            return await probeOpenAIDecisions()
        case .geminiDecisions:
            return await probeGeminiDecisions()
        case .reverseProxy:
            return await probeReverseProxy()
        case .generativeBaseline:
            return await probeBaseline()
        }
    }

    public func probeAll() async -> [TriageBackend: BackendHealthStatus] {
        var results: [TriageBackend: BackendHealthStatus] = [:]
        await withTaskGroup(of: (TriageBackend, BackendHealthStatus).self) { group in
            for backend in TriageBackend.allCases {
                group.addTask {
                    let status = await self.probe(backend: backend)
                    return (backend, status)
                }
            }
            for await (backend, status) in group {
                results[backend] = status
            }
        }
        return results
    }

    // MARK: - Private Probes

    private func evaluateHTTPStatus(_ statusCode: Int, latencyMs: Double) -> BackendHealthStatus {
        if (200...299).contains(statusCode) {
            return .healthy(latencyMs: latencyMs)
        } else if statusCode == 401 {
            return .unreachable(
                reason: "Invalid API Key (HTTP 401)",
                guidance: "Check your API Key in Settings."
            )
        } else if statusCode == 403 {
            return .unreachable(
                reason: "Authentication Failed (HTTP 403)",
                guidance: "Check your API Key or Token in Settings."
            )
        } else if statusCode == 404 {
            return .unreachable(
                reason: "Endpoint Not Found (HTTP 404)",
                guidance: "Verify the endpoint URL path in Settings."
            )
        } else if statusCode == 422 {
            return .unreachable(
                reason: "Schema Error (HTTP 422)",
                guidance: "The request schema or question payload was rejected by the server."
            )
        } else if statusCode == 429 {
            return .unreachable(
                reason: "Rate Limited (HTTP 429)",
                guidance: "Endpoint is rate limited. Wait or check quota."
            )
        } else {
            return .unreachable(
                reason: "Unexpected HTTP \(statusCode)",
                guidance: "Check server status."
            )
        }
    }

    private func probeLocalServe() async -> BackendHealthStatus {
        let endpoint = BackendConfigurationStore.normalizeSystemOneEndpoint(
            configStore.localServeURL,
            defaultURL: BackendConfigurationStore.defaultLocalServeURL
        )

        // Try health endpoint first, fallback to base URL
        let probeURL: URL
        if endpoint.path.hasSuffix("/systemone") {
            var comp = URLComponents(url: endpoint, resolvingAgainstBaseURL: false)
            comp?.path = "/health"
            probeURL = comp?.url ?? endpoint.deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("health")
        } else if endpoint.lastPathComponent == "v1" {
            probeURL = endpoint.deletingLastPathComponent().appendingPathComponent("health")
        } else {
            probeURL = endpoint.appendingPathComponent("health")
        }

        let clock = ContinuousClock()
        let start = clock.now

        var request = URLRequest(url: probeURL)
        request.httpMethod = "GET"
        request.timeoutInterval = 2.5

        do {
            let (_, response) = try await session.data(for: request)
            let elapsed = start.duration(to: clock.now).asMilliseconds
            guard let http = response as? HTTPURLResponse else {
                return .unreachable(
                    reason: "Invalid response from laya-serve",
                    guidance: "Check server status."
                )
            }
            return evaluateHTTPStatus(http.statusCode, latencyMs: elapsed)
        } catch {
            // Also try hitting base URL directly before reporting unreachable
            var baseReq = URLRequest(url: endpoint)
            baseReq.httpMethod = "GET"
            baseReq.timeoutInterval = 1.5
            if let (_, response) = try? await session.data(for: baseReq),
               let http = response as? HTTPURLResponse {
                let elapsed = start.duration(to: clock.now).asMilliseconds
                return evaluateHTTPStatus(http.statusCode, latencyMs: elapsed)
            }

            let host = endpoint.host ?? "127.0.0.1"
            let port = endpoint.port.map { ":\($0)" } ?? ":8000"
            return .unreachable(
                reason: "laya-serve is not running on \(host)\(port)",
                guidance: "Open Terminal and run 'laya serve' or start your local container."
            )
        }
    }

    private func probeJevCloud() async -> BackendHealthStatus {
        let key = configStore.typesafeApiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else {
            return .unreachable(
                reason: "Missing TypeSafe API Key",
                guidance: "Open Settings (⌘,) and paste your TYPESAFE_API_KEY."
            )
        }

        let base = configStore.jevCloudURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: base) else {
            return .unreachable(
                reason: "Invalid Jev Cloud endpoint",
                guidance: "Open Settings (⌘,) and verify your Jev Cloud URL."
            )
        }

        let clock = ContinuousClock()
        let start = clock.now

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 10.0

        do {
            let probeRequest = JevRequest(
                state: "health_check",
                model: "jev-latest",
                questions: [
                    "ping": .noul(instructions: "Is this endpoint responsive?")
                ]
            )
            request.httpBody = try JSONEncoder().encode(probeRequest)

            let (data, response) = try await session.data(for: request)
            let elapsed = start.duration(to: clock.now).asMilliseconds
            guard let http = response as? HTTPURLResponse else {
                return .unreachable(
                    reason: "Unexpected response from Jev Cloud",
                    guidance: "Check your internet connection or service status."
                )
            }

            if (200...299).contains(http.statusCode) {
                return .healthy(latencyMs: elapsed)
            }

            let errorBody = String(data: data, encoding: .utf8) ?? ""
            let serverMessage = parseServerErrorMessage(from: data) ?? {
                let trimmed = errorBody.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed.isEmpty ? nil : trimmed
            }()

            if let serverMessage, !serverMessage.isEmpty {
                let guidance: String
                if http.statusCode == 401 || http.statusCode == 403 {
                    guidance = "Check your API Key in Settings."
                } else if http.statusCode == 422 {
                    guidance = "The request schema or question payload was rejected by the server."
                } else if http.statusCode == 429 {
                    guidance = "Endpoint is rate limited. Wait or check quota."
                } else {
                    guidance = "Check server status."
                }
                return .unreachable(
                    reason: "Jev Error (HTTP \(http.statusCode)): \(serverMessage)",
                    guidance: guidance
                )
            }

            return evaluateHTTPStatus(http.statusCode, latencyMs: elapsed)
        } catch {
            print("⚠️ [probeJevCloud] Failed with error: \(error)")
            return .unreachable(
                reason: "Cannot connect to Jev Cloud API: \(error.localizedDescription)",
                guidance: "Check your internet connection or cloud service status."
            )
        }
    }

    private func probeCloudflareClef() async -> BackendHealthStatus {
        let accountId = configStore.cloudflareAccountId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !accountId.isEmpty else {
            return .unreachable(
                reason: "Missing Cloudflare Account ID",
                guidance: "Open Settings (⌘,) and paste your Cloudflare Account ID."
            )
        }

        let token = configStore.cloudflareApiToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else {
            return .unreachable(
                reason: "Missing Cloudflare API Token",
                guidance: "Open Settings (⌘,) and paste your Cloudflare API Token."
            )
        }

        let endpoint = ClefEndpoint.workersAI(accountID: accountId, model: .clefFlash)
        let clock = ContinuousClock()
        let start = clock.now

        var request = URLRequest(url: endpoint.url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 10.0

        do {
            let probeRequest = SystemOneRequest(
                state: "health_check",
                model: "clef-flash",
                questions: [
                    "ping": .noul(instructions: "Is this endpoint responsive?")
                ]
            )
            request.httpBody = try JSONEncoder().encode(probeRequest)

            let (data, response) = try await session.data(for: request)
            let elapsed = start.duration(to: clock.now).asMilliseconds
            guard let http = response as? HTTPURLResponse else {
                return .unreachable(
                    reason: "Unexpected response from Cloudflare Clef",
                    guidance: "Check your internet connection or service status."
                )
            }

            if (200...299).contains(http.statusCode) {
                if let envelope = try? JSONDecoder().decode(CloudflareProbeEnvelope.self, from: data) {
                    if envelope.success == false {
                        let errorMessage = envelope.errors?.first?.message ?? parseServerErrorMessage(from: data) ?? "Cloudflare API request failed"
                        return .unreachable(
                            reason: "\(errorMessage) (HTTP \(http.statusCode))",
                            guidance: "Verify your Cloudflare Workers AI configuration."
                        )
                    }
                }
                return .healthy(latencyMs: elapsed)
            }

            let serverMessage = parseServerErrorMessage(from: data)
            if let serverMessage, !serverMessage.isEmpty {
                let guidance: String
                if http.statusCode == 401 || http.statusCode == 403 {
                    guidance = "Check your Cloudflare API Token and Account ID in Settings."
                } else {
                    guidance = "Verify your Cloudflare Workers AI configuration."
                }
                return .unreachable(
                    reason: "\(serverMessage) (HTTP \(http.statusCode))",
                    guidance: guidance
                )
            }

            return evaluateHTTPStatus(http.statusCode, latencyMs: elapsed)
        } catch {
            print("⚠️ [probeCloudflareClef] Failed with error: \(error)")
            return .unreachable(
                reason: "Cannot connect to Cloudflare Workers AI: \(error.localizedDescription)",
                guidance: "Check your internet connection and Cloudflare credentials."
            )
        }
    }

    private func probeOpenAIDecisions() async -> BackendHealthStatus {
        var key = configStore.openaiAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if key.hasPrefix("Bearer ") {
            key = String(key.dropFirst("Bearer ".count)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard !key.isEmpty else {
            return .unreachable(
                reason: "Missing OpenAI API Key",
                guidance: "Open Settings (⌘,) and paste your OPENAI_API_KEY."
            )
        }

        let clock = ContinuousClock()
        let start = clock.now

        var request = URLRequest(url: OpenAIDecisionsEndpoint.defaultURL)
        request.httpMethod = "POST"
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let org = configStore.openaiOrganization.trimmingCharacters(in: .whitespacesAndNewlines)
        if !org.isEmpty {
            request.setValue(org, forHTTPHeaderField: "OpenAI-Organization")
        }
        let proj = configStore.openaiProject.trimmingCharacters(in: .whitespacesAndNewlines)
        if !proj.isEmpty {
            request.setValue(proj, forHTTPHeaderField: "OpenAI-Project")
        }
        request.timeoutInterval = 10.0

        do {
            let probeRequest = OpenAIDecisionsRequest(
                model: OpenAIDecisionsEndpoint.defaultModel,
                input: .text("Health check probe"),
                questions: [
                    OpenAIDecisionsQuestion(
                        type: "predicate",
                        name: "ping",
                        instructions: "Is this endpoint responsive?"
                    )
                ]
            )
            request.httpBody = try JSONEncoder().encode(probeRequest)

            let (data, response) = try await session.data(for: request)
            let elapsed = start.duration(to: clock.now).asMilliseconds
            guard let http = response as? HTTPURLResponse else {
                return .unreachable(
                    reason: "Unexpected response from OpenAI Decisions API",
                    guidance: "Check your internet connection or service status."
                )
            }

            if (200...299).contains(http.statusCode) {
                return .healthy(latencyMs: elapsed)
            }

            let serverMessage = parseServerErrorMessage(from: data)
            if let serverMessage, !serverMessage.isEmpty {
                let guidance: String
                if http.statusCode == 401 || http.statusCode == 403 {
                    guidance = "Check your OpenAI API Key in Settings."
                } else if http.statusCode == 429 {
                    guidance = "OpenAI Decisions API rate limited or quota exceeded."
                } else {
                    guidance = "Check OpenAI service status."
                }
                return .unreachable(
                    reason: "OpenAI Error (HTTP \(http.statusCode)): \(serverMessage)",
                    guidance: guidance
                )
            }

            return evaluateHTTPStatus(http.statusCode, latencyMs: elapsed)
        } catch {
            print("⚠️ [probeOpenAIDecisions] Failed with error: \(error)")
            return .unreachable(
                reason: "Cannot connect to OpenAI Decisions API: \(error.localizedDescription)",
                guidance: "Check your internet connection and OpenAI API key."
            )
        }
    }

    private func probeGeminiDecisions() async -> BackendHealthStatus {
        var key = configStore.geminiAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if key.hasPrefix("Bearer ") {
            key = String(key.dropFirst("Bearer ".count)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard !key.isEmpty else {
            return .unreachable(
                reason: "Missing Gemini API Key",
                guidance: "Open Settings (⌘,) and paste your GEMINI_API_KEY."
            )
        }

        let clock = ContinuousClock()
        let start = clock.now

        var request = URLRequest(url: GeminiDecisionsEndpoint.defaultURL)
        request.httpMethod = "POST"
        request.setValue(key, forHTTPHeaderField: "x-goog-api-key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 10.0

        do {
            let probeRequest = GeminiDecisionsRequest(
                model: GeminiDecisionsEndpoint.defaultModel,
                input: .text("Health check ping."),
                questions: [
                    "ok": GeminiDecisionsQuestion(
                        type: "noul",
                        instructions: "Return true."
                    )
                ]
            )
            request.httpBody = try JSONEncoder().encode(probeRequest)

            let (data, response) = try await session.data(for: request)
            let elapsed = start.duration(to: clock.now).asMilliseconds
            guard let http = response as? HTTPURLResponse else {
                return .unreachable(
                    reason: "Unexpected response from Google Gemini Decisions API",
                    guidance: "Check your internet connection or service status."
                )
            }

            if (200...299).contains(http.statusCode) {
                return .healthy(latencyMs: elapsed)
            }

            let serverMessage = parseServerErrorMessage(from: data)
            if let serverMessage, !serverMessage.isEmpty {
                let guidance: String
                if http.statusCode == 401 || http.statusCode == 403 {
                    guidance = "Open Settings (⌘,) and paste your GEMINI_API_KEY."
                } else if http.statusCode == 429 {
                    guidance = "Google Gemini Decisions API rate limited or quota exceeded."
                } else {
                    guidance = "Check Google Gemini service status."
                }
                return .unreachable(
                    reason: "Gemini Error (HTTP \(http.statusCode)): \(serverMessage)",
                    guidance: guidance
                )
            }

            if http.statusCode == 401 || http.statusCode == 403 {
                return .unreachable(
                    reason: http.statusCode == 401 ? "Invalid API Key (HTTP 401)" : "Authentication Failed (HTTP 403)",
                    guidance: "Open Settings (⌘,) and paste your GEMINI_API_KEY."
                )
            }

            return evaluateHTTPStatus(http.statusCode, latencyMs: elapsed)
        } catch is CancellationError {
            return .unreachable(
                reason: "Health check cancelled",
                guidance: "Retry the connection check when ready."
            )
        } catch let urlError as URLError {
            if urlError.code == .cancelled {
                return .unreachable(
                    reason: "Health check cancelled",
                    guidance: "Retry the connection check when ready."
                )
            }
            let connectivityCodes: Set<URLError.Code> = [
                .notConnectedToInternet,
                .networkConnectionLost,
                .cannotFindHost,
                .cannotConnectToHost,
                .timedOut,
                .dnsLookupFailed
            ]
            if connectivityCodes.contains(urlError.code) {
                return .unreachable(
                    reason: "Cannot connect to Google Gemini Decisions API: \(urlError.localizedDescription)",
                    guidance: "Check your internet connection or Google Gemini service status."
                )
            }
            print("⚠️ [probeGeminiDecisions] Failed with URLError: \(urlError)")
            return .unreachable(
                reason: "Cannot connect to Google Gemini Decisions API: \(urlError.localizedDescription)",
                guidance: "Check your internet connection and verify your GEMINI_API_KEY in Settings (⌘,)."
            )
        } catch {
            print("⚠️ [probeGeminiDecisions] Failed with error: \(error)")
            return .unreachable(
                reason: "Cannot connect to Google Gemini Decisions API: \(error.localizedDescription)",
                guidance: "Check your internet connection and verify your GEMINI_API_KEY in Settings (⌘,)."
            )
        }
    }

    private func probeReverseProxy() async -> BackendHealthStatus {
        let rawURL = configStore.reverseProxyURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !rawURL.isEmpty else {
            return .unreachable(
                reason: "Missing Proxy Endpoint URL",
                guidance: "Open Settings (⌘,) and configure your HTTPS Proxy Endpoint URL (or set SYSTEM_ONE_PROXY_URL)."
            )
        }

        guard let proxyURL = URL(string: rawURL) else {
            return .unreachable(
                reason: "Invalid Proxy Endpoint URL",
                guidance: "Open Settings (⌘,) and provide a valid HTTPS URL (or http://127.0.0.1 for local gateways)."
            )
        }

        do {
            try ProxyEndpointValidator.validate(proxyURL)
        } catch let sysError as SystemOneError {
            return .unreachable(
                reason: sysError.localizedDescription,
                guidance: "Use https:// for remote proxy gateways (http:// is permitted only for localhost / 127.0.0.1) and omit embedded URL credentials."
            )
        } catch {
            return .unreachable(
                reason: "Invalid Proxy Endpoint URL: \(error.localizedDescription)",
                guidance: "Open Settings (⌘,) and verify your Proxy Endpoint URL."
            )
        }

        let clock = ContinuousClock()
        let start = clock.now

        var request = URLRequest(url: proxyURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 10.0

        do {
            let credential = configStore.makeProxyCredential()
            try await credential.apply(to: &request)

            let probeRequest = SystemOneRequest(
                state: "health_check",
                model: "systemone-default",
                questions: [
                    "ping": .noul(instructions: "Is this endpoint responsive?")
                ]
            )
            request.httpBody = try JSONEncoder().encode(probeRequest)

            let (data, response) = try await session.data(for: request)
            let elapsed = start.duration(to: clock.now).asMilliseconds
            guard let http = response as? HTTPURLResponse else {
                return .unreachable(
                    reason: "Unexpected response from Authenticated Proxy",
                    guidance: "Check your internet connection or proxy gateway status."
                )
            }

            if (200...299).contains(http.statusCode) {
                return .healthy(latencyMs: elapsed)
            }

            let serverMessage = parseServerErrorMessage(from: data)
            if let serverMessage, !serverMessage.isEmpty {
                let guidance: String
                if http.statusCode == 401 || http.statusCode == 403 {
                    guidance = "Verify your Proxy Token and Credential Mode in Settings (⌘,)."
                } else if http.statusCode == 429 {
                    guidance = "Authenticated Proxy gateway rate limited or quota exceeded."
                } else {
                    guidance = "Verify your proxy gateway deployment and upstream provider routing."
                }
                return .unreachable(
                    reason: "Proxy Error (HTTP \(http.statusCode)): \(serverMessage)",
                    guidance: guidance
                )
            }

            if http.statusCode == 401 || http.statusCode == 403 {
                return .unreachable(
                    reason: http.statusCode == 401 ? "Proxy Authentication Failed (HTTP 401)" : "Proxy Forbidden (HTTP 403)",
                    guidance: "Verify your Proxy Token and Credential Mode in Settings (⌘,)."
                )
            }

            return evaluateHTTPStatus(http.statusCode, latencyMs: elapsed)
        } catch is CancellationError {
            return .unreachable(
                reason: "Health check cancelled",
                guidance: "Retry the connection check when ready."
            )
        } catch let urlError as URLError where urlError.code == .cancelled {
            return .unreachable(
                reason: "Health check cancelled",
                guidance: "Retry the connection check when ready."
            )
        } catch let sysError as SystemOneError {
            return .unreachable(
                reason: sysError.localizedDescription,
                guidance: "Verify your Proxy Endpoint URL and Proxy Token in Settings (⌘,)."
            )
        } catch {
            print("⚠️ [probeReverseProxy] Failed with error: \(error)")
            return .unreachable(
                reason: "Cannot connect to Authenticated Proxy: \(error.localizedDescription)",
                guidance: "Check your network connection and verify your Proxy Endpoint URL in Settings (⌘,)."
            )
        }
    }

    private func parseServerErrorMessage(from data: Data) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        if let errors = json["errors"] as? [[String: Any]],
           let first = errors.first,
           let message = first["message"] as? String, !message.isEmpty {
            return message
        }
        if let detail = json["detail"] as? [String: Any],
           let message = detail["message"] as? String, !message.isEmpty {
            return message
        }
        if let detailStr = json["detail"] as? String, !detailStr.isEmpty {
            return detailStr
        }
        if let error = json["error"] as? [String: Any],
           let message = error["message"] as? String, !message.isEmpty {
            return message
        }
        if let errorStr = json["error"] as? String, !errorStr.isEmpty {
            return errorStr
        }
        if let message = json["message"] as? String, !message.isEmpty {
            return message
        }
        return nil
    }

    private func probeHostedVPC() async -> BackendHealthStatus {
        let endpoint = BackendConfigurationStore.normalizeSystemOneEndpoint(
            configStore.hostedVpcURL,
            defaultURL: BackendConfigurationStore.defaultHostedVpcURL
        )

        let token = configStore.hostedVpcToken.trimmingCharacters(in: .whitespacesAndNewlines)

        let clock = ContinuousClock()
        let start = clock.now

        var request = URLRequest(url: endpoint)
        request.httpMethod = "GET"
        if !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        request.timeoutInterval = 3.0

        do {
            let (_, response) = try await session.data(for: request)
            let elapsed = start.duration(to: clock.now).asMilliseconds
            guard let http = response as? HTTPURLResponse else {
                return .unreachable(
                    reason: "Invalid response from Hosted VPC",
                    guidance: "Check server status."
                )
            }
            return evaluateHTTPStatus(http.statusCode, latencyMs: elapsed)
        } catch {
            return .unreachable(
                reason: "Cannot connect to Hosted VPC at \(endpoint.host ?? endpoint.absoluteString)",
                guidance: "Verify your enterprise VPN / VPC connection and token."
            )
        }
    }

    private func probeCoreML() async -> BackendHealthStatus {
        guard let modelURL = coreMLManager.resolvedModelURL else {
            return .unreachable(
                reason: "Model weights not installed",
                guidance: "Open Settings (⌘,) and download the Core ML model."
            )
        }

        let clock = ContinuousClock()
        let start = clock.now

        do {
            let config = MLModelConfiguration()
            config.computeUnits = .all
            _ = try MLModel(contentsOf: modelURL, configuration: config)
            let elapsed = start.duration(to: clock.now).asMilliseconds
            return .healthy(latencyMs: elapsed)
        } catch {
            return .unreachable(
                reason: "Failed to load Core ML model: \(error.localizedDescription)",
                guidance: "Open Settings (⌘,) and re-download the Core ML model."
            )
        }
    }

    private func probeBaseline() async -> BackendHealthStatus {
        switch SystemLanguageModel.default.availability {
        case .available:
            return .healthy(latencyMs: 1.0)
        case .unavailable(let reason):
            switch reason {
            case .modelNotReady:
                return .unreachable(
                    reason: "Apple Intelligence Model Preparing (Downloading Assets)",
                    guidance: "Your Mac is eligible and Apple Intelligence is enabled, but the on-device system model assets are still downloading or preparing in macOS. Keep your Mac connected to power and Wi-Fi, and check System Settings > Apple Intelligence & Siri."
                )
            case .appleIntelligenceNotEnabled:
                return .unreachable(
                    reason: "Apple Intelligence is Turned Off",
                    guidance: "Turn on Apple Intelligence in macOS System Settings > Apple Intelligence & Siri."
                )
            case .deviceNotEligible:
                return .unreachable(
                    reason: "Device Not Eligible for Apple Intelligence",
                    guidance: "Apple Intelligence requires an Apple Silicon Mac (M1 or later)."
                )
            @unknown default:
                return .unreachable(
                    reason: "Apple Intelligence Unavailable",
                    guidance: "Apple Intelligence is currently unavailable on this system."
                )
            }
        @unknown default:
            return .unreachable(reason: "Apple Intelligence Unavailable", guidance: "Check System Settings.")
        }
    }
}

// MARK: - Cloudflare Probe Envelope

private struct CloudflareProbeEnvelope: Decodable, Sendable {
    let success: Bool?
    let errors: [CloudflareProbeError]?
}

private struct CloudflareProbeError: Decodable, Sendable {
    let code: Int?
    let message: String?
}
