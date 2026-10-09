import Foundation
import SystemOneCore

/// Bridges between unified `SystemOneRequest` / `SystemOneResponse` models and OpenAI Decisions wire payloads.
public enum OpenAIDecisionsPayloadAdapter {

    /// Translates a unified `SystemOneRequest` into an `OpenAIDecisionsRequest`.
    public static func adaptRequest(_ request: SystemOneRequest) throws -> OpenAIDecisionsRequest {
        let inputPayload: OpenAIDecisionsRequest.InputPayload

        if let images = request.images, !images.isEmpty {
            // Validate all image attachments meet OpenAI Decisions constraints
            try OpenAIDecisionsAttachmentValidator.validate(attachments: images)

            var contentBlocks: [OpenAIDecisionsRequest.InputPayload.ContentBlock] = [
                .inputText(request.state)
            ]
            for image in images {
                contentBlocks.append(.inputImage(dataURL: image.dataURL))
            }
            inputPayload = .multimodal([
                OpenAIDecisionsRequest.InputPayload.Message(role: "user", content: contentBlocks)
            ])
        } else {
            inputPayload = .text(request.state)
        }

        var openAIQuestions: [OpenAIDecisionsQuestion] = []
        for (name, q) in request.questions.sorted(by: { $0.key < $1.key }) {
            switch q {
            case .noul(let instructions):
                openAIQuestions.append(OpenAIDecisionsQuestion(
                    type: "predicate",
                    name: name,
                    instructions: instructions
                ))

            case .choice(let instructions, let criteria):
                let choiceItems = criteria.sorted(by: { $0.key < $1.key }).map {
                    OpenAIDecisionsQuestion.ChoiceItem(value: $0.key, description: $0.value)
                }
                openAIQuestions.append(OpenAIDecisionsQuestion(
                    type: "choice",
                    name: name,
                    instructions: instructions,
                    choices: choiceItems
                ))

            case .score(let instructions, let criteria):
                let levels: [OpenAIDecisionsQuestion.LevelItem]
                if !criteria.isEmpty {
                    levels = criteria.map {
                        OpenAIDecisionsQuestion.LevelItem(label: $0, description: $0)
                    }
                } else {
                    levels = (1...5).map {
                        OpenAIDecisionsQuestion.LevelItem(label: "Level \($0)", description: "Rating score \($0)")
                    }
                }
                openAIQuestions.append(OpenAIDecisionsQuestion(
                    type: "score",
                    name: name,
                    instructions: instructions,
                    levels: levels
                ))
            }
        }

        let model = (request.model.isEmpty || request.model == "systemone-default") ? "gpt-6-luna" : request.model

        return OpenAIDecisionsRequest(
            model: model,
            input: inputPayload,
            questions: openAIQuestions
        )
    }

    /// Adapts an `OpenAIDecisionsResponse` into a unified `SystemOneResponse`.
    public static func adaptResponse(
        _ openAIResponse: OpenAIDecisionsResponse,
        expectedQuestionNames: Set<String>? = nil,
        transportDurationMs: Double? = nil,
        serverDurationMs: Double? = nil
    ) throws -> SystemOneResponse {
        guard !openAIResponse.answers.isEmpty else {
            if let firstExpected = expectedQuestionNames?.sorted().first {
                throw SystemOneError.decodingError("Missing answer for expected question '\(firstExpected)'")
            }
            throw SystemOneError.decodingError("Missing answers in OpenAI Decisions response: answers array is empty")
        }

        var answers: [String: SystemOneAnswer] = [:]

        for ans in openAIResponse.answers {
            // Check for safety refusal
            if ans.type == "refusal" || ans.refusal != nil {
                let reason = ans.refusal ?? "Content blocked by safety policy"
                throw SystemOneError.safetyRefusal(reason: reason, questionName: ans.name)
            }

            if let prob = ans.probability {
                // Predicate -> noul
                let conf = ans.confidence ?? max(prob, 1.0 - prob)
                var probsDict: [String: Double] = [
                    "true": prob,
                    "false": max(0.0, 1.0 - prob)
                ]
                if let distribution = ans.probabilities {
                    for entry in distribution {
                        probsDict[entry.value] = entry.probability
                    }
                }

                answers[ans.name] = SystemOneAnswer(
                    type: "noul",
                    noul: prob,
                    confidence: conf,
                    probabilities: probsDict
                )
            } else if let ch = ans.choice {
                // Choice -> choice
                var probsDict: [String: Double]? = nil
                if let probsList = ans.probabilities {
                    probsDict = Dictionary(
                        probsList.map { ($0.value, $0.probability) },
                        uniquingKeysWith: { current, _ in current }
                    )
                }
                let conf = ans.confidence ?? probsDict?[ch] ?? 1.0
                answers[ans.name] = SystemOneAnswer(
                    type: "choice",
                    choice: ch,
                    confidence: conf,
                    probabilities: probsDict
                )
            } else if let sc = ans.score {
                // Score -> score
                var probsDict: [String: Double]? = nil
                var legendDict: [String: String]? = nil
                if let probsList = ans.probabilities {
                    probsDict = Dictionary(
                        probsList.map { ($0.value, $0.probability) },
                        uniquingKeysWith: { current, _ in current }
                    )
                    legendDict = Dictionary(
                        probsList.compactMap {
                            guard let label = $0.label else { return nil }
                            return ($0.value, label)
                        },
                        uniquingKeysWith: { current, _ in current }
                    )
                }
                answers[ans.name] = SystemOneAnswer(
                    type: "score",
                    score: sc,
                    confidence: ans.confidence ?? 1.0,
                    probabilities: probsDict,
                    legend: legendDict
                )
            } else {
                throw SystemOneError.decodingError("Unrecognized answer shape for question '\(ans.name)': \(ans)")
            }
        }

        if let expectedQuestionNames {
            for key in expectedQuestionNames.sorted() {
                guard answers[key] != nil else {
                    throw SystemOneError.decodingError("Missing answer for expected question '\(key)'")
                }
            }
        }

        let usage = SystemOneUsage(
            inputTokens: openAIResponse.usage?.inputTokens ?? 0,
            outputTokens: openAIResponse.usage?.outputTokens ?? 0
        )

        return SystemOneResponse(
            model: openAIResponse.model,
            answers: answers,
            usage: usage,
            serverDurationMs: serverDurationMs,
            transportDurationMs: transportDurationMs
        )
    }

    /// Adapts an `OpenAIDecisionsResponse` into a unified `SystemOneResponse` with an array of expected question names.
    public static func adaptResponse(
        _ openAIResponse: OpenAIDecisionsResponse,
        expectedQuestionNames: [String],
        transportDurationMs: Double? = nil,
        serverDurationMs: Double? = nil
    ) throws -> SystemOneResponse {
        try adaptResponse(
            openAIResponse,
            expectedQuestionNames: Set(expectedQuestionNames),
            transportDurationMs: transportDurationMs,
            serverDurationMs: serverDurationMs
        )
    }
}

/// Attachment validator enforcing OpenAI Decisions constraints.
public enum OpenAIDecisionsAttachmentValidator {
    /// Validates an array of image attachments against OpenAI Decisions constraints.
    public static func validate(attachments: [SystemOneImage]) throws {
        for image in attachments {
            guard image.dataURL.hasPrefix("data:") && image.dataURL.contains(";base64,") else {
                throw SystemOneError.modelExecutionError(
                    "OpenAI Decisions API requires inline RFC 2397 base64 Data URLs. Hosted URLs and file_ids are unsupported."
                )
            }
        }
        try SystemOneImage.validate(images: attachments)
    }
}
