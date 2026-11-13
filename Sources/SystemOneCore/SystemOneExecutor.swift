import Foundation
import FoundationModels

/// An executor bridging `LanguageModelSession` requests to any `SystemOneBackend`.
public final class SystemOneExecutor: LanguageModelExecutor, Sendable {
    public typealias Model = SystemOneLanguageModel
    public typealias Configuration = SystemOneLanguageModel.Configuration

    public let configuration: Configuration
    private let translator: SchemaTranslator
    private let synthesizer: ResponseSynthesizer

    public init(configuration: Configuration) {
        self.configuration = configuration
        self.translator = SchemaTranslator()
        self.synthesizer = ResponseSynthesizer()
    }

    public func prewarm(model: SystemOneLanguageModel, transcript: Transcript) {
        // System One models with local weights or remote connections may prewarm as needed.
    }

    public func respond(
        to request: LanguageModelExecutorGenerationRequest,
        model: SystemOneLanguageModel,
        streamingInto channel: LanguageModelExecutorGenerationChannel
    ) async throws {
        guard let schema = request.schema else {
            throw SystemOneError.structuredOutputRequired
        }

        // 1. Extract context/prompt from transcript as state
        let stateText = extractState(from: request.transcript)

        // 2. Extract active-turn image attachments if vision is supported
        let images: [SystemOneImage]?
        if configuration.supportsVision {
            let extracted = try TranscriptAttachmentExtractor.extractImages(from: request.transcript)
            images = extracted.isEmpty ? nil : extracted
        } else {
            images = nil
        }

        // 3. Translate schema into System One questions (noul / choice / score)
        let translation = try translator.translate(schema)

        // 4. Dispatch to System One backend
        let systemOneRequest = SystemOneRequest(
            state: stateText,
            model: configuration.modelID,
            questions: translation.questions,
            images: images
        )

        let response = try await configuration.backend.evaluate(request: systemOneRequest)

        if configuration.requiresAllAnswers {
            for key in translation.questions.keys.sorted() {
                guard response.answers[key] != nil else {
                    throw SystemOneError.decodingError("Missing answer for expected question '\(key)'")
                }
            }
        }

        // 5. Synthesize payload matching expected @Generable shape
        let synthesizedText = try synthesizer.synthesize(
            answers: response.answers,
            layout: translation.layout
        )
        let entryID = UUID().uuidString
        let outputTokenCount = response.usage?.outputTokens ?? configuration.defaultOutputTokenCount

        // 6. Emit single-frame text for @Generable decoding
        await channel.send(.response(
            entryID: entryID,
            action: .appendText(synthesizedText, tokenCount: outputTokenCount)
        ))

        // 7. Emit metadata with probabilities, confidence scores, and score rubric values
        var metadata: [String: GeneratedContent] = [
            "model": GeneratedContent(response.model)
        ]

        if configuration.emitsOutputTokensMetadata {
            metadata["output_tokens"] = GeneratedContent(String(outputTokenCount))
        }

        if let serverDurationMs = response.serverDurationMs {
            metadata["serverDurationMs"] = GeneratedContent(String(format: "%.1f", serverDurationMs))
        }
        if let transportDurationMs = response.transportDurationMs {
            metadata["transportDurationMs"] = GeneratedContent(String(format: "%.1f", transportDurationMs))
        }

        if let probabilitiesJSON = synthesizer.extractProbabilitiesJSON(from: response.answers) {
            metadata["probabilities"] = (try? GeneratedContent(json: probabilitiesJSON)) ?? GeneratedContent(probabilitiesJSON)
        }
        if let confidenceJSON = synthesizer.extractConfidenceJSON(from: response.answers) {
            metadata["confidence"] = (try? GeneratedContent(json: confidenceJSON)) ?? GeneratedContent(confidenceJSON)
        }
        if let scoresJSON = synthesizer.extractScoresJSON(from: response.answers, layout: translation.layout) {
            metadata["scores"] = (try? GeneratedContent(json: scoresJSON)) ?? GeneratedContent(scoresJSON)
        }

        await channel.send(.response(entryID: entryID, action: .updateMetadata(metadata)))

        // 8. Emit token usage
        if let usage = response.usage {
            await channel.send(.response(
                entryID: entryID,
                action: .updateUsage(
                    input: .init(totalTokenCount: usage.inputTokens, cachedTokenCount: 0),
                    output: .init(totalTokenCount: usage.outputTokens, reasoningTokenCount: 0)
                )
            ))
        } else if configuration.alwaysEmitUsage {
            await channel.send(.response(
                entryID: entryID,
                action: .updateUsage(
                    input: .init(totalTokenCount: 0, cachedTokenCount: 0),
                    output: .init(totalTokenCount: outputTokenCount, reasoningTokenCount: 0)
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
                    if case .text(let textSegment) = segment {
                        parts.append(textSegment.content)
                    }
                }
            case .prompt(let prompt):
                for segment in prompt.segments {
                    if case .text(let textSegment) = segment {
                        parts.append(textSegment.content)
                    }
                }
            case .response(let response):
                for segment in response.segments {
                    if case .text(let textSegment) = segment {
                        parts.append(textSegment.content)
                    }
                }
            default:
                break
            }
        }

        let combined = parts.joined(separator: "\n\n").trimmingCharacters(in: .whitespacesAndNewlines)
        return combined.isEmpty ? configuration.emptyStateFallback : combined
    }
}
