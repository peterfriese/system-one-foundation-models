import Foundation
import SystemOneCore
#if canImport(FirebaseAppCheck)
import FirebaseAppCheck
#endif
#if canImport(JevFoundationModels)
import JevFoundationModels
#endif

/// The token acquisition strategy for Firebase App Check attestation.
public enum FirebaseAppCheckTokenStrategy: Sendable, Hashable {
    /// Uses cached in-memory tokens (< 1 ms lookup).
    /// Recommended for interactive UI, low-latency loops, and continuous decisions.
    case cached

    /// Acquires a one-time consumable token with server-side replay protection (~40–120 ms token exchange).
    /// Recommended for sensitive operations, billing-sensitive decisions, or high-security actions.
    case singleUse
}

extension ProxyCredential {
    /// Authenticates requests to a Firebase App Check reverse proxy across all 5 networked
    /// System One providers (`JevLanguageModel`, `LayaLanguageModel`, `ClefLanguageModel`,
    /// `OpenAILanguageModel`, `GeminiLanguageModel`) and `SystemOneLanguageModel` without
    /// importing `JevFoundationModels`.
    ///
    /// Example:
    /// ```swift
    /// let model = GeminiLanguageModel(
    ///     proxyEndpoint: URL(string: "https://us-central1-my-app.cloudfunctions.net/systemone/gemini")!,
    ///     credential: .firebaseAppCheck(strategy: .singleUse)
    /// )
    /// ```
    public static func firebaseAppCheck(
        strategy: FirebaseAppCheckTokenStrategy = .cached,
        headerName: String = "X-Firebase-AppCheck"
    ) -> ProxyCredential {
        .appCheck(headerName: headerName) {
            try await FirebaseAppCheckTransport.acquireAppCheckToken(strategy: strategy)
        }
    }
}

/// A transport that delivers System One requests to a secure Firebase Cloud Function proxy
/// authenticated with Apple App Attest via Firebase App Check.
///
/// Supports both Pattern B (`SystemOneBackend` / `SystemOneLanguageModel`) universally via
/// `SystemOneCore` and legacy `JevTransport` conformance when `JevFoundationModels` is linked.
/// For any individual provider (`Gemini`, `OpenAI`, `Clef`, `Laya`, `Jev`), prefer passing
/// `credential: .firebaseAppCheck(...)` directly to `<Provider>LanguageModel(proxyEndpoint:credential:)`.
///
/// See `docs/mobile-security.md` and `tech-notes/0004-secure-mobile-transport-appcheck.md`
/// for complete setup instructions.
public struct FirebaseAppCheckTransport: SystemOneBackend, Sendable {
    /// Backward-compatible alias for `FirebaseAppCheckTokenStrategy`.
    public typealias TokenStrategy = FirebaseAppCheckTokenStrategy

    /// An explicit proxy endpoint URL.
    public let proxyEndpoint: URL?
    public let session: URLSession
    public let tokenStrategy: TokenStrategy
    public let timeoutInterval: TimeInterval

    public init(
        proxyEndpoint: URL? = nil,
        session: URLSession = .shared,
        tokenStrategy: TokenStrategy = .cached,
        timeoutInterval: TimeInterval = 30
    ) {
        self.proxyEndpoint = proxyEndpoint
        self.session = session
        self.tokenStrategy = tokenStrategy
        self.timeoutInterval = timeoutInterval
    }

