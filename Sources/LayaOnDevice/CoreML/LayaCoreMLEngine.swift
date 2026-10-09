import Foundation
@preconcurrency import CoreML
import SystemOneCore

/// A thread-safe wrapper around Core ML's `MLModel`.
///
/// In Apple's CoreML framework, `MLModel` is proven thread-safe for read-only prediction evaluations,
/// but the Objective-C class interface currently lacks the Swift `Sendable` annotation.
private final class ThreadSafeMLModel: @unchecked Sendable {
    let model: MLModel

    init(_ model: MLModel) {
        self.model = model
    }
}

/// An on-device inference engine executing Laya decision models locally via Core ML on Apple Neural Engine / GPU.
///
/// See `tech-notes/0008-on-device-coreml-decision-engine.md`.
public final class LayaCoreMLEngine: Sendable {
    public let modelURL: URL?
    public let tokenizer: any LayaTokenizer
    public let sequenceBuilder: LayaSequenceBuilder
    public let maxOptions: Int

    private let modelHolder: ThreadSafeMLModel?
    private let mockPredictor: (@Sendable (FormattedQuestionSequence) async throws -> [Double])?

    public init(
        modelURL: URL,
        tokenizer: any LayaTokenizer,
        configuration: MLModelConfiguration = MLModelConfiguration(),
        maxOptions: Int = 32
    ) throws {
        self.modelURL = modelURL
        self.tokenizer = tokenizer
        self.sequenceBuilder = LayaSequenceBuilder(tokenizer: tokenizer)
        self.maxOptions = maxOptions

        // Optimize compute units for Apple Neural Engine with GPU/CPU fallback
        let config = (configuration.copy() as? MLModelConfiguration) ?? MLModelConfiguration()
        config.computeUnits = .all
        let loaded = try MLModel(contentsOf: modelURL, configuration: config)
        self.modelHolder = ThreadSafeMLModel(loaded)
        self.mockPredictor = nil
    }

    /// Internal initializer enabling deterministic offline testing without physical model weights.
    public init(
        tokenizer: any LayaTokenizer,
        maxOptions: Int = 32,
        mockPredictor: @escaping @Sendable (FormattedQuestionSequence) async throws -> [Double]
    ) {
        self.modelURL = nil
        self.tokenizer = tokenizer
        self.sequenceBuilder = LayaSequenceBuilder(tokenizer: tokenizer)
        self.maxOptions = maxOptions
        self.modelHolder = nil
        self.mockPredictor = mockPredictor
    }

    /// Evaluates a System One request locally on device.
    public func predict(request: SystemOneRequest) async throws -> SystemOneResponse {
        let startTime = CFAbsoluteTimeGetCurrent()
        var answers: [String: SystemOneAnswer] = [:]
        var totalTokens = 0

        let pretokenizedStateIds = sequenceBuilder.pretokenizeState(request.state)

        for (qid, question) in request.questions {
            let sequence = try sequenceBuilder.buildSequence(pretokenizedStateIds: pretokenizedStateIds, question: question)
            try validateOptionCount(sequence.markerPositions.count, questionID: qid)
            totalTokens += sequence.inputIds.count

            let logits: [Double]
            if let mock = mockPredictor {
                logits = try await mock(sequence)
            } else if let holder = modelHolder {
                let model = holder.model
                logits = try await Task.detached { [self] in
                    try self.executeCoreML(model: model, sequence: sequence)
                }.value
            } else {
                throw SystemOneError.modelExecutionError("No Core ML model or predictor configured.")
            }

            let answer = decodeAnswer(logits: logits, sequence: sequence)
            answers[qid] = answer
        }

        let durationMs = (CFAbsoluteTimeGetCurrent() - startTime) * 1000.0

        return SystemOneResponse(
            model: request.model.isEmpty ? "laya-coreml-local" : request.model,
            answers: answers,
            usage: SystemOneUsage(inputTokens: totalTokens, outputTokens: 0),
            serverDurationMs: durationMs
        )
    }

    // MARK: - Core ML Execution

