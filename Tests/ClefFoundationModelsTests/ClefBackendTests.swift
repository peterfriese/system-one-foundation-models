import Testing
import Foundation
import SystemOneCore
import ClefFoundationModels

// MARK: - Mock URLProtocol for Cloudflare Clef Backend

final class MockClefBackendProtocol: URLProtocol {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var _responseQueue: [Result<(statusCode: Int, headers: [String: String], body: Data), any Error>] = []
    nonisolated(unsafe) private static var _recordedRequests: [URLRequest] = []

    static var recordedRequests: [URLRequest] {
        lock.withLock { _recordedRequests }
    }

    static var requestCount: Int {
        lock.withLock { _recordedRequests.count }
    }

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

    static func enqueue(error: any Error) {
        lock.withLock {
            _responseQueue.append(.failure(error))
        }
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
                url: request.url ?? URL(string: "https://api.cloudflare.com")!,
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

@Suite("Clef HTTP Backend Tests", .serialized)
struct ClefBackendTests {

    private func makeSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockClefBackendProtocol.self]
        return URLSession(configuration: config)
    }

    private let sampleValidClefJSON = """
    {
      "model": "@cf/cloudflare/clef-flash",
      "answers": {
        "hasDefect": { "type": "noul", "noul": 0.93, "confidence": 0.93 },
        "defectType": { "type": "choice", "choice": "scratch", "confidence": 0.89 },
        "severity": { "type": "score", "score": 2.0, "confidence": 0.85 }
      },
      "usage": { "input_tokens": 240, "output_tokens": 12 }
    }
    """.data(using: .utf8)!

    private let sampleCloudflareEnvelopeJSON = """
    {
      "result": {
        "model": "@cf/cloudflare/clef-flash",
        "answers": {
          "hasDefect": { "type": "noul", "noul": 0.93, "confidence": 0.93 },
          "defectType": { "type": "choice", "choice": "scratch", "confidence": 0.89 },
          "severity": { "type": "score", "score": 2.0, "confidence": 0.85 }
        },
        "usage": { "input_tokens": 240, "output_tokens": 12 }
      },
      "success": true,
      "errors": [],
      "messages": []
    }
    """.data(using: .utf8)!

    private let sampleRequest = SystemOneRequest(
        state: "Inspect camera sensor housing",
        model: "@cf/cloudflare/clef-flash",
        questions: [
            "hasDefect": .noul(instructions: "Is there any visible defect?"),
            "defectType": .choice(instructions: "What type of defect?", criteria: ["scratch": "Scratch", "dent": "Dent"]),
            "severity": .score(instructions: "Defect severity", criteria: ["None", "Low", "Med", "High"])
        ]
    )

    // MARK: - Evaluation & Response Parsing

    @Test("ClefHTTPBackend decodes valid noul, choice, and score answers successfully")
    func testValidNoulChoiceScoreEvaluation() async throws {
        MockClefBackendProtocol.reset()
        MockClefBackendProtocol.enqueue(statusCode: 200, body: sampleValidClefJSON)

        let backend = ClefHTTPBackend(
            endpoint: .workersAI(accountID: "cf-test-acc", model: .clefFlash),
            apiToken: "cf-token-123",
            session: makeSession(),
            timeoutInterval: 10
        )

        let response = try await backend.evaluate(request: sampleRequest)

        #expect(response.model == "@cf/cloudflare/clef-flash")
        #expect(response.answers.count == 3)

        let noulAnswer = response.answers["hasDefect"]
        #expect(noulAnswer?.type == "noul")
        #expect(noulAnswer?.noul == 0.93)
        #expect(noulAnswer?.confidence == 0.93)

        let choiceAnswer = response.answers["defectType"]
        #expect(choiceAnswer?.type == "choice")
        #expect(choiceAnswer?.choice == "scratch")
        #expect(choiceAnswer?.confidence == 0.89)

        let scoreAnswer = response.answers["severity"]
        #expect(scoreAnswer?.type == "score")
        #expect(scoreAnswer?.score == 2.0)
        #expect(scoreAnswer?.confidence == 0.85)

        #expect(response.usage?.inputTokens == 240)
        #expect(response.usage?.outputTokens == 12)
    }

