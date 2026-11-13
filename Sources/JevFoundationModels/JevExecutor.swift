import Foundation
import FoundationModels
import SystemOneCore

/// An executor bridging `LanguageModelSession` requests to the TypeSafe AI Jev decision API.
public final class JevExecutor: LanguageModelExecutor, Sendable {
    public typealias Model = JevLanguageModel
    public typealias Configuration = JevLanguageModel.Configuration

    public let configuration: Configuration
    private let underlyingExecutor: SystemOneExecutor
    private let coreModel: SystemOneLanguageModel

    public init(configuration: Configuration) throws {
        self.configuration = configuration
        let client = JevClient(configuration: configuration)
        let coreConfig = SystemOneLanguageModel.Configuration(
            backend: client,
            modelID: configuration.modelID
        )
        self.coreModel = SystemOneLanguageModel(configuration: coreConfig)
        self.underlyingExecutor = SystemOneExecutor(configuration: coreConfig)
    }

    public func prewarm(model: JevLanguageModel, transcript: Transcript) {
        underlyingExecutor.prewarm(model: coreModel, transcript: transcript)
    }

    public func respond(
        to request: LanguageModelExecutorGenerationRequest,
        model: JevLanguageModel,
        streamingInto channel: LanguageModelExecutorGenerationChannel
    ) async throws {
        try await underlyingExecutor.respond(to: request, model: coreModel, streamingInto: channel)
    }

    public func extractState(from transcript: Transcript) -> String {
        underlyingExecutor.extractState(from: transcript)
    }
}
