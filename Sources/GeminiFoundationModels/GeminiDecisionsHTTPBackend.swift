import Foundation
import SystemOneCore

/// An HTTP backend bridging System One requests to the Google Gemini Decisions API (`gemini-decision-1`).
///
/// See tech-notes/0018-gemini-decisions-api-architecture.md
public struct GeminiDecisionsHTTPBackend: SystemOneBackend, Sendable, Hashable {
    public let endpoint: GeminiDecisionsEndpoint
    public let apiKey: String?
    public let session: URLSession
    public let timeoutInterval: TimeInterval
    public let retryPolicy: RetryPolicy

    public init(
        endpoint: GeminiDecisionsEndpoint = .hosted(),
        apiKey: String? = nil,
        session: URLSession = .shared,
        timeoutInterval: TimeInterval = 30,
        retryPolicy: RetryPolicy = .default
    ) {
        self.endpoint = endpoint
        self.apiKey = apiKey
        self.session = session
        self.timeoutInterval = timeoutInterval
        self.retryPolicy = retryPolicy
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
        self.session = session
        self.timeoutInterval = timeoutInterval
        self.retryPolicy = retryPolicy
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

    private func resolveAPIKey() -> String? {
        if let explicit = apiKey {
            let trimmed = explicit.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        let env = ProcessInfo.processInfo.environment
        if let geminiKey = env["GEMINI_API_KEY"] {
            let trimmed = geminiKey.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                return trimmed
            }
        }
        if let googleKey = env["GOOGLE_API_KEY"] {
            let trimmed = googleKey.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                return trimmed
            }
        }
        return nil
    }

    private func evaluateWithTiming(
        request: GeminiDecisionsRequest
    ) async throws -> (response: GeminiDecisionsResponse, transportDurationMs: Double, serverDurationMs: Double?) {
        guard let resolvedKey = resolveAPIKey() else {
            throw SystemOneError.missingAPIKey
        }

        var attempts = 0
        let maxAttempts = retryPolicy.maxAttempts

        while true {
            attempts += 1
            do {
                return try await performSingleEvaluation(request: request, apiKey: resolvedKey)
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

                let delay: Duration
                if statusCode == 429, let retryAfterDelay = retryPolicy.retryAfter(from: resError.httpResponse) {
                    delay = retryAfterDelay
                } else {
                    delay = retryPolicy.backoff(afterAttempt: attempts)
                }

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
                case .apiError(let statusCode, _):
                    if retryPolicy.retryableStatuses.contains(statusCode), attempts < maxAttempts {
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
        request: GeminiDecisionsRequest,
        apiKey: String
    ) async throws -> (response: GeminiDecisionsResponse, transportDurationMs: Double, serverDurationMs: Double?) {
        var urlRequest = URLRequest(url: endpoint.url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Accept")
        urlRequest.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
        urlRequest.timeoutInterval = timeoutInterval

        if let clientReqID = endpoint.clientRequestID, !clientReqID.isEmpty {
            urlRequest.setValue(clientReqID, forHTTPHeaderField: "X-Client-Request-Id")
        }

        do {
            urlRequest.httpBody = try JSONEncoder().encode(request)
        } catch {
            throw SystemOneError.decodingError("Failed to serialize GeminiDecisionsRequest: \(error.localizedDescription)")
        }

        let networkStartTime = CFAbsoluteTimeGetCurrent()
        let data: Data
        let urlResponse: URLResponse
        do {
            (data, urlResponse) = try await session.data(for: urlRequest)
        } catch is CancellationError {
            throw CancellationError()
        } catch let urlError as URLError where urlError.code == .cancelled {
            throw CancellationError()
        } catch {
            if (error as? URLError)?.code == .cancelled || error is CancellationError {
                throw CancellationError()
            }
            throw SystemOneError.networkError(error.localizedDescription)
        }

        let transportDuration = (CFAbsoluteTimeGetCurrent() - networkStartTime) * 1000.0

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
