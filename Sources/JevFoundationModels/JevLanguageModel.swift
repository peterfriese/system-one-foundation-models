import Foundation
import FoundationModels
import UniformTypeIdentifiers
import SystemOneCore

/// Defines connection endpoints for TypeSafe AI's Jev System One API.
public enum JevEndpoint: Sendable, Hashable {
    /// Default TypeSafe AI hosted endpoint (`https://api.typesafe.ai/v1/systemone`).
    case hosted
    /// Arbitrary custom endpoint URL.
    case custom(URL)

    private static let hostedURL: URL = {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "api.typesafe.ai"
        components.path = "/v1/systemone"
        guard let built = components.url else {
            preconditionFailure("Static JevEndpoint.hostedURL components must form a valid URL")
        }
        return built
    }()

    public var url: URL {
        switch self {
        case .hosted:
            return Self.hostedURL
        case .custom(let url):
            return url
        }
    }

    public func validatedURL() throws -> URL {
        let candidate = url
        guard let scheme = candidate.scheme?.lowercased(), scheme == "https" || scheme == "http",
              let host = candidate.host, !host.isEmpty else {
            throw SystemOneError.networkError("Invalid Jev endpoint URL: '\(candidate.absoluteString)'.")
        }
        return candidate
    }
}

/// An Apple Foundation Models provider for TypeSafe AI's Jev System One decision models.
public struct JevLanguageModel: LanguageModel, Sendable {
    public struct Configuration: Hashable, Sendable {
        public var apiKey: String?
        public var modelID: String
        public var endpoint: URL
        public var transport: AnyJevTransport

        public init(
            apiKey: String? = nil,
            modelID: String = "jev-latest",
            endpoint: URL = JevEndpoint.hosted.url,
            transport: AnyJevTransport = AnyJevTransport(URLSessionTransport())
        ) {
            self.apiKey = apiKey
            self.modelID = modelID
            self.endpoint = endpoint
            self.transport = transport
        }
    }

    public typealias Executor = JevExecutor

    public var executorConfiguration: Configuration

    public var capabilities: LanguageModelCapabilities {
        LanguageModelCapabilities([.guidedGeneration])
    }

    public init(
        apiKey: String? = nil,
        modelID: String = "jev-latest",
        endpoint: URL = JevEndpoint.hosted.url,
        transport: (any JevTransport)? = nil,
        retryPolicy: RetryPolicy = .default
    ) {
        let resolvedKey = apiKey ?? Self.nonEmptyEnv("TYPESAFE_API_KEY")
        let resolvedTransport = transport.map { AnyJevTransport($0) }
            ?? AnyJevTransport(URLSessionTransport(retryPolicy: retryPolicy))
        self.executorConfiguration = Configuration(
            apiKey: resolvedKey,
            modelID: modelID,
            endpoint: endpoint,
            transport: resolvedTransport
        )
    }

    public init(
        endpoint: JevEndpoint,
        apiKey: String? = nil,
        modelID: String = "jev-latest",
        transport: (any JevTransport)? = nil,
        retryPolicy: RetryPolicy = .default
    ) {
        self.init(
            apiKey: apiKey,
            modelID: modelID,
            endpoint: endpoint.url,
            transport: transport,
            retryPolicy: retryPolicy
        )
    }

    public init(
        proxyEndpoint: URL,
        credential: ProxyCredential,
        modelID: String = "jev-latest",
        session: URLSession = .shared,
        timeoutInterval: TimeInterval = 30,
        retryPolicy: RetryPolicy = .default
    ) {
        let proxyTransport = ProxyTransport(
            proxyEndpoint: proxyEndpoint,
            credential: credential,
            session: session,
            timeoutInterval: timeoutInterval,
            retryPolicy: retryPolicy
        )
        self.executorConfiguration = Configuration(
            apiKey: nil,
            modelID: modelID,
            endpoint: proxyEndpoint,
            transport: AnyJevTransport(proxyTransport)
        )
    }

    public init(
        proxyEndpoint: URL,
        modelID: String = "jev-latest",
        session: URLSession = .shared,
        timeoutInterval: TimeInterval = 30,
        retryPolicy: RetryPolicy = .default,
        authorize: @escaping @Sendable (inout URLRequest) async throws -> Void
    ) {
        self.init(
            proxyEndpoint: proxyEndpoint,
            credential: .custom(authorize),
            modelID: modelID,
            session: session,
            timeoutInterval: timeoutInterval,
            retryPolicy: retryPolicy
        )
    }

    public init(
        backend: any SystemOneBackend,
        modelID: String = "jev-latest"
    ) {
        let wrapped = (backend as? AnySystemOneBackend) ?? AnySystemOneBackend(backend)
        self.executorConfiguration = Configuration(
            apiKey: nil,
            modelID: modelID,
            endpoint: JevEndpoint.hosted.url,
            transport: AnyJevTransport { request in
                try await wrapped.evaluate(request: request)
            }
        )
    }

    public init(configuration: Configuration) {
        self.executorConfiguration = configuration
    }

    public func supportsDataAttachmentType(_ type: UTType) async throws -> Bool {
        false
    }

    public func supportsDataEntryType(_ type: UTType) async throws -> Bool {
        false
    }

    private static func nonEmptyEnv(_ key: String) -> String? {
        guard let raw = ProcessInfo.processInfo.environment[key]?.trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty else {
            return nil
        }
        return raw
    }
}
