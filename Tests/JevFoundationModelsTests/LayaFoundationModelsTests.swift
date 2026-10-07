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
    var request: URLRequest?
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
    }
}
