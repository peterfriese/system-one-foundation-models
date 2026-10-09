import Testing
import Foundation
import FoundationModels
@testable import JevFoundationModels

// MARK: - Test URLProtocol

/// Intercepts URLSession requests for offline header assertions.
final class CapturingURLProtocol: URLProtocol {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var _capturedAuthHeader: String?
    nonisolated(unsafe) private static var _responseData: Data = Data()

    static func setResponseData(_ data: Data) {
        lock.withLock { _responseData = data }
    }

    static func lastCapturedAuthHeader() -> String? {
        lock.withLock { _capturedAuthHeader }
    }

    static func reset() {
        lock.withLock {
            _capturedAuthHeader = nil
            _responseData = Data()
        }
    }

    nonisolated override class func canInit(with request: URLRequest) -> Bool { true }
    nonisolated override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.lock.withLock {
            Self._capturedAuthHeader = request.value(forHTTPHeaderField: "Authorization")
        }
        let responseData = Self.lock.withLock { Self._responseData }
        guard let url = request.url else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }
        let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: responseData)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

// MARK: - Test Generable Types

@Generable
enum TestDepartment: String {
    case billing
    case engineering
    case sales
}

@Generable
struct TestDecision {
    @Guide(description: "Is this request urgent?")
    var isUrgent: Bool

    @Guide(description: "Which department handles this?")
    var department: TestDepartment

    @Guide(description: "Frustration rating", .range(0...2))
    var frustration: Int
}

@Generable
struct TestOptionalDecision {
    @Guide(description: "Optional department category")
    var optionalDepartment: TestDepartment?
}

@Generable
struct InvalidProseStruct {
    var freeformNotes: String
}

// MARK: - Test Suite

@Suite("Jev Foundation Models Unit & Integration Tests")
struct JevFoundationModelsTests {

    // MARK: - DTO and Model Capabilities

    @Test("JevRequest JSON encoding matches TypeSafe API format")
    func testRequestEncoding() throws {
        let request = JevRequest(
            state: "I was double charged on my receipt.",
            model: "jev-latest",
            questions: [
                "is_urgent": .noul(instructions: "Is this urgent?"),
                "department": .choice(
                    instructions: "Which team handles this?",
                    criteria: ["billing": "Invoices and charges", "sales": "Pricing"]
                ),
                "frustration": .score(
                    instructions: "Frustration level",
                    criteria: ["Calm", "Upset"]
                )
            ]
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(request)
        let json = try #require(String(data: data, encoding: .utf8))

        #expect(json.contains("\"type\":\"noul\""))
        #expect(json.contains("\"type\":\"choice\""))
        #expect(json.contains("\"type\":\"score\""))
        #expect(json.contains("\"billing\":\"Invoices and charges\""))
    }

    @Test("JevResponse decodes answers and probabilities accurately")
    func testResponseDecoding() throws {
        let sampleJSON = """
        {
          "model": "jev-1.13.0",
          "answers": {
            "is_urgent": {
              "type": "noul",
              "noul": 0.95
            },
            "department": {
              "type": "choice",
              "choice": "billing",
              "confidence": 0.98,
              "probabilities": {
                "billing": 0.98,
                "sales": 0.02
              }
            }
          },
          "usage": {
            "input_tokens": 120,
            "output_tokens": 25
          }
        }
        """

        let decoder = JSONDecoder()
        let response = try decoder.decode(JevResponse.self, from: Data(sampleJSON.utf8))

        #expect(response.model == "jev-1.13.0")
        #expect(response.answers["is_urgent"]?.noul == 0.95)
        #expect(response.answers["department"]?.choice == "billing")
        #expect(response.answers["department"]?.confidence == 0.98)
        #expect(response.usage?.inputTokens == 120)
        #expect(response.usage?.outputTokens == 25)
    }

    @Test("JevLanguageModel capability configuration conforms to System One expectations")
    func testModelCapabilities() {
        let model = JevLanguageModel(apiKey: "test-api-key")
        #expect(model.capabilities.contains(.guidedGeneration) == true)
        #expect(model.capabilities.contains(.toolCalling) == false)
        #expect(model.capabilities.contains(.vision) == false)
        #expect(model.executorConfiguration.apiKey == "test-api-key")
        #expect(model.executorConfiguration.modelID == "jev-latest")
    }

    // MARK: - SchemaTranslator Tests

    @Test("SchemaTranslator maps Bool to noul, enum to choice, range to score")
    func testSchemaTranslatorTranslation() throws {
        let translator = SchemaTranslator()
        let translation = try translator.translate(TestDecision.generationSchema)

        #expect(translation.questions.count == 3)

        // isUrgent -> noul
        guard case .noul(let instructions) = translation.questions["isUrgent"] else {
            Issue.record("Expected isUrgent to be translated to .noul")
            return
        }
        #expect(instructions == "Is this request urgent?")

        // department -> choice
        guard case .choice(let deptInstructions, let criteria) = translation.questions["department"] else {
            Issue.record("Expected department to be translated to .choice")
            return
        }
        #expect(deptInstructions == "Which department handles this?")
        #expect(criteria["billing"] != nil)
        #expect(criteria["engineering"] != nil)
        #expect(criteria["sales"] != nil)

        // frustration -> score
        guard case .score(let frustInstructions, let scoreCriteria) = translation.questions["frustration"] else {
            Issue.record("Expected frustration to be translated to .score")
            return
        }
        #expect(frustInstructions == "Frustration rating")
        #expect(scoreCriteria.count == 3) // 0, 1, 2
    }

    @Test("SchemaTranslator rejects unconstrained String properties with typed error")
    func testSchemaTranslatorRejectsUnconstrainedString() {
        let translator = SchemaTranslator()
        #expect(throws: JevError.self) {
            try translator.translate(InvalidProseStruct.generationSchema)
        }
    }

