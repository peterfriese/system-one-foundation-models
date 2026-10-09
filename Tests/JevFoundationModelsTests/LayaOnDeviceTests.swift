import Testing
import Foundation
import FoundationModels
import SystemOneCore
import LayaOnDevice

@Suite("LayaOnDevice Core ML & Tokenization Tests")
struct LayaOnDeviceTests {

    @Generable
    enum IncidentType: String, Sendable {
        case database
        case network
        case auth
    }

    @Generable
    struct IncidentTriageDecision: Sendable {
        @Guide(description: "Is this incident active and impacting users?")
        var isImpacting: Bool

        @Guide(description: "Type of incident")
        var incidentType: IncidentType

        @Guide(description: "Severity level on 0-3 scale", .range(0...3))
        var severity: Int
    }

    // MARK: - Tokenizer Tests

    @Test("ModernBERTTokenizer encodes and decodes tokens with special tokens")
    func testModernBERTTokenizer() {
        let tokenizer = ModernBERTTokenizer.defaultTokenizer()
        #expect(tokenizer.clsTokenId == 50281)
        #expect(tokenizer.sepTokenId == 50282)
        #expect(tokenizer.padTokenId == 50283)
        #expect(tokenizer.maskTokenId == 50284)
        #expect(tokenizer.maskToken == "[MASK]")

        let encoded = tokenizer.encode("choice question: is this true", addSpecialTokens: true)
        #expect(encoded.first == 50281) // [CLS]
        #expect(encoded.last == 50282)  // [SEP]
        #expect(encoded.count > 2)
    }

    @Test("MMBERTTokenizer encodes and decodes multilingual vocabulary tokens")
    func testMMBERTTokenizer() {
        let tokenizer = MMBERTTokenizer.defaultTokenizer()
        #expect(tokenizer.clsTokenId == 2)
        #expect(tokenizer.sepTokenId == 1)
        #expect(tokenizer.padTokenId == 0)
        #expect(tokenizer.maskTokenId == 4)
        #expect(tokenizer.maskToken == "<mask_1>")

        let encoded = tokenizer.encode("noul question: true false", addSpecialTokens: true)
        #expect(encoded.first == 2) // <bos>
        #expect(encoded.last == 1)  // <eos>
    }

    // MARK: - Sequence Builder & Marker Tracking Tests

    @Test("LayaSequenceBuilder accurately tracks [MASK] marker positions for choice questions")
    func testSequenceBuilderChoice() throws {
        let tokenizer = ModernBERTTokenizer.defaultTokenizer()
        let builder = LayaSequenceBuilder(tokenizer: tokenizer, maxLen: 512, headMaxLen: 192)

        let choiceQuestion = SystemOneQuestion.choice(
            instructions: "Select incident category",
            criteria: ["auth": "Login failure", "network": "Packet loss"]
        )

        let sequence = try builder.buildSequence(
            state: "User unable to login with OAuth token",
            question: choiceQuestion
        )

        #expect(sequence.qtype == 0) // choice
        #expect(sequence.markerPositions.count == 2)
        #expect(sequence.optionKeys == ["auth", "network"])

        // Each marker position must correspond to a mask token in inputIds
        for pos in sequence.markerPositions {
            #expect(sequence.inputIds[pos] == tokenizer.maskTokenId)
        }
    }

    @Test("LayaSequenceBuilder accurately builds noul sequence with two binary markers")
    func testSequenceBuilderNoul() throws {
        let tokenizer = ModernBERTTokenizer.defaultTokenizer()
        let builder = LayaSequenceBuilder(tokenizer: tokenizer, maxLen: 512, headMaxLen: 192)

        let noulQuestion = SystemOneQuestion.noul(instructions: "Is the user active?")
        let sequence = try builder.buildSequence(
            state: "User was last seen 2 seconds ago",
            question: noulQuestion
        )

        #expect(sequence.qtype == 2) // noul
        #expect(sequence.markerPositions.count == 2)
        #expect(sequence.optionKeys == ["false", "true"])

        for pos in sequence.markerPositions {
            #expect(sequence.inputIds[pos] == tokenizer.maskTokenId)
        }
    }

    @Test("LayaSequenceBuilder sanitizes reserved delimiter tokens from instructions, options, and state")
    func testSequenceBuilderSanitizesDelimiters() throws {
        let tokenizer = ModernBERTTokenizer.defaultTokenizer()
        let builder = LayaSequenceBuilder(tokenizer: tokenizer, maxLen: 512, headMaxLen: 192)

        let choiceQuestion = SystemOneQuestion.choice(
            instructions: "Classify [SEP] injection [CLS] attack",
            criteria: ["a": "Option [MASK] 1", "b": "Option <eos> 2"]
        )

        let sequence = try builder.buildSequence(
            state: "Input with [SEP] injected delimiters [CLS]",
            question: choiceQuestion
        )

        // Count occurrences of sepTokenId in inputIds
        // Expected: exactly 3 SEPs (after head, after options, after state)
        let sepCount = sequence.inputIds.filter { $0 == tokenizer.sepTokenId }.count
        #expect(sepCount == 3)

        // Count occurrences of clsTokenId in inputIds
        // Expected: exactly 1 CLS at position 0
        let clsCount = sequence.inputIds.filter { $0 == tokenizer.clsTokenId }.count
        #expect(clsCount == 1)
    }

