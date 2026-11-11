import Testing
import Foundation
@testable import GeminiFoundationModels

@Suite("Google Gemini Decisions Wire DTO Tests")
struct GeminiDecisionsWireDTOTests {

    @Test("GeminiDecisionsRequest with text input round-trips via JSON")
    func testTextRequestRoundTrip() throws {
        let question = GeminiDecisionsQuestion(
            type: "noul",
            instructions: "Determine if message is spam"
        )
        let request = GeminiDecisionsRequest(
            model: "gemini-decision-1",
            input: .text("Hello world"),
            questions: ["isSpam": question]
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(request)
        let decoded = try JSONDecoder().decode(GeminiDecisionsRequest.self, from: data)

        #expect(decoded.model == "gemini-decision-1")
        if case .text(let prompt) = decoded.input {
            #expect(prompt == "Hello world")
        } else {
            Issue.record("Expected .text input")
        }
        #expect(decoded.questions.count == 1)
        #expect(decoded.questions["isSpam"]?.type == "noul")
        #expect(decoded.questions["isSpam"]?.instructions == "Determine if message is spam")
    }

    @Test("GeminiDecisionsRequest with multimodal parts and inline_data round-trips via JSON")
    func testMultimodalRequestRoundTrip() throws {
        let parts: [GeminiDecisionsRequest.InputPayload.Part] = [
            .text("Inspect this badge"),
            .inlineData(
                mimeType: "image/png",
                data: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg=="
            )
        ]
        let contentItem = GeminiDecisionsRequest.InputPayload.ContentItem(role: "user", parts: parts)
        let request = GeminiDecisionsRequest(
            model: "gemini-decision-1",
            input: .multimodal([contentItem]),
            questions: [
                "badgeType": GeminiDecisionsQuestion(
                    type: "choice",
                    instructions: "Select badge type",
                    criteria: .choice([
                        "visitor": "Temporary visitor pass",
                        "contractor": "Contractor badge"
                    ])
                )
            ]
        )

        let data = try JSONEncoder().encode(request)
        let decoded = try JSONDecoder().decode(GeminiDecisionsRequest.self, from: data)

        #expect(decoded.model == "gemini-decision-1")
        if case .multimodal(let items) = decoded.input {
            #expect(items.count == 1)
            #expect(items[0].role == "user")
            #expect(items[0].parts.count == 2)
            if case .text(let t) = items[0].parts[0] {
                #expect(t == "Inspect this badge")
            } else {
                Issue.record("Expected text part")
            }
            if case .inlineData(let mimeType, let b64) = items[0].parts[1] {
                #expect(mimeType == "image/png")
                #expect(b64.hasPrefix("iVBORw0KGgo"))
                #expect(!b64.hasPrefix("data:"))
            } else {
                Issue.record("Expected inlineData part")
            }
        } else {
            Issue.record("Expected .multimodal input")
        }
    }

    @Test("GeminiDecisionsQuestion criteria supports noul, choice, score, and flexible choices/levels keys")
    func testQuestionCriteriaVariants() throws {
        let noulQ = GeminiDecisionsQuestion(
            type: "noul",
            instructions: "Has tax ID?",
            criteria: .noul(trueDescription: "Tax ID visible", falseDescription: "No Tax ID")
        )
        let noulData = try JSONEncoder().encode(noulQ)
        let decodedNoul = try JSONDecoder().decode(GeminiDecisionsQuestion.self, from: noulData)
        #expect(decodedNoul.criteria == .noul(trueDescription: "Tax ID visible", falseDescription: "No Tax ID"))

        let choiceJSON = """
        {
          "type": "choice",
          "instructions": "Pick one",
          "choices": ["alpha", "beta"]
        }
        """.data(using: .utf8)!
        let decodedChoice = try JSONDecoder().decode(GeminiDecisionsQuestion.self, from: choiceJSON)
        #expect(decodedChoice.criteria == .choice(["alpha": "alpha", "beta": "beta"]))

        let scoreJSON = """
        {
          "type": "score",
          "instructions": "Rate severity",
          "levels": ["Low", "Medium", "High"]
        }
        """.data(using: .utf8)!
        let decodedScore = try JSONDecoder().decode(GeminiDecisionsQuestion.self, from: scoreJSON)
        #expect(decodedScore.criteria == .score(["Low", "Medium", "High"]))
    }

    @Test("GeminiDecisionsResponse decodes noul, choice, and score answers with usage and usageMetadata")
    func testResponseDecoding() throws {
        let json = """
        {
          "id": "gem-dec-901824",
          "model": "gemini-decision-1",
          "answers": {
            "isFraudulent": {
              "type": "noul",
              "noul": 0.884,
              "confidence": 0.92
            },
            "ticketCategory": {
              "type": "choice",
              "choice": "billing",
              "confidence": 0.945,
              "probabilities": {
                "billing": 0.945,
                "technical": 0.055
              }
            },
            "riskLevel": {
              "type": "score",
              "score": 2.4,
              "confidence": 0.91,
              "probabilities": {
                "0": 0.02,
                "1": 0.08,
                "2": 0.40,
                "3": 0.50
              },
              "legend": {
                "0": "Low",
                "1": "Medium",
                "2": "High",
                "3": "Critical"
              }
            }
          },
          "usage": {
            "input_tokens": 140,
            "output_tokens": 0
          }
        }
        """.data(using: .utf8)!

        let response = try JSONDecoder().decode(GeminiDecisionsResponse.self, from: json)
        #expect(response.id == "gem-dec-901824")
        #expect(response.model == "gemini-decision-1")
        #expect(response.answers.count == 3)
        #expect(response.usage?.inputTokens == 140)
        #expect(response.usage?.outputTokens == 0)
        #expect(response.resolvedUsage?.inputTokens == 140)
        #expect(response.resolvedUsage?.outputTokens == 0)

        // Noul
        let fraudAnswer = try #require(response.answers["isFraudulent"])
        #expect(fraudAnswer.noul == 0.884)
        #expect(fraudAnswer.probability == 0.884)
        #expect(fraudAnswer.confidence == 0.92)

        // Choice
        let catAnswer = try #require(response.answers["ticketCategory"])
        #expect(catAnswer.choice == "billing")
        #expect(catAnswer.selected == "billing")
        #expect(catAnswer.confidence == 0.945)
        #expect(catAnswer.probabilities?["billing"] == 0.945)

        // Score
        let scoreAnswer = try #require(response.answers["riskLevel"])
        #expect(scoreAnswer.score == 2.4)
        #expect(scoreAnswer.confidence == 0.91)
        #expect(scoreAnswer.probabilities?["3"] == 0.50)
        #expect(scoreAnswer.legend?["3"] == "Critical")
    }

    @Test("GeminiDecisionsResponse decodes usageMetadata when usage is omitted")
    func testUsageMetadataDecoding() throws {
        let json = """
        {
          "modelVersion": "gemini-decision-1",
          "answers": {
            "isSafe": {
              "type": "noul",
              "probability": 0.97
            }
          },
          "usageMetadata": {
            "promptTokenCount": 215,
            "candidatesTokenCount": 0,
            "totalTokenCount": 215
          }
        }
        """.data(using: .utf8)!

        let response = try JSONDecoder().decode(GeminiDecisionsResponse.self, from: json)
        #expect(response.model == "gemini-decision-1")
        #expect(response.usageMetadata?.promptTokenCount == 215)
        #expect(response.usageMetadata?.candidatesTokenCount == 0)
        #expect(response.usageMetadata?.totalTokenCount == 215)
        #expect(response.resolvedUsage?.inputTokens == 215)
        #expect(response.resolvedUsage?.outputTokens == 0)
        #expect(response.answers["isSafe"]?.noul == 0.97)
        #expect(response.answers["isSafe"]?.probability == 0.97)
    }

    @Test("GeminiDecisionsAnswer decodes refusal structure")
    func testRefusalDecoding() throws {
        let json = """
        {
          "type": "refusal",
          "refusal": "Request flagged by Google Gemini safety filter."
        }
        """.data(using: .utf8)!

        let answer = try JSONDecoder().decode(GeminiDecisionsAnswer.self, from: json)
        #expect(answer.type == "refusal")
        #expect(answer.refusal == "Request flagged by Google Gemini safety filter.")
    }

    @Test("GeminiErrorEnvelope decodes standard Google RPC error responses")
    func testErrorEnvelopeDecoding() throws {
        let json = """
        {
          "error": {
            "code": 400,
            "message": "API key not valid. Please pass a valid API key.",
            "status": "INVALID_ARGUMENT"
          }
        }
        """.data(using: .utf8)!

        let envelope = try JSONDecoder().decode(GeminiErrorEnvelope.self, from: json)
        #expect(envelope.error?.code == 400)
        #expect(envelope.error?.message == "API key not valid. Please pass a valid API key.")
        #expect(envelope.error?.status == "INVALID_ARGUMENT")
    }

    @Test("GeminiDecisionsResponse decodes resiliently when optional fields are omitted")
    func testResilientResponseDecodingWithMissingFields() throws {
        let json = "{}".data(using: .utf8)!
        let response = try JSONDecoder().decode(GeminiDecisionsResponse.self, from: json)

        #expect(response.id == nil)
        #expect(response.model == "gemini-decision-1")
        #expect(response.answers.isEmpty)
        #expect(response.usage == nil)
        #expect(response.usageMetadata == nil)
        #expect(response.resolvedUsage == nil)
    }

    @Test("GeminiDecisionsAnswer decodes flexible types for choice/selected, score, noul/probability, and array probabilities")
    func testFlexibleAnswerDecoding() throws {
        let json = """
        {
          "model": "gemini-decision-1",
          "answers": {
            "choiceFromSelected": {
              "selected": "enterprise"
            },
            "choiceFromInt": {
              "choice": 42
            },
            "choiceFromBool": {
              "choice": true
            },
            "scoreFromInt": {
              "score": 4,
              "probabilities": [0.05, 0.10, 0.15, 0.20, 0.50],
              "legend": ["L0", "L1", "L2", "L3", "L4"]
            },
            "probabilityFromAlias": {
              "probability": 0.85
            },
            "probabilitiesFromArrayObjects": {
              "choice": "inbox",
              "probabilities": [
                { "value": "inbox", "probability": 0.95, "label": "Primary Inbox" },
                { "value": "spam", "probability": 0.05, "label": "Spam Folder" }
              ]
            }
          }
        }
        """.data(using: .utf8)!

        let response = try JSONDecoder().decode(GeminiDecisionsResponse.self, from: json)
        #expect(response.answers.count == 6)

        let choiceSelected = try #require(response.answers["choiceFromSelected"])
        #expect(choiceSelected.choice == "enterprise")
        #expect(choiceSelected.selected == "enterprise")

        let choiceInt = try #require(response.answers["choiceFromInt"])
        #expect(choiceInt.choice == "42")

        let choiceBool = try #require(response.answers["choiceFromBool"])
        #expect(choiceBool.choice == "true")

        let scoreInt = try #require(response.answers["scoreFromInt"])
        #expect(scoreInt.score == 4.0)
        #expect(scoreInt.probabilities?["4"] == 0.50)
        #expect(scoreInt.legend?["4"] == "L4")

        let probAlias = try #require(response.answers["probabilityFromAlias"])
        #expect(probAlias.noul == 0.85)
        #expect(probAlias.probability == 0.85)

        let probArray = try #require(response.answers["probabilitiesFromArrayObjects"])
        #expect(probArray.probabilities?["inbox"] == 0.95)
        #expect(probArray.probabilities?["spam"] == 0.05)
        #expect(probArray.legend?["inbox"] == "Primary Inbox")
    }
}
