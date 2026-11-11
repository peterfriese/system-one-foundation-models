import Foundation
import SystemOneCore

/// Bridges between unified `SystemOneRequest` / `SystemOneResponse` models and Google Gemini Decisions wire payloads.
///
/// See tech-notes/0018-gemini-decisions-api-architecture.md
public enum GeminiDecisionsPayloadAdapter {

    /// Translates a unified `SystemOneRequest` into a `GeminiDecisionsRequest`.
    public static func adaptRequest(_ request: SystemOneRequest) throws -> GeminiDecisionsRequest {
        let inputPayload: GeminiDecisionsRequest.InputPayload

        if let images = request.images, !images.isEmpty {
            // Validate all image attachments meet Gemini Decisions constraints
            try GeminiDecisionsAttachmentValidator.validate(attachments: images)

            var parts: [GeminiDecisionsRequest.InputPayload.Part] = [
                .text(request.state)
            ]
            for image in images {
                parts.append(
                    .inlineData(
                        mimeType: image.format.rawValue,
                        data: image.base64DataString
                    )
                )
            }
            inputPayload = .multimodal([
                GeminiDecisionsRequest.InputPayload.ContentItem(role: "user", parts: parts)
            ])
        } else {
            inputPayload = .text(request.state)
        }

        var geminiQuestions: [String: GeminiDecisionsQuestion] = [:]
        for (name, q) in request.questions {
            switch q {
            case .noul(let instructions):
                geminiQuestions[name] = GeminiDecisionsQuestion(
                    type: "noul",
                    instructions: instructions
                )

            case .choice(let instructions, let criteria):
                geminiQuestions[name] = GeminiDecisionsQuestion(
                    type: "choice",
                    instructions: instructions,
                    criteria: .choice(criteria)
                )

            case .score(let instructions, let criteria):
                let levels = criteria.isEmpty
                    ? (1...5).map { "Level \($0): Rating score \($0)" }
                    : criteria
                geminiQuestions[name] = GeminiDecisionsQuestion(
                    type: "score",
                    instructions: instructions,
                    criteria: .score(levels)
                )
            }
        }

        let model = (request.model.isEmpty || request.model == "systemone-default")
            ? GeminiDecisionsEndpoint.defaultModel
            : request.model

        return GeminiDecisionsRequest(
            model: model,
            input: inputPayload,
            questions: geminiQuestions
        )
    }

    /// Adapts a `GeminiDecisionsResponse` into a unified `SystemOneResponse`.
    public static func adaptResponse(
        _ geminiResponse: GeminiDecisionsResponse,
        expectedQuestionNames: Set<String>? = nil,
        transportDurationMs: Double? = nil,
        serverDurationMs: Double? = nil
    ) throws -> SystemOneResponse {
        guard !geminiResponse.answers.isEmpty else {
            if let firstExpected = expectedQuestionNames?.sorted().first {
                throw SystemOneError.decodingError("Missing answer for expected question '\(firstExpected)'")
            }
            throw SystemOneError.decodingError("Missing answers in Gemini Decisions response: answers dictionary is empty")
        }

        var answers: [String: SystemOneAnswer] = [:]

        for (name, ans) in geminiResponse.answers {
            // Check for safety refusal
            if ans.type == "refusal" || ans.refusal != nil {
                let reason = ans.refusal ?? "Content blocked by Google Gemini safety policy"
                throw SystemOneError.safetyRefusal(reason: reason, questionName: name)
            }

            if let prob = ans.noul ?? ans.probability {
                let conf = ans.confidence ?? max(prob, 1.0 - prob)
                var probsDict: [String: Double] = [
                    "true": prob,
                    "false": max(0.0, 1.0 - prob)
                ]
                if let distribution = ans.probabilities {
                    for (k, v) in distribution {
                        probsDict[k] = v
                    }
                }
                answers[name] = SystemOneAnswer(
                    type: "noul",
                    noul: prob,
                    confidence: conf,
                    probabilities: probsDict
                )
            } else if let ch = ans.choice ?? ans.selected {
                let probsDict = ans.probabilities
                let conf = ans.confidence ?? probsDict?[ch] ?? 1.0
                answers[name] = SystemOneAnswer(
                    type: "choice",
                    choice: ch,
                    confidence: conf,
                    probabilities: probsDict
                )
            } else if let sc = ans.score {
                answers[name] = SystemOneAnswer(
                    type: "score",
                    score: sc,
                    confidence: ans.confidence ?? 1.0,
                    probabilities: ans.probabilities,
                    legend: ans.legend
                )
            } else {
                throw SystemOneError.decodingError("Unrecognized answer shape for question '\(name)': \(ans)")
            }
        }

        if let expectedQuestionNames {
            for key in expectedQuestionNames.sorted() {
                guard answers[key] != nil else {
                    throw SystemOneError.decodingError("Missing answer for expected question '\(key)'")
                }
            }
        }

        let resolvedUsage = geminiResponse.resolvedUsage
        let usage = SystemOneUsage(
            inputTokens: resolvedUsage?.inputTokens ?? 0,
            outputTokens: resolvedUsage?.outputTokens ?? 0
        )

        return SystemOneResponse(
            model: geminiResponse.model,
            answers: answers,
            usage: usage,
            serverDurationMs: serverDurationMs,
            transportDurationMs: transportDurationMs
        )
    }

    /// Adapts a `GeminiDecisionsResponse` into a unified `SystemOneResponse` with an array of expected question names.
    public static func adaptResponse(
        _ geminiResponse: GeminiDecisionsResponse,
        expectedQuestionNames: [String],
        transportDurationMs: Double? = nil,
        serverDurationMs: Double? = nil
    ) throws -> SystemOneResponse {
        try adaptResponse(
            geminiResponse,
            expectedQuestionNames: Set(expectedQuestionNames),
            transportDurationMs: transportDurationMs,
            serverDurationMs: serverDurationMs
        )
    }
}

/// Attachment validator enforcing Google Gemini Decisions multimodal constraints.
public enum GeminiDecisionsAttachmentValidator {
    /// Validates an array of image attachments against Gemini Decisions constraints.
    public static func validate(attachments: [SystemOneImage]) throws {
        for image in attachments {
            guard image.dataURL.hasPrefix("data:") && image.dataURL.contains(";base64,") else {
                throw SystemOneError.modelExecutionError(
                    "Gemini Decisions API requires inline base64 image data. Remote URLs and file references are unsupported."
                )
            }
        }
        try SystemOneImage.validate(images: attachments)
    }
}
