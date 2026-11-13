import Testing
import Foundation
import FoundationModels
import SystemOneCore
import LayaFoundationModels

// MARK: - Mock URLProtocol for HTTP Testing

final class MockURLProtocol: URLProtocol {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var _requestHandler: (@Sendable (URLRequest) throws -> (HTTPURLResponse, Data))?

    static var requestHandler: (@Sendable (URLRequest) throws -> (HTTPURLResponse, Data))? {
        get {
            lock.lock()
            defer { lock.unlock() }
            return _requestHandler
        }
        set {
            lock.lock()
            defer { lock.unlock() }
            _requestHandler = newValue
        }
    }

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let handler = MockURLProtocol.requestHandler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }

        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

private final class CapturedRequestBox: @unchecked Sendable {
    private let lock = NSLock()
    private var _request: URLRequest?

    var request: URLRequest? {
        get { lock.withLock { _request } }
        set { lock.withLock { _request = newValue } }
    }
}

@Suite("LayaFoundationModels HTTP Adapter Tests", .serialized)
struct LayaFoundationModelsTests {

    @Generable
    struct RoutingTriageDecision: Sendable {
        @Guide(description: "Department best suited for this task")
        var department: String
    }

    @Test("LayaEndpoint presets produce correct endpoint URLs")
    func testLayaEndpointPresets() {
        #expect(LayaEndpoint.localDefault.url.absoluteString == "http://127.0.0.1:8000/v1/systemone")
        #expect(LayaEndpoint.localAlt.url.absoluteString == "http://127.0.0.1:8770/v1/systemone")
        #expect(LayaEndpoint.local(port: 8080).url.absoluteString == "http://127.0.0.1:8080/v1/systemone")
        #expect(LayaEndpoint.hosted.url.absoluteString == "https://api.impossibl.com/v1/systemone")

        let customURL = URL(string: "https://my-laya.internal/v1/systemone")!
        #expect(LayaEndpoint.custom(customURL).url == customURL)
    }

    @Test("LayaHTTPBackend omits Authorization header when apiKey is nil for local laya-serve")
    func testLayaHTTPBackendOmitsAuthHeaderWhenNil() async throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        let session = URLSession(configuration: config)

        let box = CapturedRequestBox()
        MockURLProtocol.requestHandler = { request in
            box.request = request
            let json = """
            {
              "model": "laya-rl-agent",
              "answers": {
                "department": { "type": "choice", "choice": "billing", "confidence": 0.95 }
              },
              "usage": { "input_tokens": 40, "output_tokens": 0 }
            }
            """
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            return (response, Data(json.utf8))
        }
        defer { MockURLProtocol.requestHandler = nil }

        let backend = LayaHTTPBackend(endpoint: .localDefault, apiKey: nil, session: session)
        let request = SystemOneRequest(
            state: "Refund request",
            questions: ["department": .choice(instructions: "Which team?", criteria: ["billing": "Invoices"])]
        )

