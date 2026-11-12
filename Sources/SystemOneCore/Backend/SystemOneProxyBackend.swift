import Foundation

/// A provider-agnostic HTTP backend that dispatches canonical `SystemOneRequest` payloads
/// to a custom proxy or backend gateway (Pattern B: Provider-Agnostic Gateway).
///
/// Your backend gateway can route or fan-out the canonical `SystemOneRequest` to Jev, Laya,
/// Clef, OpenAI (`gpt-6-luna`), or Google Gemini (`gemini-decision-1`) without requiring
/// any client-side code changes.
public struct SystemOneProxyBackend: SystemOneBackend, Sendable, Hashable {
    /// The target proxy URL to which canonical `SystemOneRequest` payloads are dispatched.
    public let proxyEndpoint: URL

    /// The dynamic authentication credential applied to every outbound request attempt.
    public let credential: ProxyCredential

    /// The underlying `URLSession` used for HTTP networking.
    public let session: URLSession

    /// Per-attempt network timeout interval in seconds.
    public let timeoutInterval: TimeInterval

    /// Retry and backoff resilience configuration.
    public let retryPolicy: RetryPolicy

    public init(
        proxyEndpoint: URL,
        credential: ProxyCredential,
        session: URLSession = .shared,
        timeoutInterval: TimeInterval = 30,
        retryPolicy: RetryPolicy = .default
    ) {
        self.proxyEndpoint = proxyEndpoint
        self.credential = credential
        self.session = session
        self.timeoutInterval = timeoutInterval
        self.retryPolicy = retryPolicy
    }

    public func evaluate(request: SystemOneRequest) async throws -> SystemOneResponse {
        try ProxyEndpointValidator.validate(proxyEndpoint)

        let requestData: Data
        do {
            requestData = try JSONEncoder().encode(request)
        } catch {
            throw SystemOneError.decodingError("Failed to encode SystemOneRequest: \(error.localizedDescription)")
        }

        var attempts = 0
        let maxAttempts = max(1, retryPolicy.maxAttempts)

        while true {
            attempts += 1
            do {
                return try await performSingleEvaluation(requestData: requestData)
            } catch is CancellationError {
                throw CancellationError()
            } catch let resError as HTTPResponseError {
                let statusCode = resError.httpResponse.statusCode
                let body = String(data: resError.data, encoding: .utf8) ?? "Unknown server error"

                if statusCode == 401 || statusCode == 403 {
                    throw SystemOneError.authenticationFailed(body)
                }

                let isLastAttempt = attempts >= maxAttempts

                guard retryPolicy.retryableStatuses.contains(statusCode), !isLastAttempt else {
                    throw SystemOneError.apiError(statusCode: statusCode, message: body)
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

    private struct HTTPResponseError: Error {
        let httpResponse: HTTPURLResponse
        let data: Data
    }

    private func performSingleEvaluation(requestData: Data) async throws -> SystemOneResponse {
        var urlRequest = URLRequest(url: proxyEndpoint)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.timeoutInterval = timeoutInterval
        urlRequest.httpBody = requestData

        // Apply configured credentials on each attempt to support rotating/refreshed tokens
        do {
            try await credential.apply(to: &urlRequest)
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as SystemOneError {
            throw error
        } catch {
            throw SystemOneError.authenticationFailed("Failed to acquire proxy credential: \(error.localizedDescription)")
        }

        let clock = ContinuousClock()
        let networkStart = clock.now
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: urlRequest)
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
        let transportDuration = Double(elapsed.components.seconds) * 1000.0
            + Double(elapsed.components.attoseconds) / 1_000_000_000_000_000.0

        guard let httpResponse = response as? HTTPURLResponse else {
            throw SystemOneError.networkError("Invalid HTTP response received from proxy.")
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            throw HTTPResponseError(httpResponse: httpResponse, data: data)
        }

        do {
            var decoded = try JSONDecoder().decode(SystemOneResponse.self, from: data)
            decoded.transportDurationMs = transportDuration
            decoded.serverDurationMs = decoded.serverDurationMs
                ?? Self.parseServerTimingDuration(from: httpResponse)
                ?? transportDuration

            return decoded
        } catch {
            throw SystemOneError.decodingError("Failed to decode SystemOneResponse from proxy: \(error.localizedDescription)")
        }
    }

    private static func parseServerTimingDuration(from httpResponse: HTTPURLResponse) -> Double? {
        if let googHeader = httpResponse.value(forHTTPHeaderField: "x-goog-processing-ms"),
           let googMs = Double(googHeader) {
            return googMs
        }
        if let openAIHeader = httpResponse.value(forHTTPHeaderField: "openai-processing-ms"),
           let openAIMs = Double(openAIHeader) {
            return openAIMs
        }
        if let serviceTimeHeader = httpResponse.value(forHTTPHeaderField: "x-envoy-upstream-service-time"),
           let serviceTimeMs = Double(serviceTimeHeader) {
            return serviceTimeMs
        }
        if let serverTimingHeader = httpResponse.value(forHTTPHeaderField: "server-timing"),
           let dur = parseServerTimingDuration(serverTimingHeader) {
            return dur
        }
        if let inferenceHeader = httpResponse.value(forHTTPHeaderField: "x-inference-time-ms")
            ?? httpResponse.value(forHTTPHeaderField: "x-process-time"),
           let inferenceMs = Double(inferenceHeader) {
            return inferenceMs
        }
        return nil
    }

    private static func parseServerTimingDuration(_ header: String) -> Double? {
        for entry in header.components(separatedBy: ",") {
            let parts = entry.components(separatedBy: ";")
            for param in parts.dropFirst() {
                let kv = param.trimmingCharacters(in: .whitespaces).components(separatedBy: "=")
                if kv.count == 2 && kv[0] == "dur", let durVal = Double(kv[1]) {
                    return durVal
                }
            }
        }
        return nil
    }
}