    private func executeCoreML(model: MLModel, sequence: FormattedQuestionSequence) throws -> [Double] {
        let seqLen = sequence.inputIds.count
        let k = sequence.markerPositions.count
        try validateOptionCount(k)

        // 1. Create input multiarrays
        let inputIdsArr = try MLMultiArray(shape: [1, NSNumber(value: seqLen)], dataType: .int32)
        let maskArr = try MLMultiArray(shape: [1, NSNumber(value: seqLen)], dataType: .int32)
        for i in 0..<seqLen {
            inputIdsArr[[0, NSNumber(value: i)]] = NSNumber(value: sequence.inputIds[i])
            maskArr[[0, NSNumber(value: i)]] = 1
        }

        let markerPosArr = try MLMultiArray(shape: [1, NSNumber(value: maxOptions)], dataType: .int32)
        let markerMaskArr = try MLMultiArray(shape: [1, NSNumber(value: maxOptions)], dataType: .float32)
        for i in 0..<maxOptions {
            if i < k {
                markerPosArr[[0, NSNumber(value: i)]] = NSNumber(value: sequence.markerPositions[i])
                markerMaskArr[[0, NSNumber(value: i)]] = 1.0
            } else {
                markerPosArr[[0, NSNumber(value: i)]] = 0
                markerMaskArr[[0, NSNumber(value: i)]] = 0.0
            }
        }

        let qtypeArr = try MLMultiArray(shape: [1], dataType: .int32)
        qtypeArr[[0]] = NSNumber(value: sequence.qtype)

        // 2. Assemble feature dictionary
        let featureDict: [String: Any] = [
            "input_ids": inputIdsArr,
            "attention_mask": maskArr,
            "marker_pos": markerPosArr,
            "marker_mask": markerMaskArr,
            "qtype": qtypeArr
        ]
        let featureProvider = try MLDictionaryFeatureProvider(dictionary: featureDict)

        // 3. Run prediction on Neural Engine / GPU
        let output = try model.prediction(from: featureProvider)
        guard let logitsFeature = output.featureValue(for: "logits")?.multiArrayValue else {
            throw SystemOneError.modelExecutionError("Core ML output missing 'logits' tensor.")
        }

        var resultLogits: [Double] = []
        for i in 0..<k {
            resultLogits.append(logitsFeature[[0, NSNumber(value: i)]].doubleValue)
        }
        return resultLogits
    }

    private func validateOptionCount(_ count: Int, questionID: String? = nil) throws {
        guard count <= maxOptions else {
            let questionFragment = questionID.map { "Question '\($0)' " } ?? "Question "
            throw SystemOneError.modelExecutionError(
                "\(questionFragment)produced \(count) options, exceeding configured maxOptions=\(maxOptions)."
            )
        }
    }

    // MARK: - Answer Decoding

    private func decodeAnswer(logits: [Double], sequence: FormattedQuestionSequence) -> SystemOneAnswer {
        let k = sequence.markerPositions.count
        let rawLogits = Array(logits.prefix(k))
        let bucket = TemperatureCalibration.tempBucket(qtype: sequence.qtype, optionCount: k)
        let temperature: Double = (bucket == "choice:2" || bucket == "noul:2") ? 1.0 : 1.2
        let probs = TemperatureCalibration.softmax(logits: rawLogits, temperature: temperature)
        let conf = TemperatureCalibration.answerConfidence(probabilities: probs)

        switch sequence.qtype {
        case 0: // Choice
            var probsDict: [String: Double] = [:]
            var bestIdx = 0
            var bestProb = -1.0
            for (i, key) in sequence.optionKeys.enumerated() {
                let p = i < probs.count ? probs[i] : 0.0
                probsDict[key] = round(p * 10000.0) / 10000.0
                if p > bestProb {
                    bestProb = p
                    bestIdx = i
                }
            }
            let choiceKey = sequence.optionKeys.indices.contains(bestIdx) ? sequence.optionKeys[bestIdx] : (sequence.optionKeys.first ?? "")
            return SystemOneAnswer(
                type: "choice",
                choice: choiceKey,
                confidence: round(conf * 10000.0) / 10000.0,
                probabilities: probsDict
            )

        case 1: // Score
            var probsDict: [String: Double] = [:]
            var expectedScore = 0.0
            for (i, p) in probs.enumerated() {
                probsDict[String(i)] = round(p * 10000.0) / 10000.0
                expectedScore += Double(i) * p
            }
            return SystemOneAnswer(
                type: "score",
                score: round(expectedScore * 10000.0) / 10000.0,
                confidence: round(conf * 10000.0) / 10000.0,
                probabilities: probsDict
            )

        default: // Noul
            let pTrue = probs.count > 1 ? probs[1] : 0.5
            let noulConf = max(pTrue, 1.0 - pTrue)
            return SystemOneAnswer(
                type: "noul",
                noul: round(pTrue * 10000.0) / 10000.0,
                confidence: round(noulConf * 10000.0) / 10000.0,
                probabilities: [
                    "false": round((1.0 - pTrue) * 10000.0) / 10000.0,
                    "true": round(pTrue * 10000.0) / 10000.0
                ]
            )
        }
    }
}