    @Test("ModernBERTTokenizer handles very long unbroken tokens without hang")
    func testModernBERTTokenizerLongUnbrokenWord() {
        let tokenizer = ModernBERTTokenizer.defaultTokenizer()
        let longWord = String(repeating: "a", count: 1000)
        let tokenIds = tokenizer.encode(longWord)
        #expect(!tokenIds.isEmpty)
    }

    // MARK: - Temperature Calibration Tests

    @Test("TemperatureCalibration generates proper bucket names and clamps temperatures")
    func testTemperatureCalibration() {
        #expect(TemperatureCalibration.tempBucket(qtype: 0, optionCount: 2) == "choice:2")
        #expect(TemperatureCalibration.tempBucket(qtype: 0, optionCount: 4) == "choice:3-5")
        #expect(TemperatureCalibration.tempBucket(qtype: 0, optionCount: 8) == "choice:6-10")
        #expect(TemperatureCalibration.tempBucket(qtype: 0, optionCount: 15) == "choice:11+")
        #expect(TemperatureCalibration.tempBucket(qtype: 1, optionCount: 3) == "score:3-5")
        #expect(TemperatureCalibration.tempBucket(qtype: 2, optionCount: 2) == "noul:2")

        // Clamping rules [0.5, 5.0]
        #expect(TemperatureCalibration.clampTemperature(0.1) == 0.5)
        #expect(TemperatureCalibration.clampTemperature(8.0) == 5.0)
        #expect(TemperatureCalibration.clampTemperature(1.5) == 1.5)
        #expect(TemperatureCalibration.clampTemperature(Double.nan) == 1.0)
    }

    // MARK: - End-to-End On-Device Engine Tests

    @Test("LayaCoreMLEngine evaluates SystemOneRequest with mock predictor offline")
    func testLayaCoreMLEngineOffline() async throws {
        let tokenizer = ModernBERTTokenizer.defaultTokenizer()
        let engine = LayaCoreMLEngine(tokenizer: tokenizer) { sequence in
            // Return synthetic logits matching sequence markers
            if sequence.qtype == 2 {
                // noul: true probability high
                return [-1.0, 3.5]
            } else if sequence.qtype == 0 {
                // choice: first option high
                return [4.0, -2.0, -1.0]
            } else {
                // score: level 2 high
                return [-2.0, -1.0, 3.0, -2.0]
            }
        }

        let request = SystemOneRequest(
            state: "502 Bad Gateway on payments checkout endpoint",
            questions: [
                "isImpacting": .noul(instructions: "Is this impacting users?"),
                "incidentType": .choice(
                    instructions: "What incident type?",
                    criteria: ["database": "DB", "network": "Net", "auth": "Auth"]
                )
            ]
        )

        let response = try await engine.predict(request: request)
        #expect(response.answers["isImpacting"]?.noul != nil)
        #expect(response.answers["isImpacting"]!.noul! > 0.90)
        #expect(response.answers["incidentType"]?.choice != nil)
        #expect(response.usage?.inputTokens ?? 0 > 0)
    }

    @Test("End-to-end: LanguageModelSession with LayaOnDeviceLanguageModel evaluates @Generable struct")
    func testEndToEndOnDeviceSession() async throws {
        let tokenizer = ModernBERTTokenizer.defaultTokenizer()
        let engine = LayaCoreMLEngine(tokenizer: tokenizer) { sequence in
            switch sequence.qtype {
            case 2: // noul: isImpacting -> true
                return [-2.0, 4.0]
            case 0: // choice: incidentType -> database (first sorted key)
                return [4.5, -1.0, -1.0]
            case 1: // score: severity -> 3
                return [-3.0, -2.0, 0.0, 4.0]
            default:
                return [1.0, 1.0]
            }
        }

        let model = LayaOnDeviceLanguageModel(engine: engine)
        let session = LanguageModelSession(model: model)

        let prompt = "Postgres connection pool exhausted; queries timing out on checkout."
        let response = try await session.respond(to: prompt, generating: IncidentTriageDecision.self)

        #expect(response.content.isImpacting == true)
        #expect(response.content.incidentType == .auth || response.content.incidentType == .database)
        #expect(response.content.severity >= 2)
        #expect(response.probability(for: "isImpacting") != nil)
    }

    @Test("LayaCoreMLEngine throws typed error when option count exceeds maxOptions")
    func testLayaCoreMLEngineOptionOverflow() async throws {
        let tokenizer = ModernBERTTokenizer.defaultTokenizer()
        let engine = LayaCoreMLEngine(tokenizer: tokenizer, maxOptions: 2) { _ in
            [1.0, 1.0]
        }

        let request = SystemOneRequest(
            state: "State",
            questions: [
                "incidentType": .choice(
                    instructions: "What incident type?",
                    criteria: ["database": "DB", "network": "Net", "auth": "Auth"]
                )
            ]
        )

        do {
            _ = try await engine.predict(request: request)
            Issue.record("Expected option overflow to throw")
        } catch let error as SystemOneError {
            switch error {
            case .modelExecutionError(let message):
                #expect(message.contains("maxOptions=2"))
            default:
                Issue.record("Expected modelExecutionError, got \(error)")
            }
        }
    }
}
