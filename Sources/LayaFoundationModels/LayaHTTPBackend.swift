import Foundation
import SystemOneCore

/// An HTTP backend bridging System One requests to self-hosted or remote Laya servers (`laya-serve`).
///
/// See `tech-notes/0007-pluggable-system-one-backends-and-laya-serve.md`.
public struct LayaHTTPBackend: SystemOneBackend, Hashable, Sendable {
    public let endpoint: LayaEndpoint
    public let apiKey: String?
    public let proxyCredential: ProxyCredential?
    public let session: URLSession
    public let timeoutInterval: TimeInterval
    public let retryPolicy: RetryPolicy

    public init(
        endpoint: LayaEndpoint = .localDefault,
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
    }

    public init(
        proxyEndpoint: URL,
        credential: ProxyCredential,
        session: URLSession = .shared,
        timeoutInterval: TimeInterval = 30,
        retryPolicy: RetryPolicy = .default
    ) {
        self.endpoint = .custom(proxyEndpoint)
        self.apiKey = nil
        self.proxyCredential = credential
        self.session = session
        self.timeoutInterval = timeoutInterval
        self.retryPolicy = retryPolicy
    }

    private struct HTTPResponseError: Error {
        let httpResponse: HTTPURLResponse
        let data: Data
    }

    public func evaluate(request: SystemOneRequest) async throws -> SystemOneResponse {
        if proxyCredential != nil {
            try ProxyEndpointValidator.validate(endpoint.url)
        }

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

    private func performSingleEvaluation(requestData: Data) async throws -> SystemOneResponse {
        var urlRequest = URLRequest(url: endpoint.url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")

        // Bearer auth is optional: laya-serve without LAYA_API_KEY requires no authorization header
        if proxyCredential == nil, let key = apiKey, !key.isEmpty {
            urlRequest.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
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
            throw SystemOneError.networkError("Invalid HTTP response received from server.")
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            throw HTTPResponseError(httpResponse: httpResponse, data: data)
        }

        do {
            var decoded = try JSONDecoder().decode(SystemOneResponse.self, from: data)
            decoded.transportDurationMs = transportDuration

            // Check for server-supplied timing headers:
            // 1. x-envoy-upstream-service-time (standard Envoy/Traefik/Gateway header)
            // 2. server-timing (RFC 7668)
            // 3. x-inference-time / x-process-time
            if let serviceTimeHeader = httpResponse.value(forHTTPHeaderField: "x-envoy-upstream-service-time"),
               let serviceTimeMs = Double(serviceTimeHeader) {
                decoded.serverDurationMs = serviceTimeMs
            } else if let serverTimingHeader = httpResponse.value(forHTTPHeaderField: "server-timing"),
                      let dur = parseServerTimingDuration(serverTimingHeader) {
                decoded.serverDurationMs = dur
            } else if let inferenceHeader = httpResponse.value(forHTTPHeaderField: "x-inference-time-ms") ?? httpResponse.value(forHTTPHeaderField: "x-process-time"),
                      let inferenceMs = Double(inferenceHeader) {
                decoded.serverDurationMs = inferenceMs
            } else {
                // If the server omits internal timing headers (standard local laya-serve),
                // transportDuration represents the total HTTP socket transit and inference time.
                decoded.serverDurationMs = transportDuration
            }

            return decoded
        } catch {
            throw SystemOneError.decodingError("Failed to decode Laya response: \(error.localizedDescription)")
        }
    }

    private func parseServerTimingDuration(_ header: String) -> Double? {
        // e.g., "app;dur=42.5" or "inference;dur=18.2"
        for entry in header.components(separatedBy: ",") {
            let parts = entry.components(separatedBy: ";")
            for param in parts.dropFirst() {
                let kv = param.trimmingCharacters(in: .whitespaces).components(separatedBy: "=")
                if kv.count == 2 && kv[0] == "dur" {
                    return Double(kv[1])
                }
            }
        }
        return nil
    }
}
