import Foundation
import FoundationModels
import UniformTypeIdentifiers

/// An Apple Foundation Models provider for System One decision models.
public struct SystemOneLanguageModel: LanguageModel, Sendable {
    public struct Configuration: Hashable, Sendable {
        public var backend: AnySystemOneBackend
        public var modelID: String

        public init(
            backend: AnySystemOneBackend,
            modelID: String = "systemone-default"
        ) {
            self.backend = backend
            self.modelID = modelID
        }

        public init(
            backend: some SystemOneBackend,
            modelID: String = "systemone-default"
        ) {
            self.backend = AnySystemOneBackend(backend)
            self.modelID = modelID
        }

        public init(
            proxyEndpoint: URL,
            credential: ProxyCredential,
            modelID: String = "systemone-default",
            session: URLSession = .shared,
            timeoutInterval: TimeInterval = 30,
            retryPolicy: RetryPolicy = .default
        ) {
            let proxyBackend = SystemOneProxyBackend(
                proxyEndpoint: proxyEndpoint,
                credential: credential,
                session: session,
                timeoutInterval: timeoutInterval,
                retryPolicy: retryPolicy
            )
            self.backend = AnySystemOneBackend(proxyBackend)
            self.modelID = modelID
        }
    }

    public typealias Executor = SystemOneExecutor

    public var executorConfiguration: Configuration

    public var capabilities: LanguageModelCapabilities {
        LanguageModelCapabilities([.guidedGeneration, .vision])
    }

    public init(
        backend: some SystemOneBackend,
        modelID: String = "systemone-default"
    ) {
        self.executorConfiguration = Configuration(backend: AnySystemOneBackend(backend), modelID: modelID)
    }

    public init(
        backend: AnySystemOneBackend,
        modelID: String = "systemone-default"
    ) {
        self.executorConfiguration = Configuration(backend: backend, modelID: modelID)
    }

    public init(
        proxyEndpoint: URL,
        credential: ProxyCredential,
        modelID: String = "systemone-default",
        session: URLSession = .shared,
        timeoutInterval: TimeInterval = 30,
        retryPolicy: RetryPolicy = .default
    ) {
        self.executorConfiguration = Configuration(
            proxyEndpoint: proxyEndpoint,
            credential: credential,
            modelID: modelID,
            session: session,
            timeoutInterval: timeoutInterval,
            retryPolicy: retryPolicy
        )
    }

    public init(
        proxyEndpoint: URL,
        modelID: String = "systemone-default",
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
        type.conforms(to: .png) || type.conforms(to: .jpeg) || type.conforms(to: .webP)
    }

    public func supportsDataEntryType(_ type: UTType) async throws -> Bool {
        false
    }
}
