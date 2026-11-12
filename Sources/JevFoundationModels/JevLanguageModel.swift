import Foundation
import FoundationModels
import UniformTypeIdentifiers
import SystemOneCore

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
            endpoint: URL = URL(string: "https://api.typesafe.ai/v1/systemone")!,
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
        endpoint: URL = URL(string: "https://api.typesafe.ai/v1/systemone")!,
        transport: (any JevTransport)? = nil,
        retryPolicy: RetryPolicy = .default
    ) {
        let resolvedTransport = transport.map { AnyJevTransport($0) } ?? AnyJevTransport(URLSessionTransport(retryPolicy: retryPolicy))
        self.executorConfiguration = Configuration(
            apiKey: apiKey,
            modelID: modelID,
            endpoint: endpoint,
            transport: resolvedTransport
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

    public init(configuration: Configuration) {
        self.executorConfiguration = configuration
    }

    public func supportsDataAttachmentType(_ type: UTType) async throws -> Bool {
        false
    }

    public func supportsDataEntryType(_ type: UTType) async throws -> Bool {
        false
    }
}
