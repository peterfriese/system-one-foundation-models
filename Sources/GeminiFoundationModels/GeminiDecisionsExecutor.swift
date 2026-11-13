import Foundation
import FoundationModels
import SystemOneCore

/// An executor bridging `LanguageModelSession` requests to Google Gemini Decisions API backends via `SystemOneExecutor`.
///
/// See tech-notes/0018-gemini-decisions-api-architecture.md
/// See tech-notes/0019-cross-provider-homogeneity-and-multimodal-shortcuts.md
public final class GeminiDecisionsExecutor: LanguageModelExecutor, Sendable {
    public typealias Model = GeminiDecisionsLanguageModel
    public typealias Configuration = GeminiDecisionsLanguageModel.Configuration

    public let configuration: Configuration
    private let underlyingExecutor: SystemOneExecutor
    private let coreModel: SystemOneLanguageModel

    public init(configuration: Configuration) {
        self.configuration = configuration
        let originalBackend = configuration.backend
        let validatedBackend = AnySystemOneBackend(id: originalBackend.id) { request in
            if let images = request.images, !images.isEmpty {
                try GeminiDecisionsAttachmentValidator.validate(attachments: images)
            }
            let response = try await originalBackend.evaluate(request: request)
            let normalizedUsage = SystemOneUsage(
                inputTokens: response.usage?.inputTokens ?? 0,
                outputTokens: 0
            )
            return SystemOneResponse(
                model: response.model,
                answers: response.answers,
                usage: normalizedUsage,
                serverDurationMs: response.serverDurationMs,
                transportDurationMs: response.transportDurationMs
            )
        }
        let coreConfig = SystemOneLanguageModel.Configuration(
            backend: validatedBackend,
            modelID: configuration.modelID,
            supportsVision: true,
            defaultOutputTokenCount: 0,
            emitsOutputTokensMetadata: true,
            alwaysEmitUsage: true,
            requiresAllAnswers: true,
            emptyStateFallback: "Evaluate decision against input."
        )
        self.coreModel = SystemOneLanguageModel(configuration: coreConfig)
        self.underlyingExecutor = SystemOneExecutor(configuration: coreConfig)
    }

    public func prewarm(model: GeminiDecisionsLanguageModel, transcript: Transcript) {
        underlyingExecutor.prewarm(model: coreModel, transcript: transcript)
    }

    public func respond(
        to request: LanguageModelExecutorGenerationRequest,
        model: GeminiDecisionsLanguageModel,
        streamingInto channel: LanguageModelExecutorGenerationChannel
    ) async throws {
        try await underlyingExecutor.respond(to: request, model: coreModel, streamingInto: channel)
    }

    public func extractState(from transcript: Transcript) -> String {
        underlyingExecutor.extractState(from: transcript)
    }
}
