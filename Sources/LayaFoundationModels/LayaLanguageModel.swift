import Foundation
import FoundationModels
import UniformTypeIdentifiers
@_exported import SystemOneCore

/// An Apple Foundation Models provider for self-hosted or remote Laya decision models (`laya-serve`).
public struct LayaLanguageModel: LanguageModel, Sendable {
    public struct Configuration: Hashable, Sendable {
        public var endpoint: LayaEndpoint
        public var modelID: String
        public var apiKey: String?
        public var backend: LayaHTTPBackend

        public init(
            endpoint: LayaEndpoint = .localDefault,
            modelID: String = "english",
            apiKey: String? = nil,
            proxyCredential: ProxyCredential? = nil,
            session: URLSession = .shared,
            timeoutInterval: TimeInterval = 30,
            retryPolicy: RetryPolicy = .default
        ) {
            self.endpoint = endpoint
            self.modelID = modelID
            self.apiKey = apiKey
            self.backend = LayaHTTPBackend(
                endpoint: endpoint,
                apiKey: apiKey,
                proxyCredential: proxyCredential,
                session: session,
                timeoutInterval: timeoutInterval,
                retryPolicy: retryPolicy
            )
        }
    }

    public typealias Executor = LayaExecutor

    public var executorConfiguration: Configuration

    public var capabilities: LanguageModelCapabilities {
        LanguageModelCapabilities([.guidedGeneration])
    }

    public init(
        endpoint: LayaEndpoint = .localDefault,
        modelID: String = "english",
        apiKey: String? = nil,
        proxyCredential: ProxyCredential? = nil,
        session: URLSession = .shared,
        timeoutInterval: TimeInterval = 30,
        retryPolicy: RetryPolicy = .default
    ) {
        self.executorConfiguration = Configuration(
            endpoint: endpoint,
            modelID: modelID,
            apiKey: apiKey,
            proxyCredential: proxyCredential,
            session: session,
            timeoutInterval: timeoutInterval,
            retryPolicy: retryPolicy
        )
    }

    public init(
        proxyEndpoint: URL,
        modelID: String = "english",
        credential: ProxyCredential,
        session: URLSession = .shared,
        timeoutInterval: TimeInterval = 30,
        retryPolicy: RetryPolicy = .default
    ) {
        self.executorConfiguration = Configuration(
            endpoint: .custom(proxyEndpoint),
            modelID: modelID,
            apiKey: nil,
            proxyCredential: credential,
            session: session,
            timeoutInterval: timeoutInterval,
            retryPolicy: retryPolicy
        )
    }

    public init(
        proxyEndpoint: URL,
        credential: ProxyCredential,
        modelID: String,
        session: URLSession = .shared,
        timeoutInterval: TimeInterval = 30,
        retryPolicy: RetryPolicy = .default
    ) {
        self.init(
            proxyEndpoint: proxyEndpoint,
            modelID: modelID,
            credential: credential,
            session: session,
            timeoutInterval: timeoutInterval,
            retryPolicy: retryPolicy
        )
    }

    public init(
        proxyEndpoint: URL,
        modelID: String = "english",
        session: URLSession = .shared,
        timeoutInterval: TimeInterval = 30,
        retryPolicy: RetryPolicy = .default,
        authorize: @escaping @Sendable (inout URLRequest) async throws -> Void
    ) {
        self.init(
            proxyEndpoint: proxyEndpoint,
            modelID: modelID,
            credential: .custom(authorize),
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

/// An executor bridging `LanguageModelSession` requests to a Laya HTTP server.
public final class LayaExecutor: LanguageModelExecutor, Sendable {
    public typealias Model = LayaLanguageModel
    public typealias Configuration = LayaLanguageModel.Configuration

    public let configuration: Configuration
    private let underlyingExecutor: SystemOneExecutor

    public init(configuration: Configuration) throws {
        self.configuration = configuration
        let coreConfig = SystemOneLanguageModel.Configuration(
            backend: configuration.backend,
            modelID: configuration.modelID
        )
        self.underlyingExecutor = try SystemOneExecutor(configuration: coreConfig)
    }

    public func prewarm(model: LayaLanguageModel, transcript: Transcript) {
        // HTTP endpoints require no local prewarming
    }

    public func respond(
        to request: LanguageModelExecutorGenerationRequest,
        model: LayaLanguageModel,
        streamingInto channel: LanguageModelExecutorGenerationChannel
    ) async throws {
        let coreModel = SystemOneLanguageModel(
            backend: configuration.backend,
            modelID: configuration.modelID
        )
        try await underlyingExecutor.respond(to: request, model: coreModel, streamingInto: channel)
    }

    public func extractState(from transcript: Transcript) -> String {
        underlyingExecutor.extractState(from: transcript)
    }
}