    @Test("ClefHTTPBackend cleanly parses Cloudflare v4 envelope with result payload")
    func testCloudflareEnvelopeEvaluation() async throws {
        MockClefBackendProtocol.reset()
        MockClefBackendProtocol.enqueue(statusCode: 200, body: sampleCloudflareEnvelopeJSON)

        let backend = ClefHTTPBackend(
            endpoint: .workersAI(accountID: "cf-test-acc", model: .clefFlash),
            apiToken: "cf-token-123",
            session: makeSession(),
            timeoutInterval: 10
        )

        let response = try await backend.evaluate(request: sampleRequest)

        #expect(response.model == "@cf/cloudflare/clef-flash")
        #expect(response.answers.count == 3)

        let noulAnswer = response.answers["hasDefect"]
        #expect(noulAnswer?.type == "noul")
        #expect(noulAnswer?.noul == 0.93)
        #expect(noulAnswer?.confidence == 0.93)

        let choiceAnswer = response.answers["defectType"]
        #expect(choiceAnswer?.type == "choice")
        #expect(choiceAnswer?.choice == "scratch")
        #expect(choiceAnswer?.confidence == 0.89)

        let scoreAnswer = response.answers["severity"]
        #expect(scoreAnswer?.type == "score")
        #expect(scoreAnswer?.score == 2.0)
        #expect(scoreAnswer?.confidence == 0.85)

        #expect(response.usage?.inputTokens == 240)
        #expect(response.usage?.outputTokens == 12)
    }

    @Test("ClefHTTPBackend surfaces error when Cloudflare envelope returns success false")
    func testCloudflareEnvelopeErrorSurfaced() async throws {
        let errorEnvelopeJSON = """
        {
          "result": null,
          "success": false,
          "errors": [
            { "code": 1000, "message": "Inference worker execution failed" }
          ],
          "messages": []
        }
        """.data(using: .utf8)!

        MockClefBackendProtocol.reset()
        MockClefBackendProtocol.enqueue(statusCode: 200, body: errorEnvelopeJSON)

        let backend = ClefHTTPBackend(
            endpoint: .workersAI(accountID: "cf-test-acc", model: .clefFlash),
            apiToken: "cf-token-123",
            session: makeSession()
        )

        do {
            _ = try await backend.evaluate(request: sampleRequest)
            Issue.record("Expected apiError to be thrown")
        } catch let error as SystemOneError {
            if case .apiError(let statusCode, let message) = error {
                #expect(statusCode == 200)
                #expect(message == "Inference worker execution failed")
            } else {
                Issue.record("Unexpected SystemOneError: \(error)")
            }
        }
    }

    @Test("ClefHTTPBackend throws descriptive decodingError when response is unparseable")
    func testUnparseableResponseThrowsDecodingError() async throws {
        let invalidJSON = """
        { "invalidKey": "unexpectedValue" }
        """.data(using: .utf8)!

        MockClefBackendProtocol.reset()
        MockClefBackendProtocol.enqueue(statusCode: 200, body: invalidJSON)

        let backend = ClefHTTPBackend(
            endpoint: .workersAI(accountID: "cf-test-acc", model: .clefFlash),
            session: makeSession()
        )

        do {
            _ = try await backend.evaluate(request: sampleRequest)
            Issue.record("Expected decodingError to be thrown")
        } catch let error as SystemOneError {
            if case .decodingError(let details) = error {
                #expect(details.contains("Failed to decode Clef response"))
            } else {
                Issue.record("Expected decodingError, got: \(error)")
            }
        }
    }

    // MARK: - Telemetry Header Parsing Tests

