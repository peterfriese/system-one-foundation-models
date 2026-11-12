import Testing
import Foundation
import SystemOneCore
@testable import GeminiFoundationModels

@Suite("Google Gemini Decisions Payload Adapter Tests")
struct GeminiDecisionsPayloadAdapterTests {

    @Test("Adapt Request: Translates noul, choice, and score to Gemini dictionary wire format")
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
            model: "gemini-decision-1",
            questions: questions
        )

        let geminiRequest = try GeminiDecisionsPayloadAdapter.adaptRequest(request)

        #expect(geminiRequest.model == "gemini-decision-1")
        if case .text(let prompt) = geminiRequest.input {
            #expect(prompt == "Server CPU spike detected on node 4")
        } else {
            Issue.record("Expected .text input")
        }

        #expect(geminiRequest.questions.count == 3)

        // Noul question
        let noulQ = try #require(geminiRequest.questions["isUrgent"])
        #expect(noulQ.type == "noul")
        #expect(noulQ.instructions == "Is this request urgent?")
        #expect(noulQ.criteria == nil)

        // Choice question
        let choiceQ = try #require(geminiRequest.questions["category"])
        #expect(choiceQ.type == "choice")
        #expect(choiceQ.criteria == .choice(["billing": "Billing inquiries", "tech": "Technical support"]))

        // Score question
        let scoreQ = try #require(geminiRequest.questions["severity"])
        #expect(scoreQ.type == "score")
        #expect(scoreQ.criteria == .score(["Low", "Medium", "High"]))
    }

    @Test("Adapt Request: Encodes images as flat multimodal typed ContentItem array (raw Base64 without data: prefix)")
    func testAdaptRequestWithImages() throws {
        var samplePNG = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
        samplePNG.append(contentsOf: [0x00, 0x00, 0x00, 0x0D]) // IHDR length
        samplePNG.append(contentsOf: [0x49, 0x48, 0x44, 0x52]) // "IHDR"
        let width: UInt32 = 100
        let height: UInt32 = 100
        withUnsafeBytes(of: width.bigEndian) { samplePNG.append(contentsOf: $0) }
        withUnsafeBytes(of: height.bigEndian) { samplePNG.append(contentsOf: $0) }
        samplePNG.append(contentsOf: [0x08, 0x06, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00])
        let image = SystemOneImage(data: samplePNG, format: .png)

        let request = SystemOneRequest(
            state: "Inspect driver license photo",
            model: "gemini-decision-1",
            questions: [
                "isValid": .noul(instructions: "Is this valid?")
            ],
            images: [image]
        )

        let geminiRequest = try GeminiDecisionsPayloadAdapter.adaptRequest(request)

        if case .multimodal(let items) = geminiRequest.input {
            #expect(items.count == 2)

            if case .text(let t) = items[0] {
                #expect(t == "Inspect driver license photo")
            } else {
                Issue.record("Expected text content item")
            }

            if case .image(let mimeType, let b64) = items[1] {
                #expect(mimeType == "image/png")
                #expect(!b64.hasPrefix("data:"))
                #expect(Data(base64Encoded: b64) == samplePNG)
            } else {
                Issue.record("Expected image content item")
            }
        } else {
            Issue.record("Expected multimodal payload")
        }
    }

    @Test("Adapt Response: Maps Gemini answers back to SystemOneResponse answers")
    func testAdaptResponse() throws {
        let geminiResponse = GeminiDecisionsResponse(
            id: "gem-dec-1234",
            model: "gemini-decision-1",
            answers: [
                "isSpam": GeminiDecisionsAnswer(
                    type: "noul",
                    noul: 0.92,
                    confidence: 0.92
                ),
                "dept": GeminiDecisionsAnswer(
                    type: "choice",
                    choice: "support",
                    confidence: 0.89,
                    probabilities: [
                        "support": 0.89,
                        "sales": 0.11
                    ]
                ),
                "priority": GeminiDecisionsAnswer(
                    type: "score",
                    score: 2.0,
                    confidence: 0.85,
                    probabilities: [
                        "0": 0.05,
                        "1": 0.10,
                        "2": 0.85
                    ],
                    legend: [
                        "0": "Low",
                        "1": "Medium",
                        "2": "High"
                    ]
                )
            ],
            usage: .init(inputTokens: 95, outputTokens: 0)
        )

        let adapted = try GeminiDecisionsPayloadAdapter.adaptResponse(
            geminiResponse,
            transportDurationMs: 45.0,
            serverDurationMs: 38.0
        )

        #expect(adapted.model == "gemini-decision-1")
        #expect(adapted.transportDurationMs == 45.0)
        #expect(adapted.serverDurationMs == 38.0)
        #expect(adapted.usage?.inputTokens == 95)
        #expect(adapted.usage?.outputTokens == 0)

        // Noul
        let spamAnswer = try #require(adapted.answers["isSpam"])
        #expect(spamAnswer.type == "noul")
        #expect(spamAnswer.noul == 0.92)
        #expect(spamAnswer.confidence == 0.92)
        #expect(spamAnswer.probabilities?["true"] == 0.92)

        // Choice
        let deptAnswer = try #require(adapted.answers["dept"])
        #expect(deptAnswer.type == "choice")
        #expect(deptAnswer.choice == "support")
        #expect(deptAnswer.confidence == 0.89)
        #expect(deptAnswer.probabilities?["support"] == 0.89)

        // Score
        let priorityAnswer = try #require(adapted.answers["priority"])
        #expect(priorityAnswer.type == "score")
        #expect(priorityAnswer.score == 2.0)
        #expect(priorityAnswer.confidence == 0.85)
        #expect(priorityAnswer.legend?["2"] == "High")
    }

    @Test("Adapt Response: Throws safetyRefusal when safety refusal is present")
    func testAdaptResponseWithRefusalThrows() throws {
        let geminiResponse = GeminiDecisionsResponse(
            id: "gem-dec-refusal",
            model: "gemini-decision-1",
            answers: [
                "exploitDetection": GeminiDecisionsAnswer(
                    type: "refusal",
                    refusal: "Content violates Google Gemini safety policy regarding cyber attacks."
                )
            ],
            usage: .init(inputTokens: 30, outputTokens: 0)
        )

        do {
            _ = try GeminiDecisionsPayloadAdapter.adaptResponse(geminiResponse)
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

    @Test("Adapt Response: Throws decodingError for absent or empty answers dictionary")
    func testAdaptResponseWithAbsentAnswersThrows() throws {
        let geminiResponse = GeminiDecisionsResponse(
            id: "gem-dec-empty",
            model: "gemini-decision-1",
            answers: [:],
            usage: .init(inputTokens: 10, outputTokens: 0)
        )

        do {
            _ = try GeminiDecisionsPayloadAdapter.adaptResponse(geminiResponse)
            Issue.record("Expected decodingError for empty answers dictionary")
        } catch let error as SystemOneError {
            if case .decodingError(let message) = error {
                #expect(message.contains("Missing answers"))
            } else {
                Issue.record("Expected .decodingError, got: \(error)")
            }
        }
    }

    @Test("Adapt Response: Throws decodingError for partial answers when expected questions are provided")
    func testAdaptResponseWithPartialAnswersThrows() throws {
        let geminiResponse = GeminiDecisionsResponse(
            id: "gem-dec-partial",
            model: "gemini-decision-1",
            answers: [
                "isUrgent": GeminiDecisionsAnswer(
                    type: "noul",
                    noul: 0.95,
                    confidence: 0.95
                )
            ],
            usage: .init(inputTokens: 25, outputTokens: 0)
        )

        let expected = ["category", "isUrgent", "severity"]

        do {
            _ = try GeminiDecisionsPayloadAdapter.adaptResponse(geminiResponse, expectedQuestionNames: expected)
            Issue.record("Expected decodingError for missing expected answers")
        } catch let error as SystemOneError {
            if case .decodingError(let message) = error {
                #expect(message == "Missing answer for expected question 'category'")
            } else {
                Issue.record("Expected .decodingError, got: \(error)")
            }
        }
    }

    @Test("Attachment Validator rejects non-data-URL image payloads")
    func testAttachmentValidatorRejectsInvalidDataURL() throws {
        let invalidImage = SystemOneImage(format: .png, dataURL: "https://example.com/image.png")
        do {
            try GeminiDecisionsAttachmentValidator.validate(attachments: [invalidImage])
            Issue.record("Expected modelExecutionError for remote URL")
        } catch let error as SystemOneError {
            if case .modelExecutionError(let msg) = error {
                #expect(msg.contains("inline base64 image data"))
            } else {
                Issue.record("Expected .modelExecutionError, got: \(error)")
            }
        }
    }
}
