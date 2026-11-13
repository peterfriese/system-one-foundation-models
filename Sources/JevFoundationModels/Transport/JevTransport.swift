import Foundation

/// A transport abstraction responsible for delivering requests to the TypeSafe AI Jev decision API.
public protocol JevTransport: Sendable {
    /// Dispatches a `JevRequest` and returns the deserialized `JevResponse`.
    func send(request: JevRequest, apiKey: String?, endpoint: URL) async throws -> JevResponse
}

// See tech-notes/0006-http-resilience-and-confidence-routing.md

/// The default HTTP transport using Apple's native `URLSession` with automated retry resilience.
public struct URLSessionTransport: JevTransport, Hashable, Sendable {
    public let session: URLSession
    public let timeoutInterval: TimeInterval
    public var retryPolicy: RetryPolicy

    // Test seams for deterministic backoff and clock simulation
    let sleep: @Sendable (Duration) async throws -> Void
    let randomness: @Sendable () -> Double
    let now: @Sendable () -> Date

    public init(
        session: URLSession = .shared,
        timeoutInterval: TimeInterval = 30,
        retryPolicy: RetryPolicy = .default
    ) {
        self.session = session
        self.timeoutInterval = timeoutInterval
        self.retryPolicy = retryPolicy
        self.sleep = { try await Task.sleep(for: $0) }
        self.randomness = { Double.random(in: 0...1) }
        self.now = { Date() }
    }

    init(
        session: URLSession = .shared,
        timeoutInterval: TimeInterval = 30,
        retryPolicy: RetryPolicy = .default,
        sleep: @escaping @Sendable (Duration) async throws -> Void,
        randomness: @escaping @Sendable () -> Double,
        now: @escaping @Sendable () -> Date
    ) {
        self.session = session
        self.timeoutInterval = timeoutInterval
        self.retryPolicy = retryPolicy
        self.sleep = sleep
        self.randomness = randomness
        self.now = now
    }

    public static func == (lhs: URLSessionTransport, rhs: URLSessionTransport) -> Bool {
        lhs.session == rhs.session &&
        lhs.timeoutInterval == rhs.timeoutInterval &&
        lhs.retryPolicy == rhs.retryPolicy
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(session)
        hasher.combine(timeoutInterval)
        hasher.combine(retryPolicy)
    }

    public func send(request: JevRequest, apiKey: String?, endpoint: URL) async throws -> JevResponse {
        guard let apiKey, !apiKey.isEmpty else {
            throw JevError.missingAPIKey
        }

        let requestData: Data
        do {
            requestData = try JSONEncoder().encode(request)
        } catch {
            throw JevError.decodingError("Failed to encode JevRequest: \(error.localizedDescription)")
        }
        var urlRequest = URLRequest(url: endpoint)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        urlRequest.timeoutInterval = timeoutInterval
        urlRequest.httpBody = requestData

        let clock = ContinuousClock()
        var attempt = 1
        while true {
            try Task.checkCancellation()

            let attemptStart = clock.now
            let data: Data
            let response: URLResponse
            do {
                (data, response) = try await session.data(for: urlRequest)
            } catch is CancellationError {
                // Cooperative cancellation must never be wrapped in a custom error
                throw CancellationError()
            } catch let urlError as URLError where urlError.code == .cancelled {
                throw CancellationError()
            } catch {
                if attempt < retryPolicy.maxAttempts {
                    let delay = retryPolicy.backoff(afterAttempt: attempt, randomness: randomness())
                    try await sleep(delay)
                    attempt += 1
                    continue
                }
                throw JevError.networkError(error.localizedDescription)
            }

            let elapsed = clock.now - attemptStart
            let transportMs = Double(elapsed.components.seconds) * 1000.0
                + Double(elapsed.components.attoseconds) / 1_000_000_000_000_000.0

            guard let httpResponse = response as? HTTPURLResponse else {
                throw JevError.networkError("Invalid HTTP response received from server.")
            }

            if (200...299).contains(httpResponse.statusCode) {
                do {
                    var decoded = try JSONDecoder().decode(JevResponse.self, from: data)
                    decoded.transportDurationMs = transportMs
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

    private func failure(for response: HTTPURLResponse, data: Data) -> JevError {
        let body = String(data: data, encoding: .utf8) ?? "Unknown server error"
        if response.statusCode == 429,
           let retryAfter = retryPolicy.retryAfter(from: response, now: now()) {
            return .apiError(statusCode: response.statusCode, message: "\(body) (retry after \(retryAfter))")
        }
        return .apiError(statusCode: response.statusCode, message: body)
    }
}

/// A mock transport enabling offline, deterministic automated testing without live API credentials.
public struct MockJevTransport: JevTransport, Hashable, Sendable {
    public let id: UUID
    private let handler: @Sendable (JevRequest) async throws -> JevResponse

    public init(
        id: UUID = UUID(),
        handler: @escaping @Sendable (JevRequest) async throws -> JevResponse
    ) {
        self.id = id
        self.handler = handler
    }

    public static func == (lhs: MockJevTransport, rhs: MockJevTransport) -> Bool {
        lhs.id == rhs.id
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    public func send(request: JevRequest, apiKey: String?, endpoint: URL) async throws -> JevResponse {
        try await handler(request)
    }
}

/// A type-erased `JevTransport` that conforms to `Hashable` and `Sendable`.
public struct AnyJevTransport: JevTransport, Hashable, Sendable {
    public let id: UUID
    private let _send: @Sendable (JevRequest, String?, URL) async throws -> JevResponse

    public init(_ transport: some JevTransport, id: UUID = UUID()) {
        self.id = id
        self._send = { try await transport.send(request: $0, apiKey: $1, endpoint: $2) }
    }

    public init(id: UUID = UUID(), handler: @escaping @Sendable (JevRequest) async throws -> JevResponse) {
        self.id = id
        self._send = { req, _, _ in try await handler(req) }
    }

    public static func == (lhs: AnyJevTransport, rhs: AnyJevTransport) -> Bool {
        lhs.id == rhs.id
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    public func send(request: JevRequest, apiKey: String?, endpoint: URL) async throws -> JevResponse {
        try await _send(request, apiKey, endpoint)
    }
}
