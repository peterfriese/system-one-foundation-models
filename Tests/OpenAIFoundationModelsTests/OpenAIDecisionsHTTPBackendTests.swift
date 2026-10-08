import Testing
import Foundation
import SystemOneCore
@testable import OpenAIFoundationModels

// MARK: - Mock URLProtocol for OpenAIDecisionsHTTPBackendTests

final class MockOpenAIURLProtocol: URLProtocol {
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
                url: request.url ?? URL(string: "https://api.openai.com/v1/decisions")!,
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

@Suite("OpenAI Decisions HTTP Backend Tests", .serialized)
struct OpenAIDecisionsHTTPBackendTests {

    private func makeSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockOpenAIURLProtocol.self]
        return URLSession(configuration: config)
    }

    private let sampleResponseJSON = """
    {
      "id": "dec-test-99",
      "object": "decision",
      "model": "gpt-6-luna",
      "answers": [
        {
          "name": "isSafe",
          "type": "predicate",
          "probability": 0.98,
          "confidence": 0.98
        }
      ],
      "usage": {
        "input_tokens": 42,
        "output_tokens": 0
      }
    }
    """.data(using: .utf8)!

    @Test("HTTP Backend injects Authorization, Organization, Project, and Client Request ID headers")
    func testHeaderInjection() async throws {
        MockOpenAIURLProtocol.reset()
        MockOpenAIURLProtocol.enqueue(
            statusCode: 200,
            headers: ["openai-processing-ms": "24.5"],
            body: sampleResponseJSON
        )

        let endpoint = OpenAIDecisionsEndpoint.hosted(
            organization: "org-apple-dev",
            project: "proj-triage",
            clientRequestID: "req-custom-123"
        )
        let backend = OpenAIDecisionsHTTPBackend(
            endpoint: endpoint,
            apiKey: "sk-test-secret-key-12345",
            session: makeSession()
        )

        let request = SystemOneRequest(
            state: "Check sanity",
            model: "gpt-6-luna",
            questions: ["isSafe": .noul(instructions: "Is safe?")]
        )

        let response = try await backend.evaluate(request: request)

        #expect(response.model == "gpt-6-luna")
        #expect(response.serverDurationMs == 24.5)
        #expect(response.answers["isSafe"]?.noul == 0.98)

        let recorded = MockOpenAIURLProtocol.recordedRequests
        #expect(recorded.count == 1)
        let sentRequest = recorded[0]
        #expect(sentRequest.value(forHTTPHeaderField: "Authorization") == "Bearer sk-test-secret-key-12345")
        #expect(sentRequest.value(forHTTPHeaderField: "OpenAI-Organization") == "org-apple-dev")
        #expect(sentRequest.value(forHTTPHeaderField: "OpenAI-Project") == "proj-triage")
        #expect(sentRequest.value(forHTTPHeaderField: "X-Client-Request-Id") == "req-custom-123")
    }

    @Test("HTTP Backend throws missingAPIKey when no key is configured")
    func testMissingAPIKeyThrows() async throws {
        // Construct backend with empty key
        let backend = OpenAIDecisionsHTTPBackend(
            endpoint: .hosted(),
            apiKey: "",
            session: makeSession()
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
        MockOpenAIURLProtocol.reset()
        // Enqueue 429 with Retry-After: 0, followed by 200 OK
        MockOpenAIURLProtocol.enqueue(
            statusCode: 429,
            headers: ["Retry-After": "0"],
            body: """
            {"error": {"message": "Rate limit exceeded", "type": "rate_limit_error"}}
            """.data(using: .utf8)!
        )
        MockOpenAIURLProtocol.enqueue(
            statusCode: 200,
            headers: ["openai-processing-ms": "15.0"],
            body: sampleResponseJSON
        )

        let policy = RetryPolicy(maxAttempts: 2, initialDelay: .zero)
        let backend = OpenAIDecisionsHTTPBackend(
            endpoint: .hosted(),
            apiKey: "sk-test-retry",
            session: makeSession(),
            retryPolicy: policy
        )

        let request = SystemOneRequest(
            state: "Retry test",
            questions: ["isSafe": .noul(instructions: "Is safe?")]
        )

        let response = try await backend.evaluate(request: request)
        #expect(response.answers["isSafe"]?.noul == 0.98)
        #expect(MockOpenAIURLProtocol.recordedRequests.count == 2)
    }

    @Test("HTTP Backend does not retry non-retryable 401 Unauthorized")
    func testNonRetryable401() async throws {
        MockOpenAIURLProtocol.reset()
        MockOpenAIURLProtocol.enqueue(
            statusCode: 401,
            body: """
            {"error": {"message": "Invalid API key", "type": "invalid_request_error"}}
            """.data(using: .utf8)!
        )

        let policy = RetryPolicy(maxAttempts: 3, initialDelay: .zero)
        let backend = OpenAIDecisionsHTTPBackend(
            endpoint: .hosted(),
            apiKey: "sk-invalid",
            session: makeSession(),
            retryPolicy: policy
        )

        let request = SystemOneRequest(
            state: "Test",
            questions: ["isSafe": .noul(instructions: "Is safe?")]
        )

        do {
            _ = try await backend.evaluate(request: request)
            Issue.record("Expected apiError for 401")
        } catch let error as SystemOneError {
            if case .apiError(let statusCode, let message) = error {
                #expect(statusCode == 401)
                #expect(message.contains("Invalid API key"))
            } else {
                Issue.record("Expected .apiError, got: \(error)")
            }
        }

        // Should not have retried
        #expect(MockOpenAIURLProtocol.recordedRequests.count == 1)
    }
}
