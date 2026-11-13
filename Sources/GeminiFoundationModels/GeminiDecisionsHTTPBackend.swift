import Foundation
import SystemOneCore

/// An HTTP backend bridging System One requests to the Google Gemini Decisions API (`gemini-decision-1`).
///
/// See tech-notes/0018-gemini-decisions-api-architecture.md
public struct GeminiDecisionsHTTPBackend: SystemOneBackend, Sendable, Hashable {
    public let endpoint: GeminiDecisionsEndpoint
    public let apiKey: String?
    public let proxyCredential: ProxyCredential?
    public let session: URLSession
    public let timeoutInterval: TimeInterval
    public let retryPolicy: RetryPolicy
    internal var environmentOverride: [String: String]? = nil

    public init(
        endpoint: GeminiDecisionsEndpoint = .hosted(),
        apiKey: String? = nil,
        proxyCredential: ProxyCredential? = nil,
        session: URLSession = .shared,
        timeoutInterval: TimeInterval = 30,
        retryPolicy: RetryPolicy = .default
    ) {
        self.endpoint = endpoint
        self.apiKey = apiKey
        self.proxyCredential = proxyCredential
        self.session = session
        self.timeoutInterval = timeoutInterval
        self.retryPolicy = retryPolicy
        self.environmentOverride = nil
    }

    internal init(
        endpoint: GeminiDecisionsEndpoint = .hosted(),
        apiKey: String? = nil,
        proxyCredential: ProxyCredential? = nil,
        session: URLSession = .shared,
        timeoutInterval: TimeInterval = 30,
        retryPolicy: RetryPolicy = .default,
        environmentOverride: [String: String]?
    ) {
        self.endpoint = endpoint
        self.apiKey = apiKey
        self.proxyCredential = proxyCredential
        self.session = session
        self.timeoutInterval = timeoutInterval
        self.retryPolicy = retryPolicy
        self.environmentOverride = environmentOverride
    }

    public init(
        endpointURL: URL,
        apiKey: String? = nil,
        clientRequestID: String? = nil,
        session: URLSession = .shared,
        timeoutInterval: TimeInterval = 30,
        retryPolicy: RetryPolicy = .default
    ) {
        self.endpoint = .custom(
            endpointURL,
            clientRequestID: clientRequestID
        )
        self.apiKey = apiKey
        self.proxyCredential = nil
        self.session = session
        self.timeoutInterval = timeoutInterval
        self.retryPolicy = retryPolicy
        self.environmentOverride = nil
    }

    public init(
        proxyEndpoint: URL,
        credential: ProxyCredential,
        model: String = GeminiDecisionsEndpoint.defaultModel,
        clientRequestID: String? = nil,
        session: URLSession = .shared,
        timeoutInterval: TimeInterval = 30,
        retryPolicy: RetryPolicy = .default
    ) {
        self.endpoint = .custom(
            proxyEndpoint,
            model: model,
            clientRequestID: clientRequestID
        )
        self.apiKey = nil
        self.proxyCredential = credential
        self.session = session
        self.timeoutInterval = timeoutInterval
        self.retryPolicy = retryPolicy
        self.environmentOverride = nil
    }

    // MARK: - SystemOneBackend Conformance

    public func evaluate(request: SystemOneRequest) async throws -> SystemOneResponse {
        let geminiRequest = try GeminiDecisionsPayloadAdapter.adaptRequest(request)
        let (geminiResponse, transportDuration, serverDuration) = try await evaluateWithTiming(request: geminiRequest)
        return try GeminiDecisionsPayloadAdapter.adaptResponse(
            geminiResponse,
            expectedQuestionNames: Set(request.questions.keys),
            transportDurationMs: transportDuration,
            serverDurationMs: serverDuration
        )
    }

    // MARK: - Direct Wire Evaluation

    public func evaluate(request: GeminiDecisionsRequest) async throws -> GeminiDecisionsResponse {
        let (response, _, _) = try await evaluateWithTiming(request: request)
        return response
    }

    // MARK: - Private Evaluation Pipeline

    private struct HTTPResponseError: Error {
        let httpResponse: HTTPURLResponse
        let data: Data
    }

    private static let maxRawErrorBodyCharacters = 512

    private static let nonRetryableURLErrorCodes: Set<URLError.Code> = [
        .badURL,
        .unsupportedURL,
        .appTransportSecurityRequiresSecureConnection,
        .serverCertificateUntrusted,
        .serverCertificateHasBadDate,
        .serverCertificateHasUnknownRoot,
        .serverCertificateNotYetValid,
        .clientCertificateRejected,
        .clientCertificateRequired
    ]

    private static func containsHeaderControlCharacters(_ value: String) -> Bool {
        value.unicodeScalars.contains { scalar in
            scalar == "\r" || scalar == "\n" || scalar.value == 0
        }
    }

