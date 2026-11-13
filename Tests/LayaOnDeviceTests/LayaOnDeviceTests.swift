import Testing
import Foundation
import CoreML
import FoundationModels
import SystemOneCore
@testable import LayaOnDevice

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

    @Test("LayaCoreMLEngine.prepareFeatureArrays pads inputIds and attentionMask to static [1, 512] shape")
    func testPrepareFeatureArraysStatic512Padding() throws {
        let tokenizer = ModernBERTTokenizer.defaultTokenizer()
        let builder = LayaSequenceBuilder(tokenizer: tokenizer, maxLen: 512, headMaxLen: 192)
        let sequence = try builder.buildSequence(
            state: "Short state text",
            question: .noul(instructions: "Is this active?")
        )
        #expect(sequence.inputIds.count < 512)

        let engine = LayaCoreMLEngine(tokenizer: tokenizer) { _ in [0.0, 1.0] }
        let arrays = try engine.prepareFeatureArrays(for: sequence)

        #expect(arrays.inputIds.shape == [1, 512])
        #expect(arrays.attentionMask.shape == [1, 512])
        #expect(arrays.markerPos.shape == [1, 32])
        #expect(arrays.markerMask.shape == [1, 32])
        #expect(arrays.qtype.shape == [1])

        let seqLen = sequence.inputIds.count
        for i in 0..<seqLen {
            #expect(arrays.inputIds[[0, NSNumber(value: i)]].intValue == sequence.inputIds[i])
            #expect(arrays.attentionMask[[0, NSNumber(value: i)]].intValue == 1)
        }
        for i in seqLen..<512 {
            #expect(arrays.inputIds[[0, NSNumber(value: i)]].intValue == tokenizer.padTokenId)
            #expect(arrays.attentionMask[[0, NSNumber(value: i)]].intValue == 0)
        }
    }

    @Test("MMBERTTokenizer loads SentencePiece Unigram [[piece, score]] + added_tokens and encodes subwords")
    func testMMBERTTokenizerSentencePieceUnigramAndAddedTokens() throws {
        let tokenizerJSON = """
        {
          "model": {
            "type": "Unigram",
            "vocab": [
              ["<pad>", 0.0],
              ["<eos>", 0.0],
              ["<bos>", 0.0],
              ["<unk>", 0.0],
              ["▁hello", -1.2],
              ["▁world", -1.5],
              ["s", -2.1]
            ]
          },
          "added_tokens": [
            { "id": 7, "content": "<mask_1>", "special": true }
          ]
        }
        """
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("mmbert-unigram-\(UUID().uuidString).json")
        try Data(tokenizerJSON.utf8).write(to: tempURL)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let tokenizer = try MMBERTTokenizer(jsonURL: tempURL)
        #expect(tokenizer.maskTokenId == 7)
        let ids = tokenizer.encode("hello worlds <mask_1>", addSpecialTokens: true)
        #expect(ids == [2, 4, 5, 6, 7, 1])

        // Rejects remote URLs with SystemOneError instead of blocking network I/O
        #expect(throws: SystemOneError.self) {
            _ = try MMBERTTokenizer(jsonURL: URL(string: "https://example.com/tokenizer.json")!)
        }
        #expect(throws: SystemOneError.self) {
            _ = try ModernBERTTokenizer(jsonURL: URL(string: "https://example.com/tokenizer.json")!)
        }
    }

    @Test("TemperatureCalibration handles empty probabilities and non-finite logits safely")
    func testTemperatureCalibrationEdgeCases() {
        #expect(TemperatureCalibration.answerConfidence(probabilities: []) == 0.0)
        #expect(TemperatureCalibration.answerConfidence(probabilities: [.nan, 0.5]) == 0.0)

        let probs = TemperatureCalibration.softmax(logits: [.nan, 1.0], temperature: 1.0)
        #expect(probs.count == 2)
        #expect(probs.allSatisfy { $0.isFinite && abs($0 - 0.5) < 0.0001 })
    }

    @Test("LayaOnDeviceLanguageModel supports init(backend:) and fails cleanly on missing model file")
    func testLayaOnDeviceBackendInitAndMissingModel() async throws {
        let backend = MockSystemOneBackend(
            fixedResponse: SystemOneResponse(
                model: "laya-coreml",
                answers: ["decision": SystemOneAnswer(type: "noul", noul: 0.91, confidence: 0.91)]
            )
        )
        let session = LanguageModelSession(model: LayaOnDeviceLanguageModel(backend: backend))
        let prob = try await session.probability(of: "Check on-device backend seam", state: "State")
        #expect(abs(prob - 0.91) < 0.0001)

        let missingURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("nonexistent-\(UUID().uuidString).mlpackage")
        #expect(throws: SystemOneError.self) {
            _ = try LayaOnDeviceLanguageModel(modelURL: missingURL)
        }
    }
}
