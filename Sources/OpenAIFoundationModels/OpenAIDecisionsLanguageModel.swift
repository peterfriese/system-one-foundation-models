import Foundation
import FoundationModels
import UniformTypeIdentifiers
@_exported import SystemOneCore

/// An Apple Foundation Models provider for the OpenAI Decisions API (`gpt-6-luna`).
///
/// See tech-notes/0017-openai-decisions-api-architecture.md
public struct OpenAIDecisionsLanguageModel: LanguageModel, Sendable {

    /// Configuration parameters governing model evaluation and backend routing.
    public struct Configuration: Hashable, Sendable {
        public var endpoint: OpenAIDecisionsEndpoint
        public var modelID: String
        public var backend: AnySystemOneBackend

        public init(
            endpoint: OpenAIDecisionsEndpoint = .hosted(),
            apiKey: String? = nil,
            session: URLSession = .shared,
            timeoutInterval: TimeInterval = 30,
            retryPolicy: RetryPolicy = .default
        ) {
            self.endpoint = endpoint
            self.modelID = endpoint.model
            let httpBackend = OpenAIDecisionsHTTPBackend(
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
            modelID: String = OpenAIDecisionsEndpoint.defaultModel,
            endpoint: OpenAIDecisionsEndpoint = .hosted()
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

    public typealias Executor = OpenAIDecisionsExecutor

    public var executorConfiguration: Configuration

    public var capabilities: LanguageModelCapabilities {
        LanguageModelCapabilities([.guidedGeneration, .vision])
    }

    public init(
        apiKey: String? = nil,
        organization: String? = nil,
        project: String? = nil,
        clientRequestID: String? = nil,
        endpoint: URL = OpenAIDecisionsEndpoint.defaultURL,
        session: URLSession = .shared,
        timeoutInterval: TimeInterval = 30,
        retryPolicy: RetryPolicy = .default
    ) {
        let ep = OpenAIDecisionsEndpoint(
            url: endpoint,
            model: OpenAIDecisionsEndpoint.defaultModel,
            organization: organization,
            project: project,
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
        endpoint: OpenAIDecisionsEndpoint,
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
        modelID: String = OpenAIDecisionsEndpoint.defaultModel
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