        let response = try await backend.evaluate(request: request)
        #expect(response.answers["department"]?.choice == "billing")
        #expect(box.request?.value(forHTTPHeaderField: "Authorization") == nil)
        #expect(box.request?.value(forHTTPHeaderField: "Content-Type") == "application/json")
        #expect(box.request?.url?.absoluteString == "http://127.0.0.1:8000/v1/systemone")
    }

    @Test("LayaHTTPBackend attaches Bearer token header when apiKey is provided")
    func testLayaHTTPBackendAttachesAuthHeader() async throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        let session = URLSession(configuration: config)

        let box = CapturedRequestBox()
        MockURLProtocol.requestHandler = { request in
            box.request = request
            let json = """
            {
              "model": "laya-rl-agent",
              "answers": {},
              "usage": { "input_tokens": 10, "output_tokens": 0 }
            }
            """
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: [
                    "Content-Type": "application/json",
                    "x-envoy-upstream-service-time": "32.4"
                ]
            )!
            return (response, Data(json.utf8))
        }
        defer { MockURLProtocol.requestHandler = nil }

        let backend = LayaHTTPBackend(
            endpoint: .hosted,
            apiKey: "secret-token-xyz",
            session: session
        )
        let request = SystemOneRequest(state: "Check status", questions: [:])
        let response = try await backend.evaluate(request: request)

        #expect(box.request?.value(forHTTPHeaderField: "Authorization") == "Bearer secret-token-xyz")
        #expect(response.serverDurationMs == 32.4)
    }

    @Test("LayaLanguageModel initializes Foundation Models session cleanly")
    func testLayaLanguageModelCapabilities() {
        let model = LayaLanguageModel(endpoint: .localAlt)
        #expect(model.capabilities.contains(.guidedGeneration) == true)
        #expect(model.capabilities.contains(.toolCalling) == false)
        #expect(model.executorConfiguration.endpoint == .localAlt)
        #expect(model.executorConfiguration.modelID == "english")

        let proxyURL = URL(string: "https://laya-gateway.company.com/v1/systemone")!
        let proxyModel1 = LayaLanguageModel(
            proxyEndpoint: proxyURL,
            credential: .appCheck { "laya-tok-1" }
        )
        #expect(proxyModel1.executorConfiguration.endpoint == .custom(proxyURL))

        let proxyModel2 = LayaLanguageModel(proxyEndpoint: proxyURL) { req in
            req.setValue("laya-tok-2", forHTTPHeaderField: "X-Firebase-AppCheck")
        }
        #expect(proxyModel2.executorConfiguration.endpoint == .custom(proxyURL))
    }

    @Test("LayaHTTPBackend supports ProxyCredential with httpBody available, suppresses apiKey, maps 401/403 to authenticationFailed, and rejects insecure remote HTTP")
    func testLayaHTTPBackendProxyCredential() async throws {
        actor BodyCheck {
            private(set) var size = 0
            private(set) var attempts = 0
            func record(_ len: Int) {
                attempts += 1
                size = len
            }
            func resetAttempts() {
                attempts = 0
            }
        }

        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        let session = URLSession(configuration: config)

        let box = CapturedRequestBox()
        MockURLProtocol.requestHandler = { request in
            box.request = request
            let json = """
            {
              "model": "laya-rl-agent",
              "answers": {},
              "usage": { "input_tokens": 10, "output_tokens": 0 }
            }
            """
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            return (response, Data(json.utf8))
        }
        defer { MockURLProtocol.requestHandler = nil }

        let bodyCheck = BodyCheck()
        let proxyURL = URL(string: "https://laya-gateway.company.com/v1/systemone")!
        let backend = LayaHTTPBackend(
            endpoint: .custom(proxyURL),
            apiKey: "laya-master-must-not-leak",
            proxyCredential: .custom { req in
                await bodyCheck.record(req.httpBody?.count ?? 0)
                req.setValue("laya-attested-xyz", forHTTPHeaderField: "X-Firebase-AppCheck")
            },
            session: session
        )
        let request = SystemOneRequest(state: "Check status", questions: [:])
        _ = try await backend.evaluate(request: request)

        let bodyLen = await bodyCheck.size
        #expect(bodyLen > 0)
        #expect(box.request?.value(forHTTPHeaderField: "X-Firebase-AppCheck") == "laya-attested-xyz")
        #expect(box.request?.value(forHTTPHeaderField: "Authorization") == nil)

        // Proxy 401/403 -> authenticationFailed on attempt 1 (0 retries)
        for statusCode in [401, 403] {
            await bodyCheck.resetAttempts()
            MockURLProtocol.requestHandler = { req in
                let response = HTTPURLResponse(
                    url: req.url!,
                    statusCode: statusCode,
                    httpVersion: nil,
                    headerFields: nil
                )!
                return (response, Data("Laya auth denied (\(statusCode))".utf8))
            }

            let authBackend = LayaHTTPBackend(
                proxyEndpoint: proxyURL,
                credential: .custom { req in
                    await bodyCheck.record(req.httpBody?.count ?? 0)
                    req.setValue("bad-tok", forHTTPHeaderField: "X-Firebase-AppCheck")
                },
                session: session,
                retryPolicy: RetryPolicy(maxAttempts: 3, initialDelay: .zero)
            )

            do {
                _ = try await authBackend.evaluate(request: request)
                Issue.record("Expected authenticationFailed for Laya \(statusCode)")
            } catch let SystemOneError.authenticationFailed(msg) {
                #expect(msg.contains("Laya auth denied (\(statusCode))"))
            }
            let callCount = await bodyCheck.attempts
            #expect(callCount == 1)
        }

        let insecureBackend = LayaHTTPBackend(
            proxyEndpoint: URL(string: "http://remote-laya.example.com/v1/systemone")!,
            credential: .bearer { "tok" },
            session: session
        )
        await #expect(throws: SystemOneError.self) {
            _ = try await insecureBackend.evaluate(request: request)
        }
    }

    @Test("LayaEndpoint.validatedURL rejects invalid TCP ports without crashing .url")
    func testLayaEndpointPortValidation() throws {
        // Accessing .url never traps even on out-of-range ports
        _ = LayaEndpoint.local(port: 0).url
        _ = LayaEndpoint.local(port: 70000).url
        _ = LayaEndpoint.local(port: -5).url

        #expect(throws: SystemOneError.self) {
            _ = try LayaEndpoint.local(port: 0).validatedURL()
        }
        #expect(throws: SystemOneError.self) {
            _ = try LayaEndpoint.local(port: 70000).validatedURL()
        }
        let valid = try LayaEndpoint.local(port: 8770).validatedURL()
        #expect(valid.absoluteString == "http://127.0.0.1:8770/v1/systemone")
    }

    @Test("LayaHTTPBackend retries 503 responses and LayaLanguageModel supports init(backend:)")
    func testLayaRetryAndBackendInitializer() async throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        let session = URLSession(configuration: config)

        final class AttemptCounter: @unchecked Sendable {
            var count = 0
        }
        let counter = AttemptCounter()
        MockURLProtocol.requestHandler = { request in
            counter.count += 1
            if counter.count == 1 {
                let r503 = HTTPURLResponse(
                    url: request.url!,
                    statusCode: 503,
                    httpVersion: nil,
                    headerFields: ["Retry-After": "0"]
                )!
                return (r503, Data("busy".utf8))
            }
            let json = """
            {"model":"english","answers":{"decision":{"type":"noul","noul":0.82,"confidence":0.82}}}
            """
            let r200 = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            return (r200, Data(json.utf8))
        }
        defer { MockURLProtocol.requestHandler = nil }

        let retryPolicy = RetryPolicy(maxAttempts: 2, initialDelay: .milliseconds(1), jitter: 0.0)
        let httpBackend = LayaHTTPBackend(endpoint: .localDefault, session: session, retryPolicy: retryPolicy)
        let lmSession = LanguageModelSession(model: LayaLanguageModel(backend: httpBackend))
        let prob = try await lmSession.probability(of: "Should retry succeed?", state: "Test")
        #expect(counter.count == 2)
        #expect(abs(prob - 0.82) < 0.0001)
    }
}