    @Test("SchemaTranslator translates root enum schema to single choice question")
    func testSchemaTranslatorRootEnum() throws {
        let translator = SchemaTranslator()
        let translation = try translator.translate(TestDepartment.generationSchema)

        guard case .choice(let options, let questionKey) = translation.layout else {
            Issue.record("Expected layout to be .choice")
            return
        }
        #expect(options == ["billing", "engineering", "sales"])
        #expect(translation.questions[questionKey] != nil)
    }

    @Test("SchemaTranslator correctly dereferences $ref inside anyOf for optional enums")
    func testSchemaTranslatorOptionalEnum() throws {
        let translator = SchemaTranslator()
        let translation = try translator.translate(TestOptionalDecision.generationSchema)

        guard case .choice(let optInstructions, let criteria) = translation.questions["optionalDepartment"] else {
            Issue.record("Expected optionalDepartment to be translated to .choice")
            return
        }
        #expect(optInstructions == "Optional department category")
        #expect(criteria["billing"] != nil)
        #expect(criteria["engineering"] != nil)
        #expect(criteria["sales"] != nil)
    }

    // MARK: - ResponseSynthesizer Tests

    @Test("ResponseSynthesizer produces valid JSON for multi-property struct")
    func testResponseSynthesizerObject() throws {
        let synthesizer = ResponseSynthesizer()
        let translator = SchemaTranslator()
        let translation = try translator.translate(TestDecision.generationSchema)

        let mockAnswers: [String: JevAnswer] = [
            "isUrgent": JevAnswer(type: "noul", noul: 0.92),
            "department": JevAnswer(type: "choice", choice: "billing"),
            "frustration": JevAnswer(type: "score", score: 2.0)
        ]

        let synthesizedJSON = try synthesizer.synthesize(answers: mockAnswers, layout: translation.layout)
        guard let data = synthesizedJSON.data(using: .utf8),
              let dict = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            Issue.record("Synthesized JSON was not a valid dictionary: \(synthesizedJSON)")
            return
        }

