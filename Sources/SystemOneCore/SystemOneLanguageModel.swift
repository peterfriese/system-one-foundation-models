import Foundation
import FoundationModels
import UniformTypeIdentifiers

/// An Apple Foundation Models provider for System One decision models.
public struct SystemOneLanguageModel: LanguageModel, Sendable {
    public struct Configuration: Hashable, Sendable {
        public var backend: AnySystemOneBackend
        public var modelID: String
        public var supportsVision: Bool

        public init(
            backend: AnySystemOneBackend,
            modelID: String = "systemone-default",
            supportsVision: Bool = false
        ) {
            self.backend = backend
            self.modelID = modelID
            self.supportsVision = supportsVision
        }

        public init(
            backend: some SystemOneBackend,
            modelID: String = "systemone-default",
            supportsVision: Bool = false
        ) {
            self.backend = AnySystemOneBackend(backend)
            self.modelID = modelID
            self.supportsVision = supportsVision
        }

        public init(
            proxyEndpoint: URL,
            credential: ProxyCredential,
            modelID: String = "systemone-default",
            supportsVision: Bool = true,
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
            self.supportsVision = supportsVision
        }
    }

    public typealias Executor = SystemOneExecutor

    public var executorConfiguration: Configuration

    /// Whether the underlying System One backend accepts multimodal vision attachments.
    public var supportsVision: Bool {
        executorConfiguration.supportsVision
    }

    public var capabilities: LanguageModelCapabilities {
        if supportsVision {
            return LanguageModelCapabilities([.guidedGeneration, .vision])
        } else {
            return LanguageModelCapabilities([.guidedGeneration])
        }
    }

    public init(
        backend: any SystemOneBackend,
        modelID: String = "systemone-default",
        supportsVision: Bool = false
    ) {
        if let anyBackend = backend as? AnySystemOneBackend {
            self.executorConfiguration = Configuration(
                backend: anyBackend,
                modelID: modelID,
                supportsVision: supportsVision
            )
        } else {
            self.executorConfiguration = Configuration(
                backend: AnySystemOneBackend(backend),
                modelID: modelID,
                supportsVision: supportsVision
            )
        }
    }

    public init(
        proxyEndpoint: URL,
        credential: ProxyCredential,
        modelID: String = "systemone-default",
        supportsVision: Bool = true,
        session: URLSession = .shared,
        timeoutInterval: TimeInterval = 30,
        retryPolicy: RetryPolicy = .default
    ) {
        self.executorConfiguration = Configuration(
            proxyEndpoint: proxyEndpoint,
            credential: credential,
            modelID: modelID,
            supportsVision: supportsVision,
            session: session,
            timeoutInterval: timeoutInterval,
            retryPolicy: retryPolicy
        )
    }

    public init(
        proxyEndpoint: URL,
        modelID: String = "systemone-default",
        supportsVision: Bool = true,
        session: URLSession = .shared,
        timeoutInterval: TimeInterval = 30,
        retryPolicy: RetryPolicy = .default,
        authorize: @escaping @Sendable (inout URLRequest) async throws -> Void
    ) {
        self.init(
            proxyEndpoint: proxyEndpoint,
            credential: .custom(authorize),
            modelID: modelID,
            supportsVision: supportsVision,
            session: session,
            timeoutInterval: timeoutInterval,
            retryPolicy: retryPolicy
        )
    }

    public init(configuration: Configuration) {
        self.executorConfiguration = configuration
    }

    public func supportsDataAttachmentType(_ type: UTType) async throws -> Bool {
        guard supportsVision else { return false }
        return type.conforms(to: .png) || type.conforms(to: .jpeg) || type.conforms(to: .webP)
    }

    public func supportsDataEntryType(_ type: UTType) async throws -> Bool {
        false
    }
}
