import Foundation
import FoundationModels
import UniformTypeIdentifiers
@_exported import SystemOneCore

/// Ergonomic shorthand alias for `GeminiDecisionsLanguageModel`.
public typealias GeminiLanguageModel = GeminiDecisionsLanguageModel

/// An Apple Foundation Models provider for the Google Gemini Decisions API (`gemini-decision-1`).
///
/// See tech-notes/0018-gemini-decisions-api-architecture.md
public struct GeminiDecisionsLanguageModel: LanguageModel, Sendable {

    /// Configuration parameters governing model evaluation and backend routing.
    public struct Configuration: Hashable, Sendable {
        public var endpoint: GeminiDecisionsEndpoint
        public var modelID: String
        public var backend: AnySystemOneBackend

        public init(
            endpoint: GeminiDecisionsEndpoint = .hosted(),
            apiKey: String? = nil,
            session: URLSession = .shared,
            timeoutInterval: TimeInterval = 30,
            retryPolicy: RetryPolicy = .default
        ) {
            self.endpoint = endpoint
            self.modelID = endpoint.model
            let httpBackend = GeminiDecisionsHTTPBackend(
                endpoint: endpoint,
                apiKey: apiKey,
                session: session,
                timeoutInterval: timeoutInterval,
                retryPolicy: retryPolicy
            )
            self.backend = AnySystemOneBackend(httpBackend)
        }

        public init(
            backend: any SystemOneBackend,
            modelID: String = GeminiDecisionsEndpoint.defaultModel,
            endpoint: GeminiDecisionsEndpoint = .hosted()
        ) {
            self.endpoint = endpoint
            self.modelID = modelID
            if let anyBackend = backend as? AnySystemOneBackend {
                self.backend = anyBackend
            } else {
                self.backend = AnySystemOneBackend(backend)
            }
        }
    }

    public typealias Executor = GeminiDecisionsExecutor

    public var executorConfiguration: Configuration

    public var capabilities: LanguageModelCapabilities {
        LanguageModelCapabilities([.guidedGeneration, .vision])
    }

    public init(
        apiKey: String? = nil,
        clientRequestID: String? = nil,
        endpoint: URL = GeminiDecisionsEndpoint.defaultURL,
        session: URLSession = .shared,
        timeoutInterval: TimeInterval = 30,
        retryPolicy: RetryPolicy = .default
    ) {
        let ep = GeminiDecisionsEndpoint(
            url: endpoint,
            model: GeminiDecisionsEndpoint.defaultModel,
            clientRequestID: clientRequestID
        )
        self.executorConfiguration = Configuration(
            endpoint: ep,
            apiKey: apiKey,
            session: session,
            timeoutInterval: timeoutInterval,
            retryPolicy: retryPolicy
        )
    }

    public init(
        endpoint: GeminiDecisionsEndpoint,
        apiKey: String? = nil,
        session: URLSession = .shared,
        timeoutInterval: TimeInterval = 30,
        retryPolicy: RetryPolicy = .default
    ) {
        self.executorConfiguration = Configuration(
            endpoint: endpoint,
            apiKey: apiKey,
            session: session,
            timeoutInterval: timeoutInterval,
            retryPolicy: retryPolicy
        )
    }

    public init(configuration: Configuration) {
        self.executorConfiguration = configuration
    }

    public init(
        backend: any SystemOneBackend,
        modelID: String = GeminiDecisionsEndpoint.defaultModel
    ) {
        self.executorConfiguration = Configuration(backend: backend, modelID: modelID)
    }

    /// Supported image attachment types (PNG, JPEG, WebP).
    public func supportsDataAttachmentType(_ type: UTType) async throws -> Bool {
        type.conforms(to: .png) || type.conforms(to: .jpeg) || type.conforms(to: .webP)
    }

    public func supportsDataEntryType(_ type: UTType) async throws -> Bool {
        false
    }
}
