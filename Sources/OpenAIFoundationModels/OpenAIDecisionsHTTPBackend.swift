import Foundation
import SystemOneCore

/// An HTTP backend bridging System One requests to the OpenAI Decisions API (`gpt-6-luna`).
public struct OpenAIDecisionsHTTPBackend: SystemOneBackend, Sendable, Hashable {
    public let endpoint: OpenAIDecisionsEndpoint
    public let apiKey: String?
    public let proxyCredential: ProxyCredential?
    public let session: URLSession
    public let timeoutInterval: TimeInterval
    public let retryPolicy: RetryPolicy
    internal var environmentOverride: [String: String]? = nil

    public init(
        endpoint: OpenAIDecisionsEndpoint = .hosted(),
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
        endpoint: OpenAIDecisionsEndpoint = .hosted(),
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
        organization: String? = nil,
        project: String? = nil,
        clientRequestID: String? = nil,
        session: URLSession = .shared,
        timeoutInterval: TimeInterval = 30,
        retryPolicy: RetryPolicy = .default
    ) {
        self.endpoint = .custom(
            endpointURL,
            organization: organization,
            project: project,
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
        model: String = OpenAIDecisionsEndpoint.defaultModel,
        organization: String? = nil,
        project: String? = nil,
        clientRequestID: String? = nil,
        session: URLSession = .shared,
        timeoutInterval: TimeInterval = 30,
        retryPolicy: RetryPolicy = .default
    ) {
        self.endpoint = .custom(
            proxyEndpoint,
            model: model,
            organization: organization,
            project: project,
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
        let openAIRequest = try OpenAIDecisionsPayloadAdapter.adaptRequest(request)
        let (openAIResponse, transportDuration, serverDuration) = try await evaluateWithTiming(request: openAIRequest)
        return try OpenAIDecisionsPayloadAdapter.adaptResponse(
            openAIResponse,
            expectedQuestionNames: Set(request.questions.keys),
            transportDurationMs: transportDuration,
            serverDurationMs: serverDuration
        )
    }

    // MARK: - Direct Wire Evaluation

    public func evaluate(request: OpenAIDecisionsRequest) async throws -> OpenAIDecisionsResponse {
        let (response, _, _) = try await evaluateWithTiming(request: request)
        return response
    }

    // MARK: - Private Evaluation Pipeline

    private struct HTTPResponseError: Error {
        let httpResponse: HTTPURLResponse
        let data: Data
    }

    private func resolveAPIKey() -> String? {
        if proxyCredential != nil {
            return nil
        }
        if let explicit = apiKey {
            let trimmed = explicit.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                return trimmed
            }
        }
        let env = environmentOverride ?? ProcessInfo.processInfo.environment
        if let openAIKey = env["OPENAI_API_KEY"] {
            let trimmed = openAIKey.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                return trimmed
            }
        }
        return nil
    }

    private func evaluateWithTiming(
        request: OpenAIDecisionsRequest
    ) async throws -> (response: OpenAIDecisionsResponse, transportDurationMs: Double, serverDurationMs: Double?) {
        try Task.checkCancellation()
        try ProxyEndpointValidator.validate(endpoint.url)

        let resolvedKey = resolveAPIKey()
        if proxyCredential == nil && resolvedKey == nil {
            throw SystemOneError.missingAPIKey
        }

        let requestData: Data
        do {
            requestData = try JSONEncoder().encode(request)
        } catch {
            throw SystemOneError.decodingError("Failed to serialize OpenAIDecisionsRequest: \(error.localizedDescription)")
        }

        var attempts = 0
        let maxAttempts = max(1, retryPolicy.maxAttempts)

        while true {
            attempts += 1
            do {
                return try await performSingleEvaluation(requestData: requestData, apiKey: resolvedKey)
            } catch is CancellationError {
                throw CancellationError()
            } catch let resError as HTTPResponseError {
                let statusCode = resError.httpResponse.statusCode
                let errorDetail = parseErrorDetail(from: resError.data)
                let errorMessage = errorDetail?.message ?? parseErrorMessage(from: resError.data, fallbackCode: statusCode)

                // 401 Unauthorized / 403 Forbidden: fail fast with authenticationFailed
                if statusCode == 401 || statusCode == 403 {
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
        requestData: Data,
        apiKey: String?
    ) async throws -> (response: OpenAIDecisionsResponse, transportDurationMs: Double, serverDurationMs: Double?) {
        var urlRequest = URLRequest(url: endpoint.url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if proxyCredential == nil {
            if let apiKey {
                urlRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            }
            if let org = endpoint.organization, !org.isEmpty {
                urlRequest.setValue(org, forHTTPHeaderField: "OpenAI-Organization")
            }
            if let proj = endpoint.project, !proj.isEmpty {
                urlRequest.setValue(proj, forHTTPHeaderField: "OpenAI-Project")
            }
        }
        if let clientReqID = endpoint.clientRequestID, !clientReqID.isEmpty {
            urlRequest.setValue(clientReqID, forHTTPHeaderField: "X-Client-Request-Id")
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
        } catch let urlError as URLError where urlError.code == .cancelled {
            throw CancellationError()
        } catch {
            if (error as? URLError)?.code == .cancelled || error is CancellationError {
                throw CancellationError()
            }
            throw SystemOneError.networkError(error.localizedDescription)
        }

        let elapsed = networkStart.duration(to: clock.now)
        let transportDuration = Double(elapsed.components.seconds) * 1000.0 + Double(elapsed.components.attoseconds) / 1e15

        guard let httpResponse = urlResponse as? HTTPURLResponse else {
            throw SystemOneError.networkError("Invalid HTTP response received from OpenAI Decisions API.")
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            throw HTTPResponseError(httpResponse: httpResponse, data: data)
        }

        do {
            let decoded = try JSONDecoder().decode(OpenAIDecisionsResponse.self, from: data)
            let serverDuration = parseServerDuration(from: httpResponse)
            return (decoded, transportDuration, serverDuration)
        } catch {
            throw SystemOneError.decodingError("Failed to decode OpenAIDecisionsResponse: \(error.localizedDescription)")
        }
    }

    private func parseErrorDetail(from data: Data) -> OpenAIErrorEnvelope.ErrorDetail? {
        if let envelope = try? JSONDecoder().decode(OpenAIErrorEnvelope.self, from: data) {
            return envelope.error
        }
        return nil
    }

    private func isQuotaExhaustion(detail: OpenAIErrorEnvelope.ErrorDetail?, rawMessage: String) -> Bool {
        if let code = detail?.code?.lowercased(), code == "insufficient_quota" {
            return true
        }
        if let type = detail?.type?.lowercased(), type == "insufficient_quota" {
            return true
        }
        let message = (detail?.message ?? rawMessage).lowercased()
        if message.contains("insufficient_quota") || message.contains("exceeded your current quota") || message.contains("quota exceeded") || message.contains("quota exhausted") {
            return true
        }
        return false
    }

    private func parseErrorMessage(from data: Data, fallbackCode: Int) -> String {
        if let envelope = try? JSONDecoder().decode(OpenAIErrorEnvelope.self, from: data),
           let message = envelope.error?.message, !message.isEmpty {
            return message
        }
        if let rawString = String(data: data, encoding: .utf8), !rawString.isEmpty {
            return rawString
        }
        return "HTTP error \(fallbackCode)"
    }

    private func parseServerDuration(from response: HTTPURLResponse) -> Double? {
        if let msHeader = response.value(forHTTPHeaderField: "openai-processing-ms"),
           let ms = Double(msHeader) {
            return ms
        }
        return nil
    }
}
