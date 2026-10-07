import Foundation

// MARK: - System One Request Payloads

/// A request payload conforming to the System One decision evaluation schema.
public struct SystemOneRequest: Codable, Sendable, Equatable {
    public let state: String
    public let model: String
    public let questions: [String: SystemOneQuestion]
    /// Optional collection of image attachments for multimodal models (e.g. Cloudflare Clef).
    public let images: [SystemOneImage]?

    public init(
        state: String,
        model: String = "systemone-default",
        questions: [String: SystemOneQuestion],
        images: [SystemOneImage]? = nil
    ) {
        self.state = state
        self.model = model
        self.questions = questions
        self.images = images
    }

    private enum CodingKeys: String, CodingKey {
        case state, model, questions, images
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(state, forKey: .state)
        try container.encode(model, forKey: .model)
        try container.encode(questions, forKey: .questions)
        if let images, !images.isEmpty {
            try container.encode(images, forKey: .images)
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.state = try container.decode(String.self, forKey: .state)
        self.model = try container.decodeIfPresent(String.self, forKey: .model) ?? "systemone-default"
        self.questions = try container.decode([String: SystemOneQuestion].self, forKey: .questions)
        self.images = try container.decodeIfPresent([SystemOneImage].self, forKey: .images)
    }
}

/// A strongly-typed question evaluated in a single forward pass by a System One decision model.
public enum SystemOneQuestion: Codable, Sendable, Equatable {
    /// Evaluates the probability of truth (0.0 to 1.0) for a statement.
    case noul(instructions: String)
    /// Evaluates discrete categorical selection among candidate options.
    case choice(instructions: String, criteria: [String: String])
    /// Evaluates an ordinal rubric score across numeric/integer levels.
    case score(instructions: String, criteria: [String])

    private enum CodingKeys: String, CodingKey {
        case type, instructions, criteria
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .noul(let instructions):
            try container.encode("noul", forKey: .type)
            try container.encode(instructions, forKey: .instructions)
        case .choice(let instructions, let criteria):
            try container.encode("choice", forKey: .type)
            try container.encode(instructions, forKey: .instructions)
            try container.encode(criteria, forKey: .criteria)
        case .score(let instructions, let criteria):
            try container.encode("score", forKey: .type)
            try container.encode(instructions, forKey: .instructions)
            try container.encode(criteria, forKey: .criteria)
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        let instructions = try container.decode(String.self, forKey: .instructions)
        switch type {
        case "noul":
            self = .noul(instructions: instructions)
        case "choice":
            let criteria = try container.decode([String: String].self, forKey: .criteria)
            self = .choice(instructions: instructions, criteria: criteria)
        case "score":
            let criteria = try container.decode([String].self, forKey: .criteria)
            self = .score(instructions: instructions, criteria: criteria)
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .type,
                in: container,
                debugDescription: "Unknown primitive type: \(type)"
            )
        }
    }
}

// MARK: - System One Response Payloads

/// The response payload containing calibrated answers and telemetry from a System One model.
public struct SystemOneResponse: Codable, Sendable, Equatable {
    public let model: String
    public let answers: [String: SystemOneAnswer]
    public let usage: SystemOneUsage?
    /// Server-reported inference duration in milliseconds (if provided by gateway/server).
    public var serverDurationMs: Double?
    /// Client-side HTTP/transport round-trip latency in milliseconds.
    public var transportDurationMs: Double?

    public init(
        model: String,
        answers: [String: SystemOneAnswer],
        usage: SystemOneUsage? = nil,
        serverDurationMs: Double? = nil,
        transportDurationMs: Double? = nil
    ) {
        self.model = model
        self.answers = answers
        self.usage = usage
        self.serverDurationMs = serverDurationMs
        self.transportDurationMs = transportDurationMs
    }
}

/// Token usage statistics for a System One evaluation.
public struct SystemOneUsage: Codable, Sendable, Equatable {
    public let inputTokens: Int
    public let outputTokens: Int

    enum CodingKeys: String, CodingKey {
        case inputTokens = "input_tokens"
        case outputTokens = "output_tokens"
    }

    public init(inputTokens: Int, outputTokens: Int) {
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
    }
}