    @Test("ClefHTTPBackend parses server-timing duration header into serverDurationMs")
    func testServerTimingHeaderTelemetry() async throws {
        MockClefBackendProtocol.reset()
        let headers = ["server-timing": "inference;dur=38.4, cfL4;dur=1.2"]
        MockClefBackendProtocol.enqueue(statusCode: 200, headers: headers, body: sampleValidClefJSON)

        let backend = ClefHTTPBackend(
            endpoint: .workersAI(accountID: "cf-acc", model: .clefFlash),
            apiToken: "token",
            session: makeSession()
        )

        let response = try await backend.evaluate(request: sampleRequest)
        #expect(response.serverDurationMs == 38.4)
        #expect(response.transportDurationMs != nil)
    }

    @Test("ClefHTTPBackend server-timing prioritizes inference metric when listed after other metrics")
    func testServerTimingPrioritizesInference() async throws {
        MockClefBackendProtocol.reset()
        let headers = ["server-timing": "cfL4;dur=1.2, inference;dur=45.6, cache;dur=0.1"]
        MockClefBackendProtocol.enqueue(statusCode: 200, headers: headers, body: sampleValidClefJSON)

        let backend = ClefHTTPBackend(
            endpoint: .workersAI(accountID: "cf-acc", model: .clefFlash),
            apiToken: "token",
            session: makeSession()
        )

        let response = try await backend.evaluate(request: sampleRequest)
        #expect(response.serverDurationMs == 45.6)
    }

    @Test("ClefHTTPBackend parses x-envoy-upstream-service-time when server-timing is absent")
    func testEnvoyHeaderTelemetry() async throws {
        MockClefBackendProtocol.reset()
        let headers = ["x-envoy-upstream-service-time": "42.0"]
        MockClefBackendProtocol.enqueue(statusCode: 200, headers: headers, body: sampleValidClefJSON)

        let backend = ClefHTTPBackend(
            endpoint: .workersAI(accountID: "cf-acc", model: .clefFlash),
            apiToken: "token",
            session: makeSession()
        )

        let response = try await backend.evaluate(request: sampleRequest)
        #expect(response.serverDurationMs == 42.0)
    }

    // MARK: - Gateway & Auth Headers

    @Test("ClefHTTPBackend attaches cf-aig metadata headers when targeting Cloudflare AI Gateway")
    func testAIGatewayMetadataHeaders() async throws {
        MockClefBackendProtocol.reset()
        MockClefBackendProtocol.enqueue(statusCode: 200, body: sampleValidClefJSON)

        let backend = ClefHTTPBackend(
            endpoint: .gateway(accountID: "my-acc", gatewayID: "my-gw", model: .clefFlash),
            apiToken: "my-token",
            session: makeSession()
        )

        _ = try await backend.evaluate(request: sampleRequest)

        let recorded = MockClefBackendProtocol.recordedRequests
        #expect(recorded.count == 1)

        let request = recorded[0]
        #expect(request.value(forHTTPHeaderField: "cf-aig-metadata-app") == "system-one-foundation-models")
        #expect(request.value(forHTTPHeaderField: "cf-aig-metadata-tag") == "clef-multimodal")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer my-token")
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
    }

    @Test("ClefHTTPBackend omits Authorization header when apiToken is nil for local runner")
    func testAuthorizationOmittedWhenNil() async throws {
        MockClefBackendProtocol.reset()
        MockClefBackendProtocol.enqueue(statusCode: 200, body: sampleValidClefJSON)

        let backend = ClefHTTPBackend(
            endpoint: .local(port: 8080),
            apiToken: nil,
            session: makeSession()
        )

        _ = try await backend.evaluate(request: sampleRequest)

        let recorded = MockClefBackendProtocol.recordedRequests
        #expect(recorded.count == 1)
        #expect(recorded[0].value(forHTTPHeaderField: "Authorization") == nil)
        #expect(recorded[0].value(forHTTPHeaderField: "cf-aig-metadata-app") == nil)
    }

