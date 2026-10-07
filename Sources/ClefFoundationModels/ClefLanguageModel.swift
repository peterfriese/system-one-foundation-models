import Foundation
import FoundationModels
import UniformTypeIdentifiers
@_exported import SystemOneCore

/// An Apple Foundation Models provider for Cloudflare Clef and Clef-Flash multimodal decision models.
public struct ClefLanguageModel: LanguageModel, Sendable {
    public struct Configuration: Hashable, Sendable {
        public var endpoint: ClefEndpoint
        public var apiToken: String?
        public var modelID: String
        public var backend: ClefHTTPBackend

        public init(
            endpoint: ClefEndpoint,
            apiToken: String? = nil,
            session: URLSession = .shared,
            timeoutInterval: TimeInterval = 45,
            retryPolicy: RetryPolicy = .default
        ) {
            self.endpoint = endpoint
            self.apiToken = apiToken
            self.modelID = endpoint.modelIdentifier
            self.backend = ClefHTTPBackend(
                endpoint: endpoint,
                apiToken: apiToken,
                session: session,
                timeoutInterval: timeoutInterval,
                retryPolicy: retryPolicy
            )
        }

        public init(
            backend: ClefHTTPBackend,
            modelID: String? = nil
        ) {
            self.endpoint = backend.endpoint
            self.apiToken = backend.apiToken
            self.modelID = modelID ?? backend.endpoint.modelIdentifier
            self.backend = backend
        }
    }

    public typealias Executor = ClefExecutor

    public var executorConfiguration: Configuration

    public var capabilities: LanguageModelCapabilities {
        LanguageModelCapabilities([.guidedGeneration, .vision])
    }

    public init(
        endpoint: ClefEndpoint,
        apiToken: String? = nil,
        session: URLSession = .shared,
        timeoutInterval: TimeInterval = 45,
        retryPolicy: RetryPolicy = .default
    ) {
        self.executorConfiguration = Configuration(
            endpoint: endpoint,
            apiToken: apiToken,
            session: session,
            timeoutInterval: timeoutInterval,
            retryPolicy: retryPolicy
        )
    }

    public init(configuration: Configuration) {
        self.executorConfiguration = configuration
    }

    /// Supported image attachment types (PNG, JPEG, WebP).
    public func supportsDataAttachmentType(_ type: UTType) async throws -> Bool {
        type.conforms(to: .png) || type.conforms(to: .jpeg) || type.conforms(to: .webP)
    }

    public func supportsDataEntryType(_ type: UTType) async throws -> Bool {
        false
    }
}