        #expect(dict["isUrgent"] as? Bool == true)
        #expect(dict["department"] as? String == "billing")
        #expect(dict["frustration"] as? Int == 2)
    }

    @Test("ResponseSynthesizer delivers bare string for root enum")
    func testResponseSynthesizerBareRootEnum() throws {
        let synthesizer = ResponseSynthesizer()
        let translator = SchemaTranslator()
        let translation = try translator.translate(TestDepartment.generationSchema)

        let mockAnswers: [String: JevAnswer] = [
            "choice": JevAnswer(type: "choice", choice: "engineering")
        ]

        let result = try synthesizer.synthesize(answers: mockAnswers, layout: translation.layout)
        #expect(result == "engineering")
    }

    @Test("ResponseSynthesizer extracts metadata JSON for probabilities and confidence")
    func testResponseSynthesizerMetadataExtraction() throws {
        let synthesizer = ResponseSynthesizer()
        let answers: [String: JevAnswer] = [
            "isUrgent": JevAnswer(type: "noul", noul: 0.85),
            "dept": JevAnswer(type: "choice", choice: "billing", confidence: 0.99, probabilities: ["billing": 0.99, "sales": 0.01])
        ]

        let probs = synthesizer.extractProbabilitiesJSON(from: answers)
        #expect(probs != nil)
        let probsData = try #require(probs?.data(using: .utf8))
        let probsDict = try #require(try JSONSerialization.jsonObject(with: probsData) as? [String: Any])
        #expect(probsDict["isUrgent"] != nil)
        #expect(probsDict["dept"] != nil)

        let conf = synthesizer.extractConfidenceJSON(from: answers)
        #expect(conf != nil)
        let confData = try #require(conf?.data(using: .utf8))
        let confDict = try #require(try JSONSerialization.jsonObject(with: confData) as? [String: Double])
        #expect(confDict["dept"] == 0.99)
        #expect(abs((confDict["isUrgent"] ?? 0.0) - 0.70) < 0.01)
    }

    // MARK: - Client and Transport Layer Tests

    actor RequestRecorder {
        var recordedRequest: JevRequest?

        func record(_ request: JevRequest) {
            self.recordedRequest = request
        }
    }

    @Test("MockJevTransport intercepts and responds offline deterministically")
    func testMockJevTransport() async throws {
        let recorder = RequestRecorder()

        let mockTransport = MockJevTransport { request in
            await recorder.record(request)
            return JevResponse(
                model: "jev-mock-1.0",
                answers: ["isUrgent": JevAnswer(type: "noul", noul: 0.88)],
                usage: JevUsage(inputTokens: 50, outputTokens: 2)
            )
        }

        let model = JevLanguageModel(apiKey: "mock-key", transport: mockTransport)
        let client = JevClient(configuration: model.executorConfiguration)

        let request = JevRequest(
            state: "Server error 500",
            questions: ["isUrgent": .noul(instructions: "Is this urgent?")]
        )

        let response = try await client.execute(request: request)
        let interceptedRequest = await recorder.recordedRequest
        #expect(response.model == "jev-mock-1.0")
        #expect(response.answers["isUrgent"]?.noul == 0.88)
        #expect(interceptedRequest?.state == "Server error 500")
        #expect(interceptedRequest?.questions["isUrgent"] != nil)
    }

    // MARK: - End-to-End LanguageModelSession Integration Tests (Offline)

    @Test("End-to-end: LanguageModelSession with MockTransport decodes @Generable struct")
    func testEndToEndSessionWithMockTransport() async throws {
        let mockTransport = MockJevTransport { request in
            #expect(request.questions.count == 3)
            #expect(request.state.contains("Database connection lost"))

            return JevResponse(
                model: "jev-simulated",
                answers: [
                    "isUrgent": JevAnswer(type: "noul", noul: 0.97),
                    "department": JevAnswer(type: "choice", choice: "engineering"),
                    "frustration": JevAnswer(type: "score", score: 1.0)
                ],
                usage: JevUsage(inputTokens: 110, outputTokens: 5)
            )
        }

        let model = JevLanguageModel(apiKey: "mock-api-key", transport: mockTransport)
        let session = LanguageModelSession(model: model)

        let prompt = "Alert: Database connection lost on cluster prod-db-01. Customer checkouts failing."
        let response = try await session.respond(to: prompt, generating: TestDecision.self)

        // 1. Verify strongly-typed content decoding
        #expect(response.content.isUrgent == true)
        #expect(response.content.department == .engineering)
        #expect(response.content.frustration == 1)

        // 2. Verify token usage
        #expect(response.usage.input.totalTokenCount == 110)
        #expect(response.usage.output.totalTokenCount == 5)

        // 3. Verify metadata in transcript
        var foundMetadata = false
        for entry in response.transcriptEntries {
            if case .response(let r) = entry {
                foundMetadata = true
                #expect(r.metadata["model"] != nil)
                #expect(r.metadata["probabilities"] != nil)
                #expect(r.metadata["confidence"] != nil)
            }
        }
        #expect(foundMetadata == true)
    }

    @Test("End-to-end: LanguageModelSession decodes root @Generable enum with bare string")
    func testEndToEndRootEnum() async throws {
        let mockTransport = MockJevTransport { request in
            JevResponse(
                model: "jev-simulated",
                answers: [
                    "choice": JevAnswer(type: "choice", choice: "sales")
                ],
                usage: JevUsage(inputTokens: 40, outputTokens: 1)
            )
        }

        let model = JevLanguageModel(apiKey: "mock-key", transport: mockTransport)
        let session = LanguageModelSession(model: model)

        let prompt = "We would like to discuss volume pricing for 500 enterprise seats."
        let response = try await session.respond(to: prompt, generating: TestDepartment.self)

        #expect(response.content == .sales)
    }

    @Test("End-to-end: LanguageModelSession.Response supports confidence routing and ScoreValue inspection")
    func testEndToEndConfidenceAndNoulRouting() async throws {
        let mockTransport = MockJevTransport { _ in
            JevResponse(
                model: "jev-simulated",
                answers: [
                    "isUrgent": JevAnswer(type: "noul", noul: 0.96),
                    "department": JevAnswer(type: "choice", choice: "engineering", confidence: 0.92),
                    "frustration": JevAnswer(
                        type: "score",
                        score: 1.0,
                        confidence: 0.88,
                        probabilities: ["0": 0.05, "1": 0.85, "2": 0.10],
                        legend: ["0": "calm", "1": "frustrated", "2": "angry"]
                    )
                ],
                usage: JevUsage(inputTokens: 80, outputTokens: 4)
            )
        }

        let model = JevLanguageModel(apiKey: "mock-key", transport: mockTransport)
        let session = LanguageModelSession(model: model)

        let response = try await session.respond(to: "Database deadlocks causing customer checkout failures", generating: TestDecision.self)

        // 1. Categorical confidence routing
        #expect(response.decision(for: "department") == .auto)

        // 2. Boolean Noul routing with undecided band handling
        let urgentJudgement = response.judgement(for: "isUrgent")
        #expect(urgentJudgement.decision == .auto)
        #expect(urgentJudgement.answer == true)
        #expect(urgentJudgement.decisiveness == 0.96)

        // 3. ScoreValue inspection
        let frustrationScore = try #require(response.scoreValue(for: "frustration"))
        #expect(frustrationScore.rounded == 1)
        #expect(frustrationScore.normalized == 0.5) // 1.0 / (3 - 1) = 0.5
        #expect(frustrationScore.legend[1] == "frustrated")

        // 4. Safe escalation for unanswered questions
        #expect(response.decision(for: "unansweredQuestion") == .escalate)
        let missingJudgement = response.judgement(for: "unansweredQuestion")
        #expect(missingJudgement.decision == .escalate)
        #expect(missingJudgement.answer == nil)
    }

    @Test("JevExecutor rejects unstructured free-form text request without schema")
    func testExecutorRejectsUnstructuredRequest() async throws {
        let model = JevLanguageModel(apiKey: "mock-key")
        let executor = try JevExecutor(configuration: model.executorConfiguration)

        let request = LanguageModelExecutorGenerationRequest(
            id: UUID(),
            transcript: Transcript(entries: [
                .prompt(Transcript.Prompt(segments: [.text(Transcript.TextSegment(content: "Write a poem"))]))
            ]),
            enabledTools: [],
            schema: nil,
            generationOptions: GenerationOptions(),
            contextOptions: ContextOptions(),
            metadata: [:]
        )

        let channel = LanguageModelExecutorGenerationChannel()

        await #expect(throws: JevError.self) {
            try await executor.respond(to: request, model: model, streamingInto: channel)
        }
    }

    // MARK: - Error Handling Tests

    @Test("JevExecutor propagates API errors from transport")
    func testExecutorPropagatesApiError() async throws {
        let mockTransport = MockJevTransport { _ in
            throw JevError.apiError(statusCode: 401, message: "Unauthorized: Invalid API key")
        }

        let model = JevLanguageModel(apiKey: "bad-key", transport: mockTransport)
        let session = LanguageModelSession(model: model)

        await #expect(throws: JevError.self) {
            try await session.respond(to: "Test inquiry", generating: TestDecision.self)
        }
    }

    @Test("URLSessionTransport rejects execution without an API key")
    func testURLSessionTransportRequiresAPIKey() async throws {
        let model = JevLanguageModel()
        let request = JevRequest(state: "Test state", questions: [:])

        await #expect(throws: JevError.missingAPIKey) {
            try await JevClient(configuration: model.executorConfiguration).execute(request: request)
        }
    }

    @Test("URLSessionTransport rejects empty-string API keys")
    func testURLSessionTransportRejectsEmptyAPIKey() async throws {
        let model = JevLanguageModel(apiKey: "")
        let request = JevRequest(state: "Test state", questions: [:])

        await #expect(throws: JevError.missingAPIKey) {
            try await JevClient(configuration: model.executorConfiguration).execute(request: request)
        }
    }

    @Test("URLSessionTransport sends configured API key in Authorization header")
    func testURLSessionTransportSendsAPIKeyHeader() async throws {
        CapturingURLProtocol.reset()
        defer { CapturingURLProtocol.reset() }

        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [CapturingURLProtocol.self]
        let payload = """
        {"model":"jev-latest","answers":{"urgent":{"type":"noul","noul":0.9,"confidence":0.8}}}
        """
        CapturingURLProtocol.setResponseData(Data(payload.utf8))

        let transport = URLSessionTransport(session: URLSession(configuration: config))
        let request = JevRequest(
            state: "Test state",
            questions: ["urgent": .noul(instructions: "Is this request urgent?")]
        )

        let response = try await transport.send(
            request: request,
            apiKey: "test-api-key",
            endpoint: URL(string: "https://api.typesafe.ai/v1/systemone")!
        )

        #expect(response.answers["urgent"]?.noul == 0.9)
        #expect(CapturingURLProtocol.lastCapturedAuthHeader() == "Bearer test-api-key")
    }

    // MARK: - Live API Integration Test

    @Test("Live TypeSafe AI API integration test (runs when TYPESAFE_API_KEY is available)")
    func testLiveTypeSafeAPIIntegration() async throws {
        let apiKey: String? = {
            if let envKey = ProcessInfo.processInfo.environment["TYPESAFE_API_KEY"], !envKey.isEmpty {
                return envKey
            }
            let envURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent(".env")
            guard let contents = try? String(contentsOf: envURL, encoding: .utf8) else { return nil }
            for line in contents.components(separatedBy: .newlines) {
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.hasPrefix("#") || trimmed.isEmpty { continue }
                let parts = trimmed.split(separator: "=", maxSplits: 1).map(String.init)
                if parts.count == 2 && parts[0].trimmingCharacters(in: .whitespaces) == "TYPESAFE_API_KEY" {
                    var val = parts[1].trimmingCharacters(in: .whitespaces)
                    if (val.hasPrefix("\"") && val.hasSuffix("\"")) || (val.hasPrefix("'") && val.hasSuffix("'")) {
                        val = String(val.dropFirst().dropLast())
                    }
                    return val.isEmpty ? nil : val
                }
            }
            return nil
        }()

        guard let key = apiKey else {
            // Live key not present, skip live call
            return
        }

        let model = JevLanguageModel(apiKey: key)
        let session = LanguageModelSession(model: model)

        let prompt = "I demand an immediate refund for invoice #9920. Your billing department double-charged my account and it is unacceptable!"
        let response = try await session.respond(to: prompt, generating: TestDecision.self)

        #expect(response.content.isUrgent == true)
        #expect(response.content.department == .billing)
        #expect(response.content.frustration >= 1)
        #expect(response.usage.input.totalTokenCount > 0)
        #expect(response.usage.output.totalTokenCount > 0)
    }
}
