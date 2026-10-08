import Testing
import Foundation
import SystemOneCore
@testable import OpenAIFoundationModels

@Suite("OpenAI Decisions Payload Adapter Tests")
struct OpenAIDecisionsPayloadAdapterTests {

    @Test("Adapt Request: Translates noul, choice, and score to OpenAI wire format")
    func testAdaptRequest() throws {
        let questions: [String: SystemOneQuestion] = [
            "isUrgent": .noul(instructions: "Is this request urgent?"),
            "category": .choice(
                instructions: "Select ticket category",
                criteria: ["billing": "Billing inquiries", "tech": "Technical support"]
            ),
            "severity": .score(
                instructions: "Rate severity",
                criteria: ["Low", "Medium", "High"]
            )
        ]

        let request = SystemOneRequest(
            state: "Server CPU spike detected on node 4",
            model: "gpt-6-luna",
            questions: questions
        )

        let openAIRequest = try OpenAIDecisionsPayloadAdapter.adaptRequest(request)

        #expect(openAIRequest.model == "gpt-6-luna")
        if case .text(let prompt) = openAIRequest.input {
            #expect(prompt == "Server CPU spike detected on node 4")
        } else {
            Issue.record("Expected .text input")
        }

        #expect(openAIRequest.questions.count == 3)

        // Predicate question
        let predQ = try #require(openAIRequest.questions.first(where: { $0.name == "isUrgent" }))
        #expect(predQ.type == "predicate")
        #expect(predQ.instructions == "Is this request urgent?")

        // Choice question
        let choiceQ = try #require(openAIRequest.questions.first(where: { $0.name == "category" }))
        #expect(choiceQ.type == "choice")
        #expect(choiceQ.choices?.count == 2)
        #expect(choiceQ.choices?.contains(where: { $0.value == "billing" && $0.description == "Billing inquiries" }) == true)

        // Score question
        let scoreQ = try #require(openAIRequest.questions.first(where: { $0.name == "severity" }))
        #expect(scoreQ.type == "score")
        #expect(scoreQ.levels?.count == 3)
        #expect(scoreQ.levels?[0].label == "Low")
    }

    @Test("Adapt Request: Encodes images as multimodal base64 Data URLs")
    func testAdaptRequestWithImages() throws {
        let samplePNG = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
        let image = SystemOneImage(data: samplePNG, format: .png)

        let request = SystemOneRequest(
            state: "Inspect driver license photo",
            model: "gpt-6-luna",
            questions: [
                "isValid": .noul(instructions: "Is this valid?")
            ],
            images: [image]
        )

        let openAIRequest = try OpenAIDecisionsPayloadAdapter.adaptRequest(request)

        if case .multimodal(let messages) = openAIRequest.input {
            #expect(messages.count == 1)
            let content = messages[0].content
            #expect(content.count == 2)

            if case .inputText(let t) = content[0] {
                #expect(t == "Inspect driver license photo")
            } else {
                Issue.record("Expected inputText block")
            }

            if case .inputImage(let url) = content[1] {
                #expect(url.hasPrefix("data:image/png;base64,"))
            } else {
                Issue.record("Expected inputImage block")
            }
        } else {
            Issue.record("Expected multimodal payload")
        }
    }

    @Test("Adapt Response: Maps OpenAI answers back to SystemOneResponse answers")
    func testAdaptResponse() throws {
        let openAIResponse = OpenAIDecisionsResponse(
            id: "dec-1234",
            object: "decision",
            model: "gpt-6-luna",
            answers: [
                OpenAIDecisionsAnswer(
                    name: "isSpam",
                    type: "predicate",
                    probability: 0.92,
                    confidence: 0.92
                ),
                OpenAIDecisionsAnswer(
                    name: "dept",
                    type: "choice",
                    choice: "support",
                    confidence: 0.89,
                    probabilities: [
                        .init(value: "support", probability: 0.89),
                        .init(value: "sales", probability: 0.11)
                    ]
                ),
                OpenAIDecisionsAnswer(
                    name: "priority",
                    type: "score",
                    score: 3.5,
                    confidence: 0.85,
                    probabilities: [
                        .init(value: "1", probability: 0.05, label: "Low"),
                        .init(value: "2", probability: 0.10, label: "Medium"),
                        .init(value: "3", probability: 0.85, label: "High")
                    ]
                )
            ],
            usage: .init(inputTokens: 95, outputTokens: 0)
        )

        let adapted = try OpenAIDecisionsPayloadAdapter.adaptResponse(
            openAIResponse,
            transportDurationMs: 45.0,
            serverDurationMs: 38.0
        )

        #expect(adapted.model == "gpt-6-luna")
        #expect(adapted.transportDurationMs == 45.0)
        #expect(adapted.serverDurationMs == 38.0)
        #expect(adapted.usage?.inputTokens == 95)
        #expect(adapted.usage?.outputTokens == 0)

        // Predicate / noul
        let spamAnswer = try #require(adapted.answers["isSpam"])
        #expect(spamAnswer.type == "noul")
        #expect(spamAnswer.noul == 0.92)
        #expect(spamAnswer.confidence == 0.92)

        // Choice
        let deptAnswer = try #require(adapted.answers["dept"])
        #expect(deptAnswer.type == "choice")
        #expect(deptAnswer.choice == "support")
        #expect(deptAnswer.confidence == 0.89)
        #expect(deptAnswer.probabilities?["support"] == 0.89)

        // Score
        let priorityAnswer = try #require(adapted.answers["priority"])
        #expect(priorityAnswer.type == "score")
        #expect(priorityAnswer.score == 3.5)
        #expect(priorityAnswer.confidence == 0.85)
        #expect(priorityAnswer.legend?["3"] == "High")
    }

