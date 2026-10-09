import Foundation

/// An HTTP transport that directs requests to a secure proxy endpoint (e.g. Firebase Cloud Functions with App Check)
/// rather than dispatching directly to the TypeSafe AI upstream API.
///
/// `ProxyTransport` allows native mobile clients to authenticate against a custom backend gateway without
/// bundling upstream TypeSafe API keys on-device.
///
/// See `tech-notes/0010-proxy-transport-and-dynamic-attestation.md`.
public struct ProxyTransport: JevTransport, Sendable {

    /// Authentication mechanisms supported by the proxy gateway.
    public enum Credential: Sendable {
        /// Sets `Authorization: Bearer <token>` using the dynamically resolved token.
        case bearer(@Sendable () async throws -> String)

        /// Sets a custom HTTP header with an optional prefix (e.g. `X-Firebase-AppCheck: <token>`).
        case header(name: String, prefix: String? = nil, provider: @Sendable () async throws -> String)

        /// Applies arbitrary modifications to the outbound `URLRequest` before dispatch.
        case custom(@Sendable (inout URLRequest) async throws -> Void)
    }

    /// The target proxy URL to which all requests are directed.
    public let proxyEndpoint: URL

    /// The authentication credentials applied to requests sent to the proxy.
    public let credential: Credential

    /// The underlying `URLSession` used for HTTP networking.
    public let session: URLSession

    /// Per-attempt network timeout interval in seconds.
    public let timeoutInterval: TimeInterval

    /// Retry and backoff resilience configuration.
    public var retryPolicy: RetryPolicy

    // Test seams for deterministic backoff and clock simulation
    let sleep: @Sendable (Duration) async throws -> Void
    let randomness: @Sendable () -> Double
    let now: @Sendable () -> Date

    public init(
        proxyEndpoint: URL,
        credential: Credential,
        session: URLSession = .shared,
        timeoutInterval: TimeInterval = 30,
        retryPolicy: RetryPolicy = .default
    ) {
        self.proxyEndpoint = proxyEndpoint
        self.credential = credential
        self.session = session
        self.timeoutInterval = timeoutInterval
        self.retryPolicy = retryPolicy
        self.sleep = { try await Task.sleep(for: $0) }
        self.randomness = { Double.random(in: 0...1) }
        self.now = { Date() }
    }

    init(
        proxyEndpoint: URL,
        credential: Credential,
        session: URLSession = .shared,
        timeoutInterval: TimeInterval = 30,
        retryPolicy: RetryPolicy = .default,
        sleep: @escaping @Sendable (Duration) async throws -> Void,
        randomness: @escaping @Sendable () -> Double,
        now: @escaping @Sendable () -> Date
    ) {
        self.proxyEndpoint = proxyEndpoint
        self.credential = credential
        self.session = session
        self.timeoutInterval = timeoutInterval
        self.retryPolicy = retryPolicy
        self.sleep = sleep
        self.randomness = randomness
        self.now = now
    }

    public func send(request: JevRequest, apiKey: String?, endpoint: URL) async throws -> JevResponse {
        try validateProxyEndpointSecurity()

        let requestData: Data
        do {
            requestData = try JSONEncoder().encode(request)
        } catch {
            throw JevError.decodingError("Failed to encode JevRequest: \(error.localizedDescription)")
        }

        var attempt = 1
        while true {
            var urlRequest = URLRequest(url: proxyEndpoint)
            urlRequest.httpMethod = "POST"
            urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
            urlRequest.timeoutInterval = timeoutInterval
            urlRequest.httpBody = requestData

            // Apply configured credentials for each attempt to support rotating/refreshed tokens
            try await applyCredential(to: &urlRequest)

            let data: Data
            let response: URLResponse
            do {
                (data, response) = try await session.data(for: urlRequest)
            } catch is CancellationError {
                throw CancellationError()
            } catch let urlError as URLError where urlError.code == .cancelled {
                throw CancellationError()
            } catch {
                throw JevError.networkError(error.localizedDescription)
            }

            guard let httpResponse = response as? HTTPURLResponse else {
                throw JevError.networkError("Invalid HTTP response received from proxy.")
            }

            if (200...299).contains(httpResponse.statusCode) {
                do {
                    var decoded = try JSONDecoder().decode(JevResponse.self, from: data)
                    if let serviceTimeHeader = httpResponse.value(forHTTPHeaderField: "x-envoy-upstream-service-time"),
                       let serviceTimeMs = Double(serviceTimeHeader) {
                        decoded.serverDurationMs = serviceTimeMs
                    }
                    return decoded
                } catch {
                    throw JevError.decodingError("Failed to decode Jev response: \(error.localizedDescription)")
                }
            }

            let isLastAttempt = attempt >= retryPolicy.maxAttempts
            guard retryPolicy.retryableStatuses.contains(httpResponse.statusCode), !isLastAttempt else {
                throw failure(for: httpResponse, data: data)
            }

            let delay = retryPolicy.retryAfter(from: httpResponse, now: now())
                ?? retryPolicy.backoff(afterAttempt: attempt, randomness: randomness())
            try await sleep(delay)
            attempt += 1
        }
    }

    private func validateProxyEndpointSecurity() throws {
        let scheme = proxyEndpoint.scheme?.lowercased()
        if scheme == "https" {
            return
        }
        if scheme == "http" {
            let host = proxyEndpoint.host?.lowercased()
            if host == "localhost" || host == "127.0.0.1" || host == "::1" || host == "[::1]" {
                return
            }
        }
        throw JevError.networkError("Insecure proxy endpoint: HTTPS is required for remote proxy connections.")
    }

    private func applyCredential(to request: inout URLRequest) async throws {
        switch credential {
        case .bearer(let provider):
            let token = try await provider()
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        case .header(let name, let prefix, let provider):
            let token = try await provider()
            let value = prefix.map { "\($0) \(token)" } ?? token
            request.setValue(value, forHTTPHeaderField: name)

        case .custom(let modifier):
            try await modifier(&request)
        }
    }

    private func failure(for response: HTTPURLResponse, data: Data) -> JevError {
        let body = String(data: data, encoding: .utf8) ?? "Unknown server error"
        if response.statusCode == 429,
           let retryAfter = retryPolicy.retryAfter(from: response, now: now()) {
            return .apiError(statusCode: response.statusCode, message: "\(body) (retry after \(retryAfter))")
        }
        return .apiError(statusCode: response.statusCode, message: body)
    }
}