    private func resolveAPIKey() throws -> String? {
        if proxyCredential != nil {
            return nil
        }

        func sanitizeKeyCandidate(_ candidate: String) throws -> String? {
            if Self.containsHeaderControlCharacters(candidate) {
                throw SystemOneError.authenticationFailed("Invalid Gemini API key: CR/LF header control characters are not permitted.")
            }
            let trimmed = candidate.trimmingCharacters(in: .whitespaces)
            return trimmed.isEmpty ? nil : trimmed
        }

        if let explicit = apiKey, let valid = try sanitizeKeyCandidate(explicit) {
            return valid
        }
        let env = environmentOverride ?? ProcessInfo.processInfo.environment
        if let geminiKey = env["GEMINI_API_KEY"], let valid = try sanitizeKeyCandidate(geminiKey) {
            return valid
        }
        if let googleKey = env["GOOGLE_API_KEY"], let valid = try sanitizeKeyCandidate(googleKey) {
            return valid
        }
        throw SystemOneError.missingAPIKey
    }

    private func resolveClientRequestID() throws -> String? {
        guard let rawID = endpoint.clientRequestID else {
            return nil
        }
        if Self.containsHeaderControlCharacters(rawID) {
            throw SystemOneError.networkError("Invalid X-Client-Request-Id: CR/LF header control characters are not permitted.")
        }
        let trimmed = rawID.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func evaluateWithTiming(
        request: GeminiDecisionsRequest
    ) async throws -> (response: GeminiDecisionsResponse, transportDurationMs: Double, serverDurationMs: Double?) {
        try Task.checkCancellation()
        let targetURL = try endpoint.validatedURL()
        let resolvedKey = try resolveAPIKey()
        let sanitizedClientRequestID = try resolveClientRequestID()

        let requestData: Data
        do {
            requestData = try JSONEncoder().encode(request)
        } catch {
            throw SystemOneError.decodingError("Failed to serialize GeminiDecisionsRequest: \(error.localizedDescription)")
        }

        var attempts = 0
        let maxAttempts = max(1, retryPolicy.maxAttempts)

        while true {
            attempts += 1
            do {
                return try await performSingleEvaluation(
                    targetURL: targetURL,
                    requestData: requestData,
                    apiKey: resolvedKey,
                    clientRequestID: sanitizedClientRequestID
                )
            } catch is CancellationError {
                throw CancellationError()
            } catch let resError as HTTPResponseError {
                let statusCode = resError.httpResponse.statusCode
                let errorDetail = parseErrorDetail(from: resError.data)
                let errorMessage = errorDetail?.message ?? parseErrorMessage(from: resError.data, fallbackCode: statusCode)

                // 401 Unauthorized / 403 Forbidden or UNAUTHENTICATED / PERMISSION_DENIED
                if statusCode == 401 || statusCode == 403 ||
                   errorDetail?.status == "UNAUTHENTICATED" || errorDetail?.status == "PERMISSION_DENIED" {
                    throw SystemOneError.authenticationFailed(errorMessage)
                }

                // 429 with quota exhaustion: fail fast without retrying
                if statusCode == 429 && isQuotaExhaustion(detail: errorDetail, rawMessage: errorMessage) {
                    throw SystemOneError.quotaExceeded(errorMessage)
                }

                let isLastAttempt = attempts >= maxAttempts

                guard retryPolicy.retryableStatuses.contains(statusCode), !isLastAttempt else {
                    throw SystemOneError.apiError(statusCode: statusCode, message: errorMessage)
                }

                let delay = retryPolicy.retryAfter(from: resError.httpResponse)
                    ?? retryPolicy.backoff(afterAttempt: attempts)

                try await Task.sleep(for: delay)
                continue
            } catch let urlError as URLError {
                if urlError.code == .cancelled {
                    throw CancellationError()
                }
                if Self.nonRetryableURLErrorCodes.contains(urlError.code) || attempts >= maxAttempts || Task.isCancelled {
                    throw SystemOneError.networkError(urlError.localizedDescription)
                }
                let delay = retryPolicy.backoff(afterAttempt: attempts)
                try await Task.sleep(for: delay)
                continue
            } catch let error as SystemOneError {
                switch error {
                case .networkError:
                    if attempts < maxAttempts && !Task.isCancelled {
                        let delay = retryPolicy.backoff(afterAttempt: attempts)
                        try await Task.sleep(for: delay)
                        continue
                    }
                    throw error
                default:
                    throw error
                }
            } catch {
                if attempts < maxAttempts && !Task.isCancelled {
                    let delay = retryPolicy.backoff(afterAttempt: attempts)
                    try await Task.sleep(for: delay)
                    continue
                }
                throw SystemOneError.networkError(error.localizedDescription)
            }
        }
    }

    private func performSingleEvaluation(
        targetURL: URL,
        requestData: Data,
        apiKey: String?,
        clientRequestID: String?
    ) async throws -> (response: GeminiDecisionsResponse, transportDurationMs: Double, serverDurationMs: Double?) {
        try Task.checkCancellation()
        var urlRequest = URLRequest(url: targetURL)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Accept")
        if proxyCredential == nil, let apiKey {
            urlRequest.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
        }
        if let clientRequestID {
            urlRequest.setValue(clientRequestID, forHTTPHeaderField: "X-Client-Request-Id")
        }
        urlRequest.timeoutInterval = timeoutInterval
        urlRequest.httpBody = requestData

        if let proxyCredential {
            do {
                try await proxyCredential.apply(to: &urlRequest)
            } catch is CancellationError {
                throw CancellationError()
            } catch let urlError as URLError where urlError.code == .cancelled {
                throw CancellationError()
            } catch {
                if Task.isCancelled {
                    throw CancellationError()
                }
                if let sysError = error as? SystemOneError {
                    throw sysError
                }
                throw SystemOneError.authenticationFailed("Failed to acquire proxy credential: \(error.localizedDescription)")
            }
        }

        let clock = ContinuousClock()
        let networkStart = clock.now
        let data: Data
        let urlResponse: URLResponse
        do {
            (data, urlResponse) = try await session.data(for: urlRequest)
        } catch is CancellationError {
            throw CancellationError()
        } catch let urlError as URLError {
            if urlError.code == .cancelled {
                throw CancellationError()
            }
            throw urlError
        } catch {
            throw SystemOneError.networkError(error.localizedDescription)
        }

        let elapsed = networkStart.duration(to: clock.now)
        let transportDuration = Double(elapsed.components.seconds) * 1000.0 + Double(elapsed.components.attoseconds) / 1e15

        guard let httpResponse = urlResponse as? HTTPURLResponse else {
            throw SystemOneError.networkError("Invalid HTTP response received from Google Gemini Decisions API.")
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            throw HTTPResponseError(httpResponse: httpResponse, data: data)
        }

        do {
            let decoded = try JSONDecoder().decode(GeminiDecisionsResponse.self, from: data)
            let serverDuration = parseServerDuration(from: httpResponse)
            return (decoded, transportDuration, serverDuration)
        } catch {
            throw SystemOneError.decodingError("Failed to decode GeminiDecisionsResponse: \(error.localizedDescription)")
        }
    }

    private func parseErrorDetail(from data: Data) -> GeminiErrorEnvelope.ErrorDetail? {
        if let envelope = try? JSONDecoder().decode(GeminiErrorEnvelope.self, from: data) {
            return envelope.error
        }
        return nil
    }

    private func isQuotaExhaustion(detail: GeminiErrorEnvelope.ErrorDetail?, rawMessage: String) -> Bool {
        let message = (detail?.message ?? rawMessage).lowercased()
        if message.contains("insufficient_quota") ||
           message.contains("exceeded your current quota") ||
           message.contains("quota exceeded") ||
           message.contains("quota exhausted") ||
           message.contains("billing") {
            return true
        }
        return false
    }

    private func parseErrorMessage(from data: Data, fallbackCode: Int) -> String {
        if let envelope = try? JSONDecoder().decode(GeminiErrorEnvelope.self, from: data),
           let message = envelope.error?.message, !message.isEmpty {
            return message
        }
        if let rawString = String(data: data, encoding: .utf8), !rawString.isEmpty {
            if rawString.count > Self.maxRawErrorBodyCharacters {
                return String(rawString.prefix(Self.maxRawErrorBodyCharacters))
            }
            return rawString
        }
        return "HTTP error \(fallbackCode)"
    }

    private func parseServerDuration(from response: HTTPURLResponse) -> Double? {
        if let msHeader = response.value(forHTTPHeaderField: "x-goog-processing-ms"),
           let ms = Double(msHeader) {
            return ms
        }
        if let serverTimingHeader = response.value(forHTTPHeaderField: "server-timing"),
           let dur = parseServerTimingDuration(serverTimingHeader) {
            return dur
        }
        if let envoyHeader = response.value(forHTTPHeaderField: "x-envoy-upstream-service-time"),
           let envoyMs = Double(envoyHeader) {
            return envoyMs
        }
        return nil
    }

    private func parseServerTimingDuration(_ header: String) -> Double? {
        var fallbackDuration: Double? = nil

        for entry in header.components(separatedBy: ",") {
            let parts = entry.components(separatedBy: ";")
            guard let metricName = parts.first?.trimmingCharacters(in: .whitespaces) else { continue }

            for param in parts.dropFirst() {
                let kv = param.trimmingCharacters(in: .whitespaces).components(separatedBy: "=")
                if kv.count == 2 && kv[0] == "dur", let durVal = Double(kv[1]) {
                    let lowerName = metricName.lowercased()
                    if lowerName == "inference" || lowerName == "gfet4t7" || lowerName == "total" {
                        return durVal
                    } else if fallbackDuration == nil {
                        fallbackDuration = durVal
                    }
                }
            }
        }
        return fallbackDuration
    }
}
