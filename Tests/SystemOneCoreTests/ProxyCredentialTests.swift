import Testing
import Foundation
import CoreGraphics
import FoundationModels
@testable import SystemOneCore

// MARK: - Mock URLProtocol for SystemOneProxyBackend Tests

final class MockSystemOneProxyURLProtocol: URLProtocol {
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
                url: request.url ?? URL(string: "https://gateway.example.com")!,
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

// MARK: - Token Counter Actor for Per-Attempt Rotation

actor TokenCounter {
    private var count = 0

    func nextToken(prefix: String = "token") -> String {
        count += 1
        return "\(prefix)-\(count)"
    }
}

// MARK: - Test @Generable Schemas

@Generable
enum GatewayPriority: String, Sendable, CaseIterable, Choosable {
    case low
    case high
}

@Generable
struct GatewayTriageDecision: Sendable {
    @Guide(description: "Is this ticket urgent?")
    var isUrgent: Bool

    @Guide(description: "Select priority level")
    var priority: GatewayPriority
}

// MARK: - Test Suite

@Suite("ProxyCredential, ProxyEndpointValidator & SystemOneProxyBackend Tests", .serialized)
struct ProxyCredentialTests {

    private func makeSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockSystemOneProxyURLProtocol.self]
        return URLSession(configuration: config)
    }

    private let sampleResponseJSON = """
    {
      "model": "system-one-gateway",
      "answers": {
        "isUrgent": { "type": "noul", "noul": 0.94, "confidence": 0.94 },
        "priority": { "type": "choice", "choice": "high", "confidence": 0.92 }
      },
      "usage": { "input_tokens": 35, "output_tokens": 0 }
    }
    """.data(using: .utf8)!

    @Test("ProxyCredential factories (.bearer, .header, .appCheck, .custom) mutate URLRequest and conform to Hashable")
    func testProxyCredentialFactoriesAndHashable() async throws {
        let url = URL(string: "https://gateway.example.com/v1/decisions")!

        // 1. .bearer
        var req1 = URLRequest(url: url)
        let bearer = ProxyCredential.bearer { "jwt-token-123" }
        try await bearer.apply(to: &req1)
        #expect(req1.value(forHTTPHeaderField: "Authorization") == "Bearer jwt-token-123")

        // 2. .header with prefix and without prefix
        var req2 = URLRequest(url: url)
        let headerNoPrefix = ProxyCredential.header(name: "X-Custom-Token", provider: { "raw-tok" })
        try await headerNoPrefix.apply(to: &req2)
        #expect(req2.value(forHTTPHeaderField: "X-Custom-Token") == "raw-tok")

        var req3 = URLRequest(url: url)
        let headerWithPrefix = ProxyCredential.header(name: "X-Auth", prefix: "Token", provider: { "abc" })
        try await headerWithPrefix.apply(to: &req3)
        #expect(req3.value(forHTTPHeaderField: "X-Auth") == "Token abc")

        // 3. .appCheck (default and custom headerName)
        var req4 = URLRequest(url: url)
        let appCheckDefault = ProxyCredential.appCheck { "app-check-tok-1" }
        try await appCheckDefault.apply(to: &req4)
        #expect(req4.value(forHTTPHeaderField: "X-Firebase-AppCheck") == "app-check-tok-1")

        var req5 = URLRequest(url: url)
        let appCheckCustom = ProxyCredential.appCheck(headerName: "X-Custom-AppCheck") { "app-check-tok-2" }
        try await appCheckCustom.apply(to: &req5)
        #expect(req5.value(forHTTPHeaderField: "X-Custom-AppCheck") == "app-check-tok-2")

        // 4. .custom
        var req6 = URLRequest(url: url)
        let custom = ProxyCredential.custom { request in
            request.setValue("app-check-xyz", forHTTPHeaderField: "X-Firebase-AppCheck")
            request.setValue("Bearer user-jwt", forHTTPHeaderField: "Authorization")
        }
        try await custom.apply(to: &req6)
        #expect(req6.value(forHTTPHeaderField: "X-Firebase-AppCheck") == "app-check-xyz")
        #expect(req6.value(forHTTPHeaderField: "Authorization") == "Bearer user-jwt")

        // 5. Identity-based Hashable & Equatable
        let copyOfBearer = bearer
        #expect(bearer == copyOfBearer)
        #expect(bearer != appCheckDefault)
        let set: Set<ProxyCredential> = [bearer, copyOfBearer, appCheckDefault]
        #expect(set.count == 2)
    }

    @Test("ProxyEndpointValidator enforces HTTPS on remote hosts and permits HTTP strictly on loopback")
    func testProxyEndpointValidator() throws {
        // Valid HTTPS endpoints
        try ProxyEndpointValidator.validate(URL(string: "https://gateway.company.com/v1/decisions")!)
        try ProxyEndpointValidator.validate(URL(string: "https://us-central1-app.cloudfunctions.net/triage")!)

        // Valid HTTP loopback endpoints
        try ProxyEndpointValidator.validate(URL(string: "http://localhost:8080/v1/decisions")!)
        try ProxyEndpointValidator.validate(URL(string: "http://127.0.0.1:5001/v1/decisions")!)
        try ProxyEndpointValidator.validate(URL(string: "http://[::1]:8000/v1/decisions")!)

        // Invalid remote HTTP endpoints must throw SystemOneError.networkError
        let insecureURLs = [
            URL(string: "http://gateway.company.com/v1/decisions")!,
            URL(string: "http://192.168.1.10:8080/v1/decisions")!,
            URL(string: "ftp://gateway.company.com/v1/decisions")!
        ]

        for insecureURL in insecureURLs {
            do {
                try ProxyEndpointValidator.validate(insecureURL)
                Issue.record("Expected ProxyEndpointValidator to reject \(insecureURL)")
            } catch let SystemOneError.networkError(msg) {
                #expect(msg.contains("Insecure proxy endpoint: HTTPS is required"))
            }
        }

        // Embedded URL credentials rejected with specific message
        do {
            try ProxyEndpointValidator.validate(URL(string: "https://user:pass@gateway.company.com/v1/decisions")!)
            Issue.record("Expected embedded credentials to be rejected")
        } catch let SystemOneError.networkError(msg) {
            #expect(msg.contains("embedded user credentials"))
        }

        // Missing host rejected with specific message
        do {
            try ProxyEndpointValidator.validate(URL(string: "https:///v1/decisions")!)
            Issue.record("Expected missing host URL to be rejected")
        } catch let SystemOneError.networkError(msg) {
            #expect(msg.contains("missing scheme or host"))
        }
    }

    @Test("ProxyCredential hardens empty tokens, CR/LF injection, duplicate Bearer prefix, and deterministic id equality")
    func testProxyCredentialValidationAndDeterministicIdentity() async throws {
        let url = URL(string: "https://gateway.example.com/v1/decisions")!

        // 1. Duplicate "Bearer " (case-insensitive) stripped cleanly so "Bearer Bearer ..." never occurs
        var bearerReq = URLRequest(url: url)
        let dupBearer = ProxyCredential.bearer { "  bearer   test-token  " }
        try await dupBearer.apply(to: &bearerReq)
        #expect(bearerReq.value(forHTTPHeaderField: "Authorization") == "Bearer test-token")

        // 2. Empty or whitespace-only tokens rejected across .bearer, .header, and .appCheck
        let emptyCredentials: [ProxyCredential] = [
            .bearer { "   " },
            .bearer { "Bearer   " },
            .header(name: "X-Auth") { "" },
            .appCheck { " \t " }
        ]
        for cred in emptyCredentials {
            var req = URLRequest(url: url)
            do {
                try await cred.apply(to: &req)
                Issue.record("Expected empty token to throw authenticationFailed")
            } catch let SystemOneError.authenticationFailed(msg) {
                #expect(msg.contains("empty token"))
            }
        }

        // 3. CR/LF/NUL control characters rejected in header name, prefix, or token
        let crlfCredentials: [ProxyCredential] = [
            .bearer { "tok\r\nX-Injected: 1" },
            .header(name: "X-Bad\nName") { "tok" },
            .header(name: "X-Auth", prefix: "Token\r\nEvil: 1") { "tok" },
            .appCheck { "tok\0null" }
        ]
        for cred in crlfCredentials {
            var req = URLRequest(url: url)
            do {
                try await cred.apply(to: &req)
                Issue.record("Expected CR/LF/NUL injection to throw authenticationFailed")
            } catch SystemOneError.authenticationFailed {
                // Expected
            }
        }

        // 4. Deterministic UUID identity equality across factories
        let fixedID = UUID()
        #expect(ProxyCredential.bearer(id: fixedID) { "a" } == ProxyCredential.bearer(id: fixedID) { "b" })
        #expect(ProxyCredential.header(name: "X-Foo", id: fixedID) { "a" } == ProxyCredential.header(name: "X-Foo", id: fixedID) { "b" })
        #expect(ProxyCredential.appCheck(id: fixedID) { "a" } == ProxyCredential.appCheck(id: fixedID) { "b" })
        #expect(ProxyCredential.custom(id: fixedID) { _ in } == ProxyCredential.custom(id: fixedID) { _ in })
    }

    @Test("SystemOneProxyBackend dispatches canonical SystemOneRequest and rotates credentials per retry attempt")
    func testSystemOneProxyBackendAndRetryRotation() async throws {
        MockSystemOneProxyURLProtocol.reset()
        MockSystemOneProxyURLProtocol.enqueue(
            statusCode: 429,
            headers: ["Retry-After": "0"],
            body: Data("Rate limited".utf8)
        )
        MockSystemOneProxyURLProtocol.enqueue(
            statusCode: 200,
            headers: ["server-timing": "inference;dur=19.5"],
            body: sampleResponseJSON
        )

        let counter = TokenCounter()
        let proxyURL = URL(string: "https://gateway.company.com/v1/systemone")!
        let backend = SystemOneProxyBackend(
            proxyEndpoint: proxyURL,
            credential: .appCheck {
                await counter.nextToken(prefix: "appcheck")
            },
            session: makeSession(),
            retryPolicy: RetryPolicy(maxAttempts: 2, initialDelay: .zero)
        )

        let request = SystemOneRequest(
            state: "Production database failover alert",
            model: "system-one-gateway",
            questions: [
                "isUrgent": .noul(instructions: "Is this ticket urgent?"),
                "priority": .choice(instructions: "Select priority level", criteria: ["low": "Low", "high": "High"])
            ]
        )

        let response = try await backend.evaluate(request: request)
        #expect(response.model == "system-one-gateway")
        #expect(response.serverDurationMs == 19.5)
        #expect(response.answers["isUrgent"]?.noul == 0.94)

        let recorded = MockSystemOneProxyURLProtocol.recordedRequests
        #expect(recorded.count == 2)
        #expect(recorded[0].value(forHTTPHeaderField: "X-Firebase-AppCheck") == "appcheck-1")
        #expect(recorded[1].value(forHTTPHeaderField: "X-Firebase-AppCheck") == "appcheck-2")
    }

    @Test("Pattern B: SystemOneLanguageModel(proxyEndpoint:credential:) and trailing-closure authorize support multimodal attachments")
    func testSystemOneLanguageModelPatternBGateway() async throws {
        MockSystemOneProxyURLProtocol.reset()
        MockSystemOneProxyURLProtocol.enqueue(statusCode: 200, body: sampleResponseJSON)
        MockSystemOneProxyURLProtocol.enqueue(statusCode: 200, body: sampleResponseJSON)

        let proxyURL = URL(string: "https://gateway.company.com/v1/systemone")!

        // 1. Test credential initializer (.appCheck)
        let model1 = SystemOneLanguageModel(
            proxyEndpoint: proxyURL,
            credential: .appCheck { "attested-token-alpha" },
            modelID: "system-one-gateway",
            session: makeSession()
        )
        #expect(model1.capabilities.contains(.guidedGeneration))
        #expect(model1.capabilities.contains(.vision))

        let session1 = LanguageModelSession(model: model1)
        let result1 = try await session1.respond(
            to: "Customer production cluster is down",
            generating: GatewayTriageDecision.self
        )
        #expect(result1.content.isUrgent == true)
        #expect(result1.content.priority == .high)

        // 2. Test trailing-closure authorize initializer + multimodal image attachment
        let model2 = SystemOneLanguageModel(
            proxyEndpoint: proxyURL,
            modelID: "system-one-gateway",
            session: makeSession()
        ) { request in
            request.setValue("attested-token-beta", forHTTPHeaderField: "X-Firebase-AppCheck")
            request.setValue("Bearer user-jwt-99", forHTTPHeaderField: "Authorization")
        }

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let ctx = try #require(CGContext(
            data: nil,
            width: 16,
            height: 16,
            bitsPerComponent: 8,
            bytesPerRow: 64,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        let cgImage = try #require(ctx.makeImage())

        let session2 = LanguageModelSession(model: model2)
        let prompt = Prompt {
            "Screenshot of production alert"
            Attachment(cgImage)
        }
        let result2 = try await session2.respond(to: prompt, generating: GatewayTriageDecision.self)
        #expect(result2.content.isUrgent == true)

        let recorded = MockSystemOneProxyURLProtocol.recordedRequests
        #expect(recorded.count == 2)
        #expect(recorded[0].value(forHTTPHeaderField: "X-Firebase-AppCheck") == "attested-token-alpha")
        #expect(recorded[1].value(forHTTPHeaderField: "X-Firebase-AppCheck") == "attested-token-beta")
        #expect(recorded[1].value(forHTTPHeaderField: "Authorization") == "Bearer user-jwt-99")
    }

    @Test("SystemOneProxyBackend fails fast with authenticationFailed without retrying when ProxyCredential closure throws")
    func testCredentialClosureErrorFailsFastWithoutRetry() async throws {
        struct AttestationError: LocalizedError {
            var errorDescription: String? { "AppAttest key unavailable" }
        }

        MockSystemOneProxyURLProtocol.reset()
        let counter = TokenCounter()
        let proxyURL = URL(string: "https://gateway.company.com/v1/systemone")!

        let backend = SystemOneProxyBackend(
            proxyEndpoint: proxyURL,
            credential: .appCheck {
                _ = await counter.nextToken(prefix: "attempt")
                throw AttestationError()
            },
            session: makeSession(),
            retryPolicy: RetryPolicy(maxAttempts: 3, initialDelay: .zero)
        )

        let request = SystemOneRequest(
            state: "Test credential failure",
            questions: ["isUrgent": .noul(instructions: "Urgent?")]
        )

        do {
            _ = try await backend.evaluate(request: request)
            Issue.record("Expected authenticationFailed when credential closure throws")
        } catch let SystemOneError.authenticationFailed(msg) {
            #expect(msg.contains("AppAttest key unavailable"))
        }

        // Verify it failed on attempt 1 without dispatching any network request or retrying
        let nextToken = await counter.nextToken(prefix: "attempt")
        #expect(nextToken == "attempt-2")
        #expect(MockSystemOneProxyURLProtocol.recordedRequests.isEmpty)
    }

    @Test("SystemOneProxyBackend maps HTTP 401 and 403 responses to authenticationFailed without retrying")
    func testHTTP401And403MappedToAuthenticationFailed() async throws {
        let proxyURL = URL(string: "https://gateway.company.com/v1/systemone")!
        let request = SystemOneRequest(
            state: "Test 401/403",
            questions: ["isUrgent": .noul(instructions: "Urgent?")]
        )

        for statusCode in [401, 403] {
            MockSystemOneProxyURLProtocol.reset()
            MockSystemOneProxyURLProtocol.enqueue(
                statusCode: statusCode,
                body: Data("App Check token invalid (\(statusCode))".utf8)
            )

            let backend = SystemOneProxyBackend(
                proxyEndpoint: proxyURL,
                credential: .appCheck { "invalid-tok" },
                session: makeSession(),
                retryPolicy: RetryPolicy(maxAttempts: 3, initialDelay: .zero)
            )

            do {
                _ = try await backend.evaluate(request: request)
                Issue.record("Expected authenticationFailed for HTTP \(statusCode)")
            } catch let SystemOneError.authenticationFailed(msg) {
                #expect(msg.contains("App Check token invalid (\(statusCode))"))
            }

            #expect(MockSystemOneProxyURLProtocol.recordedRequests.count == 1)
        }
    }

    @Test("SystemOneProxyBackend extracts x-goog-processing-ms and openai-processing-ms when serverDurationMs is nil")
    func testUpstreamTimingHeadersExtraction() async throws {
        let proxyURL = URL(string: "https://gateway.company.com/v1/systemone")!
        let request = SystemOneRequest(
            state: "Timing header test",
            questions: [
                "isUrgent": .noul(instructions: "Urgent?"),
                "priority": .choice(instructions: "Priority", criteria: ["low": "Low", "high": "High"])
            ]
        )

        // 1. x-goog-processing-ms
        MockSystemOneProxyURLProtocol.reset()
        MockSystemOneProxyURLProtocol.enqueue(
            statusCode: 200,
            headers: ["x-goog-processing-ms": "17.25"],
            body: sampleResponseJSON
        )

        let backend = SystemOneProxyBackend(
            proxyEndpoint: proxyURL,
            credential: .bearer { "tok" },
            session: makeSession()
        )
        let res1 = try await backend.evaluate(request: request)
        #expect(res1.serverDurationMs == 17.25)

        // 2. openai-processing-ms
        MockSystemOneProxyURLProtocol.reset()
        MockSystemOneProxyURLProtocol.enqueue(
            statusCode: 200,
            headers: ["openai-processing-ms": "23.75"],
            body: sampleResponseJSON
        )
        let res2 = try await backend.evaluate(request: request)
        #expect(res2.serverDurationMs == 23.75)

        // 3. No timing headers and nil serverDurationMs in JSON -> serverDurationMs stays nil (not fabricated)
        MockSystemOneProxyURLProtocol.reset()
        MockSystemOneProxyURLProtocol.enqueue(statusCode: 200, body: sampleResponseJSON)
        let res3 = try await backend.evaluate(request: request)
        #expect(res3.serverDurationMs == nil)
        #expect(res3.transportDurationMs != nil)
    }

    @Test("SystemOneProxyBackend populates httpBody before credential.apply and propagates URLError(.cancelled) as CancellationError")
    func testBodyBeforeCredentialAndCooperativeCancellation() async throws {
        actor BodyObserver {
            private(set) var bodyLength: Int = 0
            func record(_ count: Int) { bodyLength = count }
        }

        let proxyURL = URL(string: "https://gateway.company.com/v1/systemone")!
        let request = SystemOneRequest(
            state: "Sign payload",
            questions: [
                "isUrgent": .noul(instructions: "Urgent?"),
                "priority": .choice(instructions: "Priority", criteria: ["low": "Low", "high": "High"])
            ]
        )

        // 1. httpBody is populated before .custom closure runs (enabling HMAC signing)
        MockSystemOneProxyURLProtocol.reset()
        MockSystemOneProxyURLProtocol.enqueue(statusCode: 200, body: sampleResponseJSON)
        let observer = BodyObserver()
        let signingBackend = SystemOneProxyBackend(
            proxyEndpoint: proxyURL,
            credential: .custom { req in
                await observer.record(req.httpBody?.count ?? 0)
                req.setValue("hmac-ok", forHTTPHeaderField: "X-Signature")
            },
            session: makeSession()
        )
        _ = try await signingBackend.evaluate(request: request)
        let observedLen = await observer.bodyLength
        #expect(observedLen > 0)
        #expect(MockSystemOneProxyURLProtocol.recordedRequests.first?.value(forHTTPHeaderField: "X-Signature") == "hmac-ok")

        // 2. URLError(.cancelled) inside ProxyCredential closure propagates CancellationError (not authenticationFailed)
        MockSystemOneProxyURLProtocol.reset()
        let cancellingBackend = SystemOneProxyBackend(
            proxyEndpoint: proxyURL,
            credential: .appCheck {
                throw URLError(.cancelled)
            },
            session: makeSession(),
            retryPolicy: RetryPolicy(maxAttempts: 3, initialDelay: .zero)
        )
        do {
            _ = try await cancellingBackend.evaluate(request: request)
            Issue.record("Expected CancellationError when credential closure throws URLError(.cancelled)")
        } catch is CancellationError {
            // Expected
        } catch {
            Issue.record("Expected CancellationError, got \(error)")
        }
        #expect(MockSystemOneProxyURLProtocol.recordedRequests.isEmpty)

        // 3. SystemOneLanguageModel gates .vision capability on supportsVision
        struct TextOnlyMockBackend: SystemOneBackend {
            func evaluate(request: SystemOneRequest) async throws -> SystemOneResponse {
                SystemOneResponse(model: "text-only", answers: [:])
            }
        }
        let textOnlyModel = SystemOneLanguageModel(backend: TextOnlyMockBackend())
        #expect(textOnlyModel.supportsVision == false)
        #expect(textOnlyModel.capabilities.contains(.guidedGeneration))
        #expect(!textOnlyModel.capabilities.contains(.vision))
        #expect(try await textOnlyModel.supportsDataAttachmentType(.png) == false)

        let visionProxyModel = SystemOneLanguageModel(
            proxyEndpoint: proxyURL,
            credential: .bearer { "tok" },
            session: makeSession()
        )
        #expect(visionProxyModel.supportsVision == true)
        #expect(visionProxyModel.capabilities.contains(.vision))
        #expect(try await visionProxyModel.supportsDataAttachmentType(.png) == true)
    }
}
