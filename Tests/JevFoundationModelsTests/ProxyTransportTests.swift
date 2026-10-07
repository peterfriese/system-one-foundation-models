import Testing
import Foundation
@testable import JevFoundationModels

// MARK: - Mock URLProtocol for Proxy Testing

final class MockProxyURLProtocol: URLProtocol {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var _responseQueue: [Result<(statusCode: Int, headers: [String: String], body: Data), any Error>] = []
    nonisolated(unsafe) private static var _recordedRequests: [URLRequest] = []

    static var recordedRequests: [URLRequest] {
        lock.withLock { _recordedRequests }
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
                url: request.url ?? URL(string: "https://proxy.example.com")!,
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

@Suite("ProxyTransport Tests", .serialized)
struct ProxyTransportTests {

    private func makeSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockProxyURLProtocol.self]
        return URLSession(configuration: config)
    }

    private var sampleResponseData: Data {
        """
        {
            "model": "jev-latest",
            "answers": {
                "priority": { "type": "choice", "choice": "high", "confidence": 0.95 }
            },
            "usage": { "input_tokens": 12, "output_tokens": 4 }
        }
        """.data(using: .utf8)!
    }

    @Test("ProxyTransport dispatches to proxy endpoint and attaches bearer credential")
    func testBearerCredential() async throws {
        MockProxyURLProtocol.reset()
        MockProxyURLProtocol.enqueue(statusCode: 200, headers: ["x-envoy-upstream-service-time": "42.5"], body: sampleResponseData)

        let proxyURL = URL(string: "https://custom-gateway.company.internal/triage")!
        let dummyEndpoint = URL(string: "https://api.typesafe.ai/v1/systemone")!

        let transport = ProxyTransport(
            proxyEndpoint: proxyURL,
            credential: .bearer { "secret-bearer-token-123" },
            session: makeSession()
        )

        let request = JevRequest(
            state: "Database connection timed out",
            model: "jev-latest",
            questions: [
                "priority": .choice(instructions: "Assign priority", criteria: ["low": "Low priority", "high": "High priority"])
            ]
        )

        let response = try await transport.send(request: request, apiKey: nil, endpoint: dummyEndpoint)

        #expect(response.model == "jev-latest")
        #expect(response.serverDurationMs == 42.5)
        #expect(response.answers.count == 1)
        #expect(response.answers["priority"]?.choice == "high")

        let recorded = MockProxyURLProtocol.recordedRequests
        #expect(recorded.count == 1)
        #expect(recorded.first?.url == proxyURL)
        #expect(recorded.first?.value(forHTTPHeaderField: "Authorization") == "Bearer secret-bearer-token-123")
        #expect(recorded.first?.value(forHTTPHeaderField: "Content-Type") == "application/json")
    }

    @Test("ProxyTransport attaches custom header with prefix (e.g. Firebase App Check)")
    func testHeaderCredential() async throws {
        MockProxyURLProtocol.reset()
        MockProxyURLProtocol.enqueue(statusCode: 200, body: sampleResponseData)

        let proxyURL = URL(string: "https://my-app.cloudfunctions.net/jevProxy")!
        let transport = ProxyTransport(
            proxyEndpoint: proxyURL,
            credential: .header(name: "X-Firebase-AppCheck", provider: { "app-check-token-xyz" }),
            session: makeSession()
        )

        let request = JevRequest(state: "Test", model: "jev-latest", questions: [:])
        _ = try await transport.send(request: request, apiKey: nil, endpoint: proxyURL)

        let recorded = MockProxyURLProtocol.recordedRequests
        #expect(recorded.first?.value(forHTTPHeaderField: "X-Firebase-AppCheck") == "app-check-token-xyz")
    }

    @Test("ProxyTransport custom modifier transforms request")
    func testCustomCredentialModifier() async throws {
        MockProxyURLProtocol.reset()
        MockProxyURLProtocol.enqueue(statusCode: 200, body: sampleResponseData)

        let proxyURL = URL(string: "https://gateway.example.com/api")!
        let transport = ProxyTransport(
            proxyEndpoint: proxyURL,
            credential: .custom { req in
                req.setValue("tenant-42", forHTTPHeaderField: "X-Tenant-ID")
                req.setValue("sig-999", forHTTPHeaderField: "X-Signature")
            },
            session: makeSession()
        )

        let request = JevRequest(state: "Test", model: "jev-latest", questions: [:])
        _ = try await transport.send(request: request, apiKey: nil, endpoint: proxyURL)

        let recorded = MockProxyURLProtocol.recordedRequests
        #expect(recorded.first?.value(forHTTPHeaderField: "X-Tenant-ID") == "tenant-42")
        #expect(recorded.first?.value(forHTTPHeaderField: "X-Signature") == "sig-999")
    }

    @Test("ProxyTransport retries on 429 and succeeds on subsequent attempt")
    func testRetryOn429() async throws {
        MockProxyURLProtocol.reset()
        MockProxyURLProtocol.enqueue(statusCode: 429, headers: ["Retry-After": "1"], body: Data("Rate limited".utf8))
        MockProxyURLProtocol.enqueue(statusCode: 200, body: sampleResponseData)

        let sleepRecorder = SleepRecorder()
        let proxyURL = URL(string: "https://proxy.example.com")!

        let transport = ProxyTransport(
            proxyEndpoint: proxyURL,
            credential: .bearer { "tok" },
            session: makeSession(),
            retryPolicy: RetryPolicy(maxAttempts: 3),
            sleep: { sleepRecorder.record($0) },
            randomness: { 0.5 },
            now: { Date() }
        )

        let request = JevRequest(state: "Test", model: "jev-latest", questions: [:])
        let response = try await transport.send(request: request, apiKey: nil, endpoint: proxyURL)

        #expect(response.answers.count == 1)
        #expect(MockProxyURLProtocol.recordedRequests.count == 2)
        #expect(sleepRecorder.delays == [.seconds(1)])
    }
}