    // MARK: - Error & Retry Handling Tests

    @Test("401 Unauthorized is never retried and throws immediately")
    func test401UnauthorizedNeverRetried() async throws {
        MockClefBackendProtocol.reset()
        MockClefBackendProtocol.enqueue(statusCode: 401, body: Data("Invalid API Token".utf8))

        let backend = ClefHTTPBackend(
            endpoint: .workersAI(accountID: "acc", model: .clefFlash),
            apiToken: "bad-token",
            session: makeSession(),
            retryPolicy: RetryPolicy(maxAttempts: 3, initialDelay: .milliseconds(1))
        )

        do {
            _ = try await backend.evaluate(request: sampleRequest)
            Issue.record("Expected 401 apiError to be thrown")
        } catch let error as SystemOneError {
            if case .apiError(let statusCode, let message) = error {
                #expect(statusCode == 401)
                #expect(message.contains("Invalid API Token"))
            } else {
                Issue.record("Unexpected SystemOneError case: \(error)")
            }
        } catch {
            Issue.record("Unexpected error thrown: \(error)")
        }

        #expect(MockClefBackendProtocol.requestCount == 1)
    }

    @Test("429 Rate Limit retries with backoff and succeeds on subsequent attempt")
    func test429RateLimitRetriesThenSucceeds() async throws {
        MockClefBackendProtocol.reset()
        MockClefBackendProtocol.enqueue(statusCode: 429, headers: ["Retry-After": "0"], body: Data("Rate limited".utf8))
        MockClefBackendProtocol.enqueue(statusCode: 200, body: sampleValidClefJSON)

        let fastRetry = RetryPolicy(maxAttempts: 3, initialDelay: .milliseconds(1), multiplier: 1.0, jitter: 0.0)
        let backend = ClefHTTPBackend(
            endpoint: .workersAI(accountID: "acc", model: .clefFlash),
            apiToken: "token",
            session: makeSession(),
            retryPolicy: fastRetry
        )

        let response = try await backend.evaluate(request: sampleRequest)
        #expect(response.model == "@cf/cloudflare/clef-flash")
        #expect(MockClefBackendProtocol.requestCount == 2)
    }

    @Test("524 Cloudflare Gateway Timeout retries and succeeds")
    func test524CloudflareTimeoutRetries() async throws {
        MockClefBackendProtocol.reset()
        MockClefBackendProtocol.enqueue(statusCode: 524, body: Data("A timeout occurred".utf8))
        MockClefBackendProtocol.enqueue(statusCode: 200, body: sampleValidClefJSON)

        let fastRetry = RetryPolicy(maxAttempts: 3, initialDelay: .milliseconds(1), multiplier: 1.0, jitter: 0.0)
        let backend = ClefHTTPBackend(
            endpoint: .workersAI(accountID: "acc", model: .clefFlash),
            apiToken: "token",
            session: makeSession(),
            retryPolicy: fastRetry
        )

        let response = try await backend.evaluate(request: sampleRequest)
        #expect(response.model == "@cf/cloudflare/clef-flash")
        #expect(MockClefBackendProtocol.requestCount == 2)
    }

    @Test("Exhausting all retry attempts throws SystemOneError.apiError")
    func testExhaustingRetriesThrowsApiError() async throws {
        MockClefBackendProtocol.reset()
        MockClefBackendProtocol.enqueue(statusCode: 429, body: Data("Rate limit 1".utf8))
        MockClefBackendProtocol.enqueue(statusCode: 429, body: Data("Rate limit 2".utf8))
        MockClefBackendProtocol.enqueue(statusCode: 429, body: Data("Rate limit 3".utf8))

        let fastRetry = RetryPolicy(maxAttempts: 3, initialDelay: .milliseconds(1), multiplier: 1.0, jitter: 0.0)
        let backend = ClefHTTPBackend(
            endpoint: .workersAI(accountID: "acc", model: .clefFlash),
            apiToken: "token",
            session: makeSession(),
            retryPolicy: fastRetry
        )

        do {
            _ = try await backend.evaluate(request: sampleRequest)
            Issue.record("Expected apiError to be thrown after exhausted retries")
        } catch let error as SystemOneError {
            if case .apiError(let statusCode, _) = error {
                #expect(statusCode == 429)
            } else {
                Issue.record("Expected apiError(429), got: \(error)")
            }
        }

        #expect(MockClefBackendProtocol.requestCount == 3)
    }

