import Testing
import Foundation
import SystemOneCore
@testable import GeminiFoundationModels

// MARK: - Mock URLProtocol for GeminiDecisionsHTTPBackendTests

final class MockGeminiURLProtocol: URLProtocol {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var _responseQueue: [Result<(statusCode: Int, headers: [String: String], body: Data), any Error>] = []
    nonisolated(unsafe) private static var _recordedRequests: [URLRequest] = []

    static func reset() {
        lock.withLock {
            _responseQueue = []
            _recordedRequests = []
        }
    }

    static func enqueue(statusCode: Int, headers: [String: String] = [:], body: Data = Data()) {
        lock.withLock {
            _responseQueue.append(.success((statusCode, headers, body)))
        }
    }

    static func enqueueFailure(_ error: any Error) {
        lock.withLock {
            _responseQueue.append(.failure(error))
        }
    }

    static var recordedRequests: [URLRequest] {
        lock.withLock { _recordedRequests }
    }

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        Self.lock.withLock {
            Self._recordedRequests.append(request)
        }

        let nextItem: Result<(statusCode: Int, headers: [String: String], body: Data), any Error>? = Self.lock.withLock {
            guard !Self._responseQueue.isEmpty else { return nil }
            return Self._responseQueue.removeFirst()
        }

        guard let next = nextItem else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }

        switch next {
        case .success(let item):
            let response = HTTPURLResponse(
                url: request.url ?? GeminiDecisionsEndpoint.defaultURL,
                statusCode: item.statusCode,
                httpVersion: "HTTP/1.1",
                headerFields: item.headers
            )!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: item.body)
            client?.urlProtocolDidFinishLoading(self)

        case .failure(let error):
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

// MARK: - Test Suite

@Suite("Google Gemini Decisions HTTP Backend Tests", .serialized)
struct GeminiDecisionsHTTPBackendTests {

