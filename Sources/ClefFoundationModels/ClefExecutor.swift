import Foundation
import FoundationModels
import SystemOneCore

/// An executor bridging `LanguageModelSession` requests to Clef multimodal backends via `SystemOneExecutor`.
public final class ClefExecutor: LanguageModelExecutor, Sendable {
    public typealias Model = ClefLanguageModel
    public typealias Configuration = ClefLanguageModel.Configuration

    public let configuration: Configuration
    private let underlyingExecutor: SystemOneExecutor
    private let coreModel: SystemOneLanguageModel

    public init(configuration: Configuration) throws {
        self.configuration = configuration
        let coreConfig = SystemOneLanguageModel.Configuration(
            backend: configuration.backend,
            modelID: configuration.modelID,
            supportsVision: true,
            defaultOutputTokenCount: 0,
            emitsOutputTokensMetadata: true
        )
        self.coreModel = SystemOneLanguageModel(configuration: coreConfig)
        self.underlyingExecutor = SystemOneExecutor(configuration: coreConfig)
    }

    public func prewarm(model: ClefLanguageModel, transcript: Transcript) {
        underlyingExecutor.prewarm(model: coreModel, transcript: transcript)
    }

    public func respond(
        to request: LanguageModelExecutorGenerationRequest,
        model: ClefLanguageModel,
        streamingInto channel: LanguageModelExecutorGenerationChannel
    ) async throws {
        try await underlyingExecutor.respond(to: request, model: coreModel, streamingInto: channel)
    }

    public func extractState(from transcript: Transcript) -> String {
        underlyingExecutor.extractState(from: transcript)
    }
}
