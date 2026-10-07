import Foundation
import FoundationModels
import SystemOneCore

/// An executor bridging `LanguageModelSession` requests to `ClefHTTPBackend`.
public final class ClefExecutor: LanguageModelExecutor, Sendable {
    public typealias Model = ClefLanguageModel
    public typealias Configuration = ClefLanguageModel.Configuration

    public let configuration: Configuration
    private let translator: SchemaTranslator
    private let synthesizer: ResponseSynthesizer

    public init(configuration: Configuration) throws {
        self.configuration = configuration
        self.translator = SchemaTranslator()
        self.synthesizer = ResponseSynthesizer()
    }

    public func prewarm(model: ClefLanguageModel, transcript: Transcript) {
        // HTTP connection prewarming can be performed if needed.
    }

    public func respond(
        to request: LanguageModelExecutorGenerationRequest,
        model: ClefLanguageModel,
        streamingInto channel: LanguageModelExecutorGenerationChannel
    ) async throws {
        guard let schema = request.schema else {
            throw SystemOneError.structuredOutputRequired
        }

        // 1. Extract context text and prompt from transcript
        let stateText = extractState(from: request.transcript)

        // 2. Extract and validate image attachments
        let images = try TranscriptAttachmentExtractor.extractImages(from: request.transcript)

        // 3. Translate schema into System One questions
        let translation = try translator.translate(schema)

        // 4. Dispatch multimodal request
        let systemOneRequest = SystemOneRequest(
            state: stateText,
            model: configuration.modelID,
            questions: translation.questions,
            images: images.isEmpty ? nil : images
        )

        let response = try await configuration.backend.evaluate(request: systemOneRequest)

        // 5. Synthesize payload for @Generable decoding
        let synthesizedText = try synthesizer.synthesize(
            answers: response.answers,
            layout: translation.layout
        )
        let entryID = UUID().uuidString
        let outputTokenCount = response.usage?.outputTokens ?? 0

        // 6. Non-autoregressive output tokens: 0
        await channel.send(.response(
            entryID: entryID,
            action: .appendText(synthesizedText, tokenCount: outputTokenCount)
        ))

        // 7. Emit rich metadata
        var metadata: [String: GeneratedContent] = [
            "model": GeneratedContent(response.model),
            "output_tokens": GeneratedContent(String(outputTokenCount))
        ]

        if let serverDuration = response.serverDurationMs {
            metadata["serverDurationMs"] = GeneratedContent(String(format: "%.1f", serverDuration))
        }
        if let transportDuration = response.transportDurationMs {
            metadata["transportDurationMs"] = GeneratedContent(String(format: "%.1f", transportDuration))
        }

        if let probJSON = synthesizer.extractProbabilitiesJSON(from: response.answers) {
            metadata["probabilities"] = (try? GeneratedContent(json: probJSON)) ?? GeneratedContent(probJSON)
        }
        if let confJSON = synthesizer.extractConfidenceJSON(from: response.answers) {
            metadata["confidence"] = (try? GeneratedContent(json: confJSON)) ?? GeneratedContent(confJSON)
        }
        if let scoresJSON = synthesizer.extractScoresJSON(from: response.answers, layout: translation.layout) {
            metadata["scores"] = (try? GeneratedContent(json: scoresJSON)) ?? GeneratedContent(scoresJSON)
        }

        await channel.send(.response(entryID: entryID, action: .updateMetadata(metadata)))

        // 8. Emit usage statistics
        if let usage = response.usage {
            await channel.send(.response(
                entryID: entryID,
                action: .updateUsage(
                    input: .init(totalTokenCount: usage.inputTokens, cachedTokenCount: 0),
                    output: .init(totalTokenCount: usage.outputTokens, reasoningTokenCount: 0)
                )
            ))
        }
    }

    public func extractState(from transcript: Transcript) -> String {
        var parts: [String] = []
        for entry in transcript {
            switch entry {
            case .instructions(let instructions):
                for segment in instructions.segments {
                    if case .text(let t) = segment { parts.append(t.content) }
                }
            case .prompt(let prompt):
                for segment in prompt.segments {
                    if case .text(let t) = segment { parts.append(t.content) }
                }
            case .response(let response):
                for segment in response.segments {
                    if case .text(let t) = segment { parts.append(t.content) }
                }
            default:
                break
            }
        }
        return parts.joined(separator: "\n")
    }
}