    private func makeSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockGeminiURLProtocol.self]
        return URLSession(configuration: config)
    }

    private let sampleResponseJSON = """
    {
      "id": "gem-dec-test-99",
      "model": "gemini-decision-1",
      "answers": {
        "isSafe": {
          "type": "noul",
          "noul": 0.98,
          "confidence": 0.98
        }
      },
      "usage": {
        "input_tokens": 42,
        "output_tokens": 0
      }
    }
    """.data(using: .utf8)!

    @Test("HTTP Backend injects x-goog-api-key and X-Client-Request-Id headers and parses server-timing")
    func testHeaderInjectionAndServerTiming() async throws {
        MockGeminiURLProtocol.reset()
        MockGeminiURLProtocol.enqueue(
            statusCode: 200,
            headers: ["server-timing": "gfet4t7; dur=21.5"],
            body: sampleResponseJSON
        )

        let endpoint = GeminiDecisionsEndpoint.hosted(
            clientRequestID: "req-gemini-123"
        )
        let backend = GeminiDecisionsHTTPBackend(
            endpoint: endpoint,
            apiKey: "AIzaSyTestKey12345",
            session: makeSession()
        )

        let request = SystemOneRequest(
            state: "Check sanity",
            model: "gemini-decision-1",
            questions: ["isSafe": .noul(instructions: "Is safe?")]
        )

        let response = try await backend.evaluate(request: request)

        #expect(response.model == "gemini-decision-1")
        #expect(response.serverDurationMs == 21.5)
        #expect(response.answers["isSafe"]?.noul == 0.98)

        let recorded = MockGeminiURLProtocol.recordedRequests
        #expect(recorded.count == 1)
        let sentRequest = recorded[0]
        #expect(sentRequest.value(forHTTPHeaderField: "x-goog-api-key") == "AIzaSyTestKey12345")
        #expect(sentRequest.value(forHTTPHeaderField: "Authorization") == nil)
        #expect(sentRequest.value(forHTTPHeaderField: "X-Client-Request-Id") == "req-gemini-123")
    }

    @Test("HTTP Backend resolves GEMINI_API_KEY and GOOGLE_API_KEY from environment and falls through whitespace apiKey")
    func testEnvironmentVariableResolution() async throws {
        let request = SystemOneRequest(
            state: "Env test",
            questions: ["isSafe": .noul(instructions: "Is safe?")]
        )

        // 1. Test GEMINI_API_KEY takes priority when apiKey is nil
        MockGeminiURLProtocol.reset()
        MockGeminiURLProtocol.enqueue(statusCode: 200, body: sampleResponseJSON)

        let backend1 = GeminiDecisionsHTTPBackend(
            endpoint: .hosted(),
            apiKey: nil,
            session: makeSession(),
            environmentOverride: [
                "GEMINI_API_KEY": "AIzaFromGeminiEnv",
                "GOOGLE_API_KEY": "AIzaFromGoogleEnv"
            ]
        )
        _ = try await backend1.evaluate(request: request)
        #expect(MockGeminiURLProtocol.recordedRequests.first?.value(forHTTPHeaderField: "x-goog-api-key") == "AIzaFromGeminiEnv")

        // 2. Test empty/whitespace-only apiKey falls through to GEMINI_API_KEY
        MockGeminiURLProtocol.reset()
        MockGeminiURLProtocol.enqueue(statusCode: 200, body: sampleResponseJSON)

        let backendWhitespace = GeminiDecisionsHTTPBackend(
            endpoint: .hosted(),
            apiKey: "   ",
            session: makeSession(),
            environmentOverride: [
                "GEMINI_API_KEY": "AIzaFromGeminiAfterTrim"
            ]
        )
        _ = try await backendWhitespace.evaluate(request: request)
        #expect(MockGeminiURLProtocol.recordedRequests.first?.value(forHTTPHeaderField: "x-goog-api-key") == "AIzaFromGeminiAfterTrim")

        // 3. Test GOOGLE_API_KEY fallback when GEMINI_API_KEY is absent
        MockGeminiURLProtocol.reset()
        MockGeminiURLProtocol.enqueue(statusCode: 200, body: sampleResponseJSON)

        let backendGoogle = GeminiDecisionsHTTPBackend(
            endpoint: .hosted(),
            apiKey: nil,
            session: makeSession(),
            environmentOverride: [
                "GOOGLE_API_KEY": "AIzaFromGoogleEnv"
            ]
        )
        _ = try await backendGoogle.evaluate(request: request)
        #expect(MockGeminiURLProtocol.recordedRequests.first?.value(forHTTPHeaderField: "x-goog-api-key") == "AIzaFromGoogleEnv")
    }

    @Test("HTTP Backend throws missingAPIKey when no key is configured in apiKey or environment")
    func testMissingAPIKeyThrows() async throws {
        let backend = GeminiDecisionsHTTPBackend(
            endpoint: .hosted(),
            apiKey: "   ",
            session: makeSession(),
            environmentOverride: [:]
        )

        let request = SystemOneRequest(
            state: "State",
            questions: ["test": .noul(instructions: "Test")]
        )

        await #expect(throws: SystemOneError.self) {
            try await backend.evaluate(request: request)
        }
    }

    @Test("HTTP Backend retries on HTTP 429 with Retry-After header")
    func testRetryAfter429Handling() async throws {
        MockGeminiURLProtocol.reset()
        MockGeminiURLProtocol.enqueue(
            statusCode: 429,
            headers: ["Retry-After": "0"],
            body: """
            {
              "error": {
                "code": 429,
                "message": "Resource has been exhausted (e.g. check rate limit).",
                "status": "RESOURCE_EXHAUSTED"
              }
            }
            """.data(using: .utf8)!
        )
        MockGeminiURLProtocol.enqueue(
            statusCode: 200,
            headers: ["x-goog-processing-ms": "15.0"],
            body: sampleResponseJSON
        )

        let policy = RetryPolicy(maxAttempts: 2, initialDelay: .zero)
        let backend = GeminiDecisionsHTTPBackend(
            endpoint: .hosted(),
            apiKey: "AIzaTestRetry",
            session: makeSession(),
            retryPolicy: policy
        )

        let request = SystemOneRequest(
            state: "Retry test",
            questions: ["isSafe": .noul(instructions: "Is safe?")]
        )

        let response = try await backend.evaluate(request: request)
        #expect(response.answers["isSafe"]?.noul == 0.98)
        #expect(response.serverDurationMs == 15.0)
        #expect(MockGeminiURLProtocol.recordedRequests.count == 2)
    }

    @Test("HTTP Backend does not retry non-retryable 401/403 and parses Google RPC error envelope")
    func testNonRetryableAuthErrors() async throws {
        MockGeminiURLProtocol.reset()
        MockGeminiURLProtocol.enqueue(
            statusCode: 403,
            body: """
            {
              "error": {
                "code": 403,
                "message": "The caller does not have permission",
                "status": "PERMISSION_DENIED"
              }
            }
            """.data(using: .utf8)!
        )

        let policy = RetryPolicy(maxAttempts: 3, initialDelay: .zero)
        let backend = GeminiDecisionsHTTPBackend(
            endpoint: .hosted(),
            apiKey: "AIzaForbidden",
            session: makeSession(),
            retryPolicy: policy
        )

        let request = SystemOneRequest(
            state: "Test",
            questions: ["isSafe": .noul(instructions: "Is safe?")]
        )

        do {
            _ = try await backend.evaluate(request: request)
            Issue.record("Expected authenticationFailed for 403 PERMISSION_DENIED")
        } catch let error as SystemOneError {
            if case .authenticationFailed(let message) = error {
                #expect(message.contains("The caller does not have permission"))
            } else {
                Issue.record("Expected .authenticationFailed, got: \(error)")
            }
        }

        #expect(MockGeminiURLProtocol.recordedRequests.count == 1)
    }

    @Test("HTTP Backend fails fast on 429 with quota exhaustion without retrying")
    func testExhaustedQuotaDoesNotRetry() async throws {
        MockGeminiURLProtocol.reset()
        MockGeminiURLProtocol.enqueue(
            statusCode: 429,
            headers: ["Retry-After": "10"],
            body: """
            {
              "error": {
                "code": 429,
                "message": "You exceeded your current quota, please check your plan and billing details.",
                "status": "RESOURCE_EXHAUSTED"
              }
            }
            """.data(using: .utf8)!
        )

        let policy = RetryPolicy(maxAttempts: 3, initialDelay: .zero)
        let backend = GeminiDecisionsHTTPBackend(
            endpoint: .hosted(),
            apiKey: "AIzaQuotaExhausted",
            session: makeSession(),
            retryPolicy: policy
        )

        let request = SystemOneRequest(
            state: "Test",
            questions: ["isSafe": .noul(instructions: "Is safe?")]
        )

        do {
            _ = try await backend.evaluate(request: request)
            Issue.record("Expected quotaExceeded for quota exhausted 429")
        } catch let error as SystemOneError {
            if case .quotaExceeded(let message) = error {
                #expect(message.contains("You exceeded your current quota"))
            } else {
                Issue.record("Expected .quotaExceeded, got: \(error)")
            }
        }

        #expect(MockGeminiURLProtocol.recordedRequests.count == 1)
    }

    @Test("HTTP Backend rejects cleartext remote http:// and embedded URL credentials before sending headers, while permitting loopback")
    func testEndpointTransportSecurityValidation() async throws {
        MockGeminiURLProtocol.reset()

        let request = SystemOneRequest(
            state: "Security check",
            questions: ["isSafe": .noul(instructions: "Is safe?")]
        )

        // 1. Remote http:// endpoint is rejected before any network request is made
        let insecureBackend = GeminiDecisionsHTTPBackend(
            endpoint: .custom(URL(string: "http://proxy.example.com/v1beta/decisions")!),
            apiKey: "AIzaSecretShouldNotLeak",
            session: makeSession(),
            retryPolicy: RetryPolicy(maxAttempts: 3, initialDelay: .zero)
        )
        do {
            _ = try await insecureBackend.evaluate(request: request)
            Issue.record("Expected networkError for cleartext remote http:// endpoint")
        } catch let error as SystemOneError {
            if case .networkError(let msg) = error {
                #expect(msg.contains("HTTPS is required"))
            } else {
                Issue.record("Expected .networkError, got \(error)")
            }
        }
        #expect(MockGeminiURLProtocol.recordedRequests.isEmpty)

        // 2. Embedded URL credentials rejected before network send
        let credentialedBackend = GeminiDecisionsHTTPBackend(
            endpoint: .custom(URL(string: "https://user:pass@proxy.example.com/v1beta/decisions")!),
            apiKey: "AIzaSecretShouldNotLeak",
            session: makeSession()
        )
        await #expect(throws: SystemOneError.self) {
            try await credentialedBackend.evaluate(request: request)
        }
        #expect(MockGeminiURLProtocol.recordedRequests.isEmpty)

        // 3. Loopback http://127.0.0.1 is permitted
        MockGeminiURLProtocol.enqueue(statusCode: 200, body: sampleResponseJSON)
        let loopbackBackend = GeminiDecisionsHTTPBackend(
            endpoint: .custom(URL(string: "http://127.0.0.1:8080/v1beta/decisions")!),
            apiKey: "AIzaLoopbackKey",
            session: makeSession()
        )
        let loopbackResp = try await loopbackBackend.evaluate(request: request)
        #expect(loopbackResp.answers["isSafe"]?.noul == 0.98)
        #expect(MockGeminiURLProtocol.recordedRequests.count == 1)
    }

    @Test("HTTP Backend honors Retry-After on HTTP 503, truncates oversized HTML error bodies, and does not retry non-transient TLS URLErrors")
    func testRetryAfterOn503TruncationAndNonTransientURLError() async throws {
        let request = SystemOneRequest(
            state: "Resilience check",
            questions: ["isSafe": .noul(instructions: "Is safe?")]
        )

        // 1. Retry-After respected on HTTP 503 (initialDelay is 30s so only Retry-After: 0 finishes instantly)
        MockGeminiURLProtocol.reset()
        MockGeminiURLProtocol.enqueue(
            statusCode: 503,
            headers: ["Retry-After": "0"],
            body: "Service temporarily overloaded".data(using: .utf8)!
        )
        MockGeminiURLProtocol.enqueue(statusCode: 200, body: sampleResponseJSON)

        let policyWithLongBackoff = RetryPolicy(maxAttempts: 2, initialDelay: .seconds(30))
        let backend503 = GeminiDecisionsHTTPBackend(
            endpoint: .hosted(),
            apiKey: "AIzaRetry503",
            session: makeSession(),
            retryPolicy: policyWithLongBackoff
        )
        let clock = ContinuousClock()
        let start = clock.now
        let resp = try await backend503.evaluate(request: request)
        let elapsed = start.duration(to: clock.now)
        #expect(resp.answers["isSafe"]?.noul == 0.98)
        #expect(elapsed < .seconds(2))
        #expect(MockGeminiURLProtocol.recordedRequests.count == 2)

        // 2. Oversized non-JSON HTML error body is truncated to <= 512 characters
        MockGeminiURLProtocol.reset()
        let hugeHTML = "<html><body>" + String(repeating: "Proxy Error ", count: 200) + "</body></html>"
        MockGeminiURLProtocol.enqueue(statusCode: 502, body: Data(hugeHTML.utf8))
        let noRetryBackend = GeminiDecisionsHTTPBackend(
            endpoint: .hosted(),
            apiKey: "AIzaHTML",
            session: makeSession(),
            retryPolicy: .none
        )
        do {
            _ = try await noRetryBackend.evaluate(request: request)
            Issue.record("Expected apiError for 502")
        } catch let error as SystemOneError {
            if case .apiError(let code, let message) = error {
                #expect(code == 502)
                #expect(message.count == 512)
            } else {
                Issue.record("Expected .apiError, got \(error)")
            }
        }

        // 3. Non-transient TLS URLError fails fast without retrying
        MockGeminiURLProtocol.reset()
        MockGeminiURLProtocol.enqueueFailure(URLError(.serverCertificateUntrusted))
        let tlsBackend = GeminiDecisionsHTTPBackend(
            endpoint: .hosted(),
            apiKey: "AIzaTLS",
            session: makeSession(),
            retryPolicy: RetryPolicy(maxAttempts: 3, initialDelay: .zero)
        )
        await #expect(throws: SystemOneError.self) {
            try await tlsBackend.evaluate(request: request)
        }
        #expect(MockGeminiURLProtocol.recordedRequests.count == 1)
    }

    @Test("Endpoint trailing slash normalization, LanguageModel model parameter, and CR/LF header sanitization")
    func testEndpointNormalizationModelOverrideAndHeaderSanitization() async throws {
        let trailingSlashEndpoint = GeminiDecisionsEndpoint(
            url: URL(string: "https://generativelanguage.googleapis.com/v1beta/decisions/")!,
            model: "gemini-decision-1-exp",
            clientRequestID: "  trace-42  "
        )
        #expect(trailingSlashEndpoint == .hosted(model: "gemini-decision-1-exp", clientRequestID: "  trace-42  "))
        #expect(trailingSlashEndpoint.url == GeminiDecisionsEndpoint.defaultURL)

        let customModelLM = GeminiDecisionsLanguageModel(
            apiKey: "AIzaCustomModel",
            model: "gemini-decision-1-preview"
        )
        #expect(customModelLM.executorConfiguration.modelID == "gemini-decision-1-preview")
        #expect(customModelLM.executorConfiguration.endpoint.model == "gemini-decision-1-preview")

        let request = SystemOneRequest(
            state: "Header check",
            questions: ["isSafe": .noul(instructions: "Is safe?")]
        )

        // Trims whitespace around clientRequestID
        MockGeminiURLProtocol.reset()
        MockGeminiURLProtocol.enqueue(statusCode: 200, body: sampleResponseJSON)
        let trimBackend = GeminiDecisionsHTTPBackend(
            endpoint: trailingSlashEndpoint,
            apiKey: "AIzaValid",
            session: makeSession()
        )
        _ = try await trimBackend.evaluate(request: request)
        #expect(MockGeminiURLProtocol.recordedRequests.first?.value(forHTTPHeaderField: "X-Client-Request-Id") == "trace-42")

        // Rejects CR/LF in apiKey
        MockGeminiURLProtocol.reset()
        let crlfKeyBackend = GeminiDecisionsHTTPBackend(
            endpoint: .hosted(),
            apiKey: "AIzaBad\r\nX-Injected: 1",
            session: makeSession()
        )
        do {
            _ = try await crlfKeyBackend.evaluate(request: request)
            Issue.record("Expected authenticationFailed for CR/LF in apiKey")
        } catch let error as SystemOneError {
            if case .authenticationFailed = error {
                // Expected
            } else {
                Issue.record("Expected .authenticationFailed, got \(error)")
            }
        }
        #expect(MockGeminiURLProtocol.recordedRequests.isEmpty)

        // Rejects CR/LF in clientRequestID
        let crlfReqIDBackend = GeminiDecisionsHTTPBackend(
            endpoint: .hosted(clientRequestID: "id\nX-Injected: 1"),
            apiKey: "AIzaValid",
            session: makeSession()
        )
        await #expect(throws: SystemOneError.self) {
            try await crlfReqIDBackend.evaluate(request: request)
        }
        #expect(MockGeminiURLProtocol.recordedRequests.isEmpty)
    }
}
