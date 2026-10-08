import Testing
import Foundation
@testable import OpenAIFoundationModels

@Suite("OpenAI Decisions Wire DTO Tests")
struct OpenAIDecisionsWireDTOTests {

    @Test("OpenAIDecisionsRequest with text input round-trips via JSON")
    func testTextRequestRoundTrip() throws {
        let question = OpenAIDecisionsQuestion(
            type: "predicate",
            name: "isSpam",
            instructions: "Determine if message is spam"
        )
        let request = OpenAIDecisionsRequest(
            model: "gpt-6-luna",
            input: .text("Hello world"),
            questions: [question]
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(request)
        let decoded = try JSONDecoder().decode(OpenAIDecisionsRequest.self, from: data)

        #expect(decoded.model == "gpt-6-luna")
        if case .text(let prompt) = decoded.input {
            #expect(prompt == "Hello world")
        } else {
            Issue.record("Expected .text input")
        }
        #expect(decoded.questions.count == 1)
        #expect(decoded.questions[0].name == "isSpam")
        #expect(decoded.questions[0].type == "predicate")
    }

    @Test("OpenAIDecisionsRequest with multimodal input round-trips via JSON")
    func testMultimodalRequestRoundTrip() throws {
        let contentBlocks: [OpenAIDecisionsRequest.InputPayload.ContentBlock] = [
            .inputText("Inspect this badge"),
            .inputImage(dataURL: "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==")
        ]
        let message = OpenAIDecisionsRequest.InputPayload.Message(role: "user", content: contentBlocks)
        let request = OpenAIDecisionsRequest(
            model: "gpt-6-luna",
            input: .multimodal([message]),
            questions: [
                OpenAIDecisionsQuestion(
                    type: "choice",
                    name: "badgeType",
                    instructions: "Select badge type",
                    choices: [
                        .init(value: "visitor", description: "Temporary visitor pass"),
                        .init(value: "contractor", description: "Contractor badge")
                    ]
                )
            ]
        )

        let data = try JSONEncoder().encode(request)
        let decoded = try JSONDecoder().decode(OpenAIDecisionsRequest.self, from: data)

        #expect(decoded.model == "gpt-6-luna")
        if case .multimodal(let messages) = decoded.input {
            #expect(messages.count == 1)
            #expect(messages[0].content.count == 2)
            if case .inputText(let t) = messages[0].content[0] {
                #expect(t == "Inspect this badge")
            } else {
                Issue.record("Expected inputText")
            }
            if case .inputImage(let url) = messages[0].content[1] {
                #expect(url.hasPrefix("data:image/png;base64,"))
            } else {
                Issue.record("Expected inputImage")
            }
        } else {
            Issue.record("Expected .multimodal input")
        }
    }

    @Test("OpenAIDecisionsResponse decodes predicate, choice, and score answers with zero output tokens")
    func testResponseDecoding() throws {
        let json = """
        {
          "id": "dec-901824",
          "object": "decision",
          "model": "gpt-6-luna",
          "answers": [
            {
              "name": "isFraudulent",
              "type": "predicate",
              "probability": 0.884,
              "confidence": 0.884
            },
            {
              "name": "ticketCategory",
              "type": "choice",
              "choice": "billing",
              "confidence": 0.945,
              "probabilities": [
                { "value": "billing", "probability": 0.945 },
                { "value": "technical", "probability": 0.055 }
              ]
            },
            {
              "name": "riskLevel",
              "type": "score",
              "score": 4.25,
              "confidence": 0.91,
              "probabilities": [
                { "value": 1, "label": "Low", "probability": 0.02 },
                { "value": 2, "label": "Medium", "probability": 0.08 },
                { "value": 3, "label": "High", "probability": 0.20 },
                { "value": 4, "label": "Critical", "probability": 0.70 }
              ]
            }
          ],
          "usage": {
            "input_tokens": 140,
            "output_tokens": 0
          }
        }
        """.data(using: .utf8)!

        let response = try JSONDecoder().decode(OpenAIDecisionsResponse.self, from: json)
        #expect(response.id == "dec-901824")
        #expect(response.model == "gpt-6-luna")
        #expect(response.answers.count == 3)
        #expect(response.usage?.inputTokens == 140)
        #expect(response.usage?.outputTokens == 0)

        // Predicate
        let fraudAnswer = try #require(response.answers.first(where: { $0.name == "isFraudulent" }))
        #expect(fraudAnswer.probability == 0.884)

        // Choice
        let catAnswer = try #require(response.answers.first(where: { $0.name == "ticketCategory" }))
        #expect(catAnswer.choice == "billing")
        #expect(catAnswer.confidence == 0.945)
        #expect(catAnswer.probabilities?.count == 2)

        // Score
        let scoreAnswer = try #require(response.answers.first(where: { $0.name == "riskLevel" }))
        #expect(scoreAnswer.score == 4.25)
        #expect(scoreAnswer.confidence == 0.91)
        #expect(scoreAnswer.probabilities?.count == 4)
        #expect(scoreAnswer.probabilities?[0].value == "1")
        #expect(scoreAnswer.probabilities?[0].label == "Low")
    }

    @Test("OpenAIDecisionsAnswer decodes refusal structure")
    func testRefusalDecoding() throws {
        let json = """
        {
          "name": "sensitiveQuery",
          "type": "refusal",
          "refusal": "Request flagged by OpenAI safety filter."
        }
        """.data(using: .utf8)!

        let answer = try JSONDecoder().decode(OpenAIDecisionsAnswer.self, from: json)
        #expect(answer.name == "sensitiveQuery")
        #expect(answer.type == "refusal")
        #expect(answer.refusal == "Request flagged by OpenAI safety filter.")
    }

    @Test("OpenAIErrorEnvelope decodes standard error responses")
    func testErrorEnvelopeDecoding() throws {
        let json = """
        {
          "error": {
            "message": "Invalid API key provided",
            "type": "invalid_request_error",
            "param": null,
            "code": "invalid_api_key"
          }
        }
        """.data(using: .utf8)!

        let envelope = try JSONDecoder().decode(OpenAIErrorEnvelope.self, from: json)
        #expect(envelope.error?.message == "Invalid API key provided")
        #expect(envelope.error?.code == "invalid_api_key")
        #expect(envelope.error?.type == "invalid_request_error")
    }

    @Test("OpenAIDecisionsResponse decodes resiliently when optional fields are omitted")
    func testResilientResponseDecodingWithMissingFields() throws {
        let json = "{}".data(using: .utf8)!
        let response = try JSONDecoder().decode(OpenAIDecisionsResponse.self, from: json)

        #expect(response.id == nil)
        #expect(response.object == nil)
        #expect(response.model == "gpt-6-luna")
        #expect(response.answers.isEmpty)
        #expect(response.usage == nil)
    }

    @Test("OpenAIDecisionsResponse.Usage decodes resiliently with missing fields")
    func testResilientUsageDecoding() throws {
        let json = "{}".data(using: .utf8)!
        let usage = try JSONDecoder().decode(OpenAIDecisionsResponse.Usage.self, from: json)

        #expect(usage.inputTokens == 0)
        #expect(usage.outputTokens == 0)
    }

    @Test("OpenAIDecisionsAnswer decodes flexible types for choice, score, probability, and probabilities dictionary")
    func testFlexibleAnswerDecoding() throws {
        let json = """
        {
          "model": "gpt-6-luna",
          "answers": [
            {
              "name": "choiceFromInt",
              "choice": 42
            },
            {
              "name": "choiceFromBool",
              "choice": true
            },
            {
              "name": "choiceFromDouble",
              "choice": 3.14
            },
            {
              "name": "scoreFromInt",
              "score": 5
            },
            {
              "name": "probabilityFromInt",
              "probability": 1
            },
            {
              "name": "probabilitiesFromDict",
              "choice": "inbox",
              "probabilities": {
                "inbox": 0.95,
                "spam": 0.05
              }
            }
          ]
        }
        """.data(using: .utf8)!

        let response = try JSONDecoder().decode(OpenAIDecisionsResponse.self, from: json)
        #expect(response.answers.count == 6)

        let choiceInt = try #require(response.answers.first(where: { $0.name == "choiceFromInt" }))
        #expect(choiceInt.choice == "42")

        let choiceBool = try #require(response.answers.first(where: { $0.name == "choiceFromBool" }))
        #expect(choiceBool.choice == "true")

        let choiceDouble = try #require(response.answers.first(where: { $0.name == "choiceFromDouble" }))
        #expect(choiceDouble.choice == "3.14")

        let scoreInt = try #require(response.answers.first(where: { $0.name == "scoreFromInt" }))
        #expect(scoreInt.score == 5.0)

        let probInt = try #require(response.answers.first(where: { $0.name == "probabilityFromInt" }))
        #expect(probInt.probability == 1.0)

        let probDict = try #require(response.answers.first(where: { $0.name == "probabilitiesFromDict" }))
        #expect(probDict.probabilities?.count == 2)
        #expect(probDict.probabilities?.contains(where: { $0.value == "inbox" && $0.probability == 0.95 }) == true)
        #expect(probDict.probabilities?.contains(where: { $0.value == "spam" && $0.probability == 0.05 }) == true)
    }
}