    public func evaluate(request: SystemOneRequest) async throws -> SystemOneResponse {
        try Task.checkCancellation()

        guard let targetURL = proxyEndpoint else {
            throw SystemOneError.networkError(
                "FirebaseAppCheckTransport requires an explicit proxyEndpoint pointing to your authenticated Cloud Function reverse proxy."
            )
        }
        try ProxyEndpointValidator.validate(targetURL)

        let tokenString = try await Self.acquireAppCheckToken(strategy: tokenStrategy)

        var urlRequest = URLRequest(url: targetURL)
        urlRequest.httpMethod = "POST"
        urlRequest.timeoutInterval = timeoutInterval
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if !tokenString.isEmpty {
            urlRequest.setValue(tokenString, forHTTPHeaderField: "X-Firebase-AppCheck")
        }

        do {
            urlRequest.httpBody = try JSONEncoder().encode(request)
        } catch {
            throw SystemOneError.decodingError("Failed to encode SystemOneRequest: \(error.localizedDescription)")
        }

        let clock = ContinuousClock()
        let start = clock.now
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: urlRequest)
        } catch is CancellationError {
            throw CancellationError()
        } catch let urlError as URLError where urlError.code == .cancelled {
            throw CancellationError()
        } catch {
            throw SystemOneError.networkError(error.localizedDescription)
        }

        let elapsed = clock.now - start
        let transportMs = Double(elapsed.components.seconds) * 1000.0
            + Double(elapsed.components.attoseconds) / 1_000_000_000_000_000.0

        guard let httpResponse = response as? HTTPURLResponse else {
            throw SystemOneError.networkError("Invalid HTTP response received from proxy.")
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? "Unknown server error"
            if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
                throw SystemOneError.authenticationFailed(body)
            }
            if httpResponse.statusCode == 422, let refusal = Self.decodeSafetyRefusal(from: data) {
                throw refusal
            }
            throw SystemOneError.apiError(statusCode: httpResponse.statusCode, message: body)
        }

        do {
            var decoded = try JSONDecoder().decode(SystemOneResponse.self, from: data)
            decoded.transportDurationMs = transportMs
            decoded.serverDurationMs = decoded.serverDurationMs ?? Self.parseServerTimingDuration(from: httpResponse)
            return decoded
        } catch {
            throw SystemOneError.decodingError("Failed to decode SystemOneResponse from proxy: \(error.localizedDescription)")
        }
    }

    fileprivate static func acquireAppCheckToken(strategy: FirebaseAppCheckTokenStrategy) async throws -> String {
        try Task.checkCancellation()
        #if canImport(FirebaseAppCheck)
        do {
            switch strategy {
            case .cached:
                let token = try await AppCheck.appCheck().token(forcingRefresh: false)
                return token.token
            case .singleUse:
                let token = try await AppCheck.appCheck().limitedUseToken()
                return token.token
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw SystemOneError.authenticationFailed(
                "Failed to acquire Firebase App Check token: \(error.localizedDescription)"
            )
        }
        #else
        throw SystemOneError.authenticationFailed(
            "FirebaseAppCheck is not linked in this application target."
        )
        #endif
    }

    private struct ProxySafetyRefusalEnvelope: Decodable {
        struct ErrorDetail: Decodable {
            let type: String?
            let question: String?
            let message: String?
        }
        let error: ErrorDetail
    }

    private static func decodeSafetyRefusal(from data: Data) -> SystemOneError? {
        guard let envelope = try? JSONDecoder().decode(ProxySafetyRefusalEnvelope.self, from: data),
              envelope.error.type == "safety_refusal" else {
            return nil
        }
        let reason = envelope.error.message.flatMap { $0.isEmpty ? nil : $0 }
            ?? "Content blocked by safety policy"
        let questionName = envelope.error.question.flatMap { $0.isEmpty ? nil : $0 }
            ?? "unknown"
        return .safetyRefusal(reason: reason, questionName: questionName)
    }

    private static func parseServerTimingDuration(from httpResponse: HTTPURLResponse) -> Double? {
        for header in ["x-goog-processing-ms", "openai-processing-ms", "x-envoy-upstream-service-time", "x-inference-time-ms"] {
            if let value = httpResponse.value(forHTTPHeaderField: header),
               let ms = Double(value) {
                return ms
            }
        }
        if let serverTiming = httpResponse.value(forHTTPHeaderField: "server-timing") {
            for entry in serverTiming.components(separatedBy: ",") {
                for param in entry.components(separatedBy: ";").dropFirst() {
                    let kv = param.trimmingCharacters(in: .whitespaces).components(separatedBy: "=")
                    if kv.count == 2 && kv[0] == "dur", let durVal = Double(kv[1]) {
                        return durVal
                    }
                }
            }
        }
        return nil
    }
}

#if canImport(JevFoundationModels)
extension FirebaseAppCheckTransport: JevTransport {
    public func send(
        request: JevRequest,
        apiKey: String?,
        endpoint: URL
    ) async throws -> JevResponse {
        try await evaluate(request: request)
    }
}
#endif