    @Test("Adapt Response: Throws safetyRefusal when safety refusal is present")
    func testAdaptResponseWithRefusalThrows() throws {
        let openAIResponse = OpenAIDecisionsResponse(
            id: "dec-refusal",
            model: "gpt-6-luna",
            answers: [
                OpenAIDecisionsAnswer(
                    name: "exploitDetection",
                    type: "refusal",
                    refusal: "Content violates OpenAI safety policy regarding cyber attacks."
                )
            ],
            usage: .init(inputTokens: 30, outputTokens: 0)
        )

        do {
            _ = try OpenAIDecisionsPayloadAdapter.adaptResponse(openAIResponse)
            Issue.record("Expected safetyRefusal error")
        } catch let error as SystemOneError {
            if case .safetyRefusal(let reason, let questionName) = error {
                #expect(questionName == "exploitDetection")
                #expect(reason.contains("safety policy"))
            } else {
                Issue.record("Expected .safetyRefusal, got: \(error)")
            }
        }
    }

    @Test("Adapt Response: Throws decodingError for absent or empty answers array")
    func testAdaptResponseWithAbsentAnswersThrows() throws {
        let openAIResponse = OpenAIDecisionsResponse(
            id: "dec-empty",
            model: "gpt-6-luna",
            answers: [],
            usage: .init(inputTokens: 10, outputTokens: 0)
        )

        do {
            _ = try OpenAIDecisionsPayloadAdapter.adaptResponse(openAIResponse)
            Issue.record("Expected decodingError for empty answers array")
        } catch let error as SystemOneError {
            if case .decodingError(let message) = error {
                #expect(message.contains("no answers") || message.contains("Missing answers"))
            } else {
                Issue.record("Expected .decodingError, got: \(error)")
            }
        }
    }

    @Test("Adapt Response: Throws decodingError for partial answer array when expected questions are provided")
    func testAdaptResponseWithPartialAnswersThrows() throws {
        let openAIResponse = OpenAIDecisionsResponse(
            id: "dec-partial",
            model: "gpt-6-luna",
            answers: [
                OpenAIDecisionsAnswer(
                    name: "isUrgent",
                    type: "predicate",
                    probability: 0.95,
                    confidence: 0.95
                )
            ],
            usage: .init(inputTokens: 25, outputTokens: 0)
        )

        let expected = ["category", "isUrgent", "severity"]

        do {
            _ = try OpenAIDecisionsPayloadAdapter.adaptResponse(openAIResponse, expectedQuestionNames: expected)
            Issue.record("Expected decodingError for missing expected answers")
        } catch let error as SystemOneError {
            if case .decodingError(let message) = error {
                #expect(message == "Missing answer for expected question 'category'")
            } else {
                Issue.record("Expected .decodingError, got: \(error)")
            }
        }
    }

    @Test("Adapt Response: Handles duplicate keys in choice and score probabilities defensively without crashing")
    func testAdaptResponseWithDuplicateKeysDoesNotCrash() throws {
        let openAIResponse = OpenAIDecisionsResponse(
            id: "dec-dup",
            object: "decision",
            model: "gpt-6-luna",
            answers: [
                OpenAIDecisionsAnswer(
                    name: "category",
                    type: "choice",
                    choice: "support",
                    confidence: 0.8,
                    probabilities: [
                        .init(value: "support", probability: 0.8),
                        .init(value: "support", probability: 0.79), // Duplicate key
                        .init(value: "sales", probability: 0.2)
                    ]
                ),
                OpenAIDecisionsAnswer(
                    name: "rating",
                    type: "score",
                    score: 4.0,
                    confidence: 0.9,
                    probabilities: [
                        .init(value: "4", probability: 0.85, label: "Good"),
                        .init(value: "4", probability: 0.84, label: "Good"), // Duplicate key
                        .init(value: "5", probability: 0.15, label: "Excellent")
                    ]
                )
            ],
            usage: .init(inputTokens: 20, outputTokens: 0)
        )

        let adapted = try OpenAIDecisionsPayloadAdapter.adaptResponse(openAIResponse)
        #expect(adapted.answers["category"]?.probabilities?["support"] == 0.8)
        #expect(adapted.answers["rating"]?.probabilities?["Good"] == 0.85)
        #expect(adapted.answers["rating"]?.legend?["4"] == "Good")
    }
}
