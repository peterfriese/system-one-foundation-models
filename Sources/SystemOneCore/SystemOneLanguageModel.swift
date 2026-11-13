import Foundation
import FoundationModels
import UniformTypeIdentifiers

/// An Apple Foundation Models provider for System One decision models.
public struct SystemOneLanguageModel: LanguageModel, Sendable {
    public struct Configuration: Hashable, Sendable {
        public var backend: AnySystemOneBackend
        public var modelID: String
        public var supportsVision: Bool
        public var defaultOutputTokenCount: Int
        public var emitsOutputTokensMetadata: Bool
        public var alwaysEmitUsage: Bool
        public var requiresAllAnswers: Bool
        public var emptyStateFallback: String

        public init(
            backend: AnySystemOneBackend,
            modelID: String = "systemone-default",
            supportsVision: Bool = false,
            defaultOutputTokenCount: Int = 1,
            emitsOutputTokensMetadata: Bool = false,
            alwaysEmitUsage: Bool = false,
            requiresAllAnswers: Bool = false,
            emptyStateFallback: String = "Application state evaluation"
        ) {
            self.backend = backend
            self.modelID = modelID
            self.supportsVision = supportsVision
            self.defaultOutputTokenCount = defaultOutputTokenCount
            self.emitsOutputTokensMetadata = emitsOutputTokensMetadata
            self.alwaysEmitUsage = alwaysEmitUsage
            self.requiresAllAnswers = requiresAllAnswers
            self.emptyStateFallback = emptyStateFallback
        }

        public init(
            backend: any SystemOneBackend,
            modelID: String = "systemone-default",
            supportsVision: Bool = false,
            defaultOutputTokenCount: Int = 1,
            emitsOutputTokensMetadata: Bool = false,
            alwaysEmitUsage: Bool = false,
            requiresAllAnswers: Bool = false,
            emptyStateFallback: String = "Application state evaluation"
        ) {
            let wrapped = (backend as? AnySystemOneBackend) ?? AnySystemOneBackend(backend)
            self.init(
                backend: wrapped,
                modelID: modelID,
                supportsVision: supportsVision,
                defaultOutputTokenCount: defaultOutputTokenCount,
                emitsOutputTokensMetadata: emitsOutputTokensMetadata,
                alwaysEmitUsage: alwaysEmitUsage,
                requiresAllAnswers: requiresAllAnswers,
                emptyStateFallback: emptyStateFallback
            )
        }

        public init(
            proxyEndpoint: URL,
            credential: ProxyCredential,
            modelID: String = "systemone-default",
            supportsVision: Bool = true,
            session: URLSession = .shared,
            timeoutInterval: TimeInterval = 30,
            retryPolicy: RetryPolicy = .default,
            defaultOutputTokenCount: Int = 1,
            emitsOutputTokensMetadata: Bool = false,
            alwaysEmitUsage: Bool = false,
            requiresAllAnswers: Bool = false,
            emptyStateFallback: String = "Application state evaluation"
        ) {
            let proxyBackend = SystemOneProxyBackend(
                proxyEndpoint: proxyEndpoint,
                credential: credential,
                session: session,
                timeoutInterval: timeoutInterval,
                retryPolicy: retryPolicy
            )
            self.init(
                backend: AnySystemOneBackend(proxyBackend),
                modelID: modelID,
                supportsVision: supportsVision,
                defaultOutputTokenCount: defaultOutputTokenCount,
                emitsOutputTokensMetadata: emitsOutputTokensMetadata,
                alwaysEmitUsage: alwaysEmitUsage,
                requiresAllAnswers: requiresAllAnswers,
                emptyStateFallback: emptyStateFallback
            )
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
        self.executorConfiguration = Configuration(
            backend: backend,
            modelID: modelID,
            supportsVision: supportsVision
        )
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
        guard supportsVision else { return false }
        return type.conforms(to: .png) || type.conforms(to: .jpeg) || type.conforms(to: .webP)
    }
}
