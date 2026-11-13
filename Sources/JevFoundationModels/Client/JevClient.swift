import Foundation
import SystemOneCore

/// A lightweight, Sendable client for dispatching decision evaluations to TypeSafe AI's Jev model.
public struct JevClient: SystemOneBackend, Sendable {
    public let configuration: JevLanguageModel.Configuration

    public init(configuration: JevLanguageModel.Configuration) {
        self.configuration = configuration
    }

    /// Dispatches a `JevRequest` to the Jev System One decision model using the configured transport.
    public func execute(request: JevRequest) async throws -> JevResponse {
        try await configuration.transport.send(
            request: request,
            apiKey: configuration.apiKey,
            endpoint: configuration.endpoint
        )
    }

    public func evaluate(request: SystemOneRequest) async throws -> SystemOneResponse {
        try await execute(request: request)
    }
}