/// A calibrated answer for a single System One question.
public struct SystemOneAnswer: Codable, Sendable, Equatable {
    public let type: String
    public let noul: Double?
    public let choice: String?
    public let score: Double?
    public let confidence: Double?
    public let probabilities: [String: Double]?
    public let legend: [String: String]?

    public init(
        type: String,
        noul: Double? = nil,
        choice: String? = nil,
        score: Double? = nil,
        confidence: Double? = nil,
        probabilities: [String: Double]? = nil,
        legend: [String: String]? = nil
    ) {
        self.type = type
        self.noul = noul
        self.choice = choice
        self.score = score
        self.confidence = confidence
        self.probabilities = probabilities
        self.legend = legend
    }

    /// Converts this answer into a typed `Probability` if it is a boolean (`noul`) answer.
    public var probability: Probability? {
        noul.flatMap(Probability.init(exactly:))
    }

    /// Converts this answer into a typed `ScoreValue` if it is a rubric `score` answer.
    public var scoreValue: ScoreValue? {
        scoreValue(minimum: nil, maximum: nil, isInteger: false)
    }

    public func scoreValue(minimum: Double?, maximum: Double?, isInteger: Bool) -> ScoreValue? {
        guard let score, score.isFinite else { return nil }
        let conf = confidence ?? 1.0
        guard conf.isFinite, (0.0...1.0).contains(conf) else { return nil }
        var indexedLegend: [Int: String] = [:]
        if let legend {
            for (k, v) in legend {
                if let idx = Int(k) { indexedLegend[idx] = v }
            }
        }
        var indexedProbs: [Int: Double] = [:]
        if let probabilities {
            for (k, v) in probabilities {
                if let idx = Int(k), v.isFinite { indexedProbs[idx] = v }
            }
        }

        let levelCount = max(indexedLegend.count, indexedProbs.count)
        let adjustedScore = adjustedScoreValue(
            rawScore: score,
            minimum: minimum,
            maximum: maximum,
            isInteger: isInteger,
            levelCount: levelCount
        )
        return ScoreValue(
            validatingValue: adjustedScore,
            legend: shiftedLevels(
                indexedLegend,
                minimum: minimum,
                maximum: maximum,
                isInteger: isInteger,
                levelCount: levelCount
            ),
            probabilities: shiftedLevels(
                indexedProbs,
                minimum: minimum,
                maximum: maximum,
                isInteger: isInteger,
                levelCount: levelCount
            ),
            confidence: conf
        )
    }

    private func adjustedScoreValue(
        rawScore: Double,
        minimum: Double?,
        maximum: Double?,
        isInteger: Bool,
        levelCount: Int
    ) -> Double {
        guard let minimum, let maximum else { return rawScore }
        guard minimum <= maximum else { return rawScore }

        let span = maximum - minimum
        if isInteger,
           minimum.rounded() == minimum,
           maximum.rounded() == maximum,
           levelCount > 1,
           span == Double(levelCount - 1),
           rawScore >= 0, rawScore <= Double(levelCount - 1) {
            return minimum + rawScore
        }

        if rawScore >= minimum && rawScore <= maximum {
            return rawScore
        }

        if levelCount > 1, rawScore >= 0, rawScore <= Double(levelCount - 1) {
            return minimum + (rawScore / Double(levelCount - 1)) * span
        }

        if rawScore >= 0, rawScore <= span {
            return minimum + rawScore
        }

        return Swift.min(Swift.max(rawScore, minimum), maximum)
    }

    private func shiftedLevels<T>(
        _ source: [Int: T],
        minimum: Double?,
        maximum: Double?,
        isInteger: Bool,
        levelCount: Int
    ) -> [Int: T] {
        guard isInteger,
              let minimum,
              let maximum,
              minimum.rounded() == minimum,
              maximum.rounded() == maximum,
              levelCount > 1,
              (maximum - minimum) == Double(levelCount - 1),
              source.keys.allSatisfy({ (0...(levelCount - 1)).contains($0) }) else {
            return source
        }

        let offset = Int(minimum)
        return Dictionary(uniqueKeysWithValues: source.map { (key, value) in
            (key + offset, value)
        })
    }
}