    @Test("Network failure maps to SystemOneError.networkError")
    func testNetworkErrorMapping() async throws {
        MockClefBackendProtocol.reset()
        MockClefBackendProtocol.enqueue(error: URLError(.notConnectedToInternet))

        let noRetry = RetryPolicy(maxAttempts: 1)
        let backend = ClefHTTPBackend(
            endpoint: .local(port: 8080),
            session: makeSession(),
            retryPolicy: noRetry
        )

        do {
            _ = try await backend.evaluate(request: sampleRequest)
            Issue.record("Expected networkError to be thrown")
        } catch let error as SystemOneError {
            if case .networkError = error {
                // Succeeded in throwing typed networkError
            } else {
                Issue.record("Expected .networkError, got: \(error)")
            }
        }
    }

    @Test("Transient network failure retries with backoff and succeeds on subsequent attempt")
    func testNetworkErrorRetriesAndSucceeds() async throws {
        MockClefBackendProtocol.reset()
        MockClefBackendProtocol.enqueue(error: URLError(.timedOut))
        MockClefBackendProtocol.enqueue(statusCode: 200, body: sampleValidClefJSON)

        let fastRetry = RetryPolicy(maxAttempts: 3, initialDelay: .milliseconds(1), multiplier: 1.0, jitter: 0.0)
        let backend = ClefHTTPBackend(
            endpoint: .workersAI(accountID: "acc", model: .clefFlash),
            apiToken: "token",
            session: makeSession(),
            retryPolicy: fastRetry
        )

        let response = try await backend.evaluate(request: sampleRequest)
        #expect(response.model == "@cf/cloudflare/clef-flash")
        #expect(MockClefBackendProtocol.requestCount == 2)
    }

    @Test("504 Gateway Timeout retries and succeeds")
    func test504GatewayTimeoutRetries() async throws {
        MockClefBackendProtocol.reset()
        MockClefBackendProtocol.enqueue(statusCode: 504, body: Data("Gateway timeout".utf8))
        MockClefBackendProtocol.enqueue(statusCode: 200, body: sampleValidClefJSON)

        let fastRetry = RetryPolicy(maxAttempts: 3, initialDelay: .milliseconds(1), multiplier: 1.0, jitter: 0.0)
        let backend = ClefHTTPBackend(
            endpoint: .workersAI(accountID: "acc", model: .clefFlash),
            apiToken: "token",
            session: makeSession(),
            retryPolicy: fastRetry
        )

        let response = try await backend.evaluate(request: sampleRequest)
        #expect(response.model == "@cf/cloudflare/clef-flash")
        #expect(MockClefBackendProtocol.requestCount == 2)
    }

    @Test("Cancelled request throws CancellationError immediately without retry or wrapping")
    func testCancelledRequestThrowsCancellationError() async throws {
        MockClefBackendProtocol.reset()
        MockClefBackendProtocol.enqueue(error: URLError(.cancelled))

        let backend = ClefHTTPBackend(
            endpoint: .local(port: 8080),
            session: makeSession()
        )

        do {
            _ = try await backend.evaluate(request: sampleRequest)
            Issue.record("Expected CancellationError to be thrown")
        } catch is CancellationError {
            // Succeeded in propagating CancellationError
        } catch {
            Issue.record("Expected CancellationError, got \(error)")
        }
    }
}
