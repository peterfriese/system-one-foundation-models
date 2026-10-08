import Foundation

// MARK: - Request DTOs

/// Wire format request payload for the OpenAI Decisions API (`POST /v1/decisions`).
public struct OpenAIDecisionsRequest: Codable, Sendable, Equatable {
    /// The target model identifier (e.g. `gpt-6-luna`).
    public let model: String

    /// The input payload, either text-only or multimodal with messages.
    public let input: InputPayload

    /// Ordered list of question specifications to evaluate.
    public let questions: [OpenAIDecisionsQuestion]

    public init(
        model: String = "gpt-6-luna",
        input: InputPayload,
        questions: [OpenAIDecisionsQuestion]
    ) {
        self.model = model
        self.input = input
        self.questions = questions
    }

    /// Input payload representation: either a single text prompt or multimodal messages.
    public enum InputPayload: Codable, Sendable, Equatable {
        case text(String)
        case multimodal([Message])

        public struct Message: Codable, Sendable, Equatable {
            public let role: String
            public let content: [ContentBlock]

            public init(role: String = "user", content: [ContentBlock]) {
                self.role = role
                self.content = content
            }
        }

        public enum ContentBlock: Codable, Sendable, Equatable {
            case inputText(String)
            case inputImage(dataURL: String)

            private enum CodingKeys: String, CodingKey {
                case type
                case text
                case imageURL = "image_url"
            }

            public func encode(to encoder: Encoder) throws {
                var container = encoder.container(keyedBy: CodingKeys.self)
                switch self {
                case .inputText(let text):
                    try container.encode("input_text", forKey: .type)
                    try container.encode(text, forKey: .text)
                case .inputImage(let dataURL):
                    try container.encode("input_image", forKey: .type)
                    try container.encode(dataURL, forKey: .imageURL)
                }
            }

            public init(from decoder: Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)
                let type = try container.decode(String.self, forKey: .type)
                switch type {
                case "input_text":
                    let text = try container.decode(String.self, forKey: .text)
                    self = .inputText(text)
                case "input_image":
                    let url = try container.decode(String.self, forKey: .imageURL)
                    self = .inputImage(dataURL: url)
                default:
                    throw DecodingError.dataCorruptedError(
                        forKey: .type,
                        in: container,
                        debugDescription: "Unknown content block type: \(type)"
                    )
                }
            }
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.singleValueContainer()
            switch self {
            case .text(let string):
                try container.encode(string)
            case .multimodal(let messages):
                try container.encode(messages)
            }
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let string = try? container.decode(String.self) {
                self = .text(string)
            } else if let messages = try? container.decode([Message].self) {
                self = .multimodal(messages)
            } else {
                throw DecodingError.dataCorruptedError(
                    in: container,
                    debugDescription: "Expected String or [Message] for input"
                )
            }
        }
    }
}

/// A single question specification sent to the OpenAI Decisions API.
public struct OpenAIDecisionsQuestion: Codable, Sendable, Equatable {
    /// Primitive type: `"predicate"`, `"choice"`, or `"score"`.
    public let type: String

    /// Identifier name matching the schema property key.
    public let name: String

    /// Natural language instructions for this question.
    public let instructions: String

    /// Candidate choices for `"choice"` questions.
    public let choices: [ChoiceItem]?

    /// Discrete scoring rubric levels for `"score"` questions.
    public let levels: [LevelItem]?

    public init(
        type: String,
        name: String,
        instructions: String,
        choices: [ChoiceItem]? = nil,
        levels: [LevelItem]? = nil
    ) {
        self.type = type
        self.name = name
        self.instructions = instructions
        self.choices = choices
        self.levels = levels
    }

    public struct ChoiceItem: Codable, Sendable, Equatable {
        public let value: String
        public let description: String

        public init(value: String, description: String) {
            self.value = value
            self.description = description
        }
    }

    public struct LevelItem: Codable, Sendable, Equatable {
        public let label: String
        public let description: String

        public init(label: String, description: String) {
            self.label = label
            self.description = description
        }
    }
}

// MARK: - Response DTOs

/// Wire format response payload from the OpenAI Decisions API (`POST /v1/decisions`).
public struct OpenAIDecisionsResponse: Codable, Sendable, Equatable {
    public let id: String?
    public let object: String?
    public let model: String
    public let answers: [OpenAIDecisionsAnswer]
    public let usage: Usage?

    private enum CodingKeys: String, CodingKey {
        case id
        case object
        case model
        case answers
        case usage
    }

    public init(
        id: String? = nil,
        object: String? = "decision",
        model: String = "gpt-6-luna",
        answers: [OpenAIDecisionsAnswer] = [],
        usage: Usage? = nil
    ) {
        self.id = id
        self.object = object
        self.model = model
        self.answers = answers
        self.usage = usage
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decodeIfPresent(String.self, forKey: .id)
        self.object = try container.decodeIfPresent(String.self, forKey: .object)
        self.model = try container.decodeIfPresent(String.self, forKey: .model) ?? "gpt-6-luna"
        self.answers = try container.decodeIfPresent([OpenAIDecisionsAnswer].self, forKey: .answers) ?? []
        self.usage = try container.decodeIfPresent(Usage.self, forKey: .usage)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(id, forKey: .id)
        try container.encodeIfPresent(object, forKey: .object)
        try container.encode(model, forKey: .model)
        try container.encode(answers, forKey: .answers)
        try container.encodeIfPresent(usage, forKey: .usage)
    }

    public struct Usage: Codable, Sendable, Equatable {
        public let inputTokens: Int
        public let outputTokens: Int

        private enum CodingKeys: String, CodingKey {
            case inputTokens = "input_tokens"
            case outputTokens = "output_tokens"
        }

        public init(inputTokens: Int = 0, outputTokens: Int = 0) {
            self.inputTokens = inputTokens
            self.outputTokens = outputTokens
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.inputTokens = try container.decodeIfPresent(Int.self, forKey: .inputTokens) ?? 0
            self.outputTokens = try container.decodeIfPresent(Int.self, forKey: .outputTokens) ?? 0
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(inputTokens, forKey: .inputTokens)
            try container.encode(outputTokens, forKey: .outputTokens)
        }
    }
}

/// Calibrated answer payload for a single question from the OpenAI Decisions API.
public struct OpenAIDecisionsAnswer: Codable, Sendable, Equatable {
    public let name: String
    public let type: String?
    public let probability: Double?
    public let choice: String?
    public let score: Double?
    public let confidence: Double?
    public let refusal: String?
    public let probabilities: [ProbabilityEntry]?

    private enum CodingKeys: String, CodingKey {
        case name
        case type
        case probability
        case choice
        case score
        case confidence
        case refusal
        case probabilities
    }

    public init(
        name: String,
        type: String? = nil,
        probability: Double? = nil,
        choice: String? = nil,
        score: Double? = nil,
        confidence: Double? = nil,
        refusal: String? = nil,
        probabilities: [ProbabilityEntry]? = nil
    ) {
        self.name = name
        self.type = type
        self.probability = probability
        self.choice = choice
        self.score = score
        self.confidence = confidence
        self.refusal = refusal
        self.probabilities = probabilities
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.name = try container.decode(String.self, forKey: .name)
        self.type = try container.decodeIfPresent(String.self, forKey: .type)

        // Make probability decode flexibly (support Double or Int)
        if let d = try? container.decodeIfPresent(Double.self, forKey: .probability) {
            self.probability = d
        } else if let i = try? container.decodeIfPresent(Int.self, forKey: .probability) {
            self.probability = Double(i)
        } else {
            self.probability = nil
        }

        // Make choice decode flexibly (if OpenAI returns a number or bool for a choice, convert to String)
        if let str = try? container.decodeIfPresent(String.self, forKey: .choice) {
            self.choice = str
        } else if let intVal = try? container.decodeIfPresent(Int.self, forKey: .choice) {
            self.choice = String(intVal)
        } else if let doubleVal = try? container.decodeIfPresent(Double.self, forKey: .choice) {
            self.choice = String(doubleVal)
        } else if let boolVal = try? container.decodeIfPresent(Bool.self, forKey: .choice) {
            self.choice = String(boolVal)
        } else {
            self.choice = nil
        }

        // Make score decode flexibly (support Int or Double)
        if let d = try? container.decodeIfPresent(Double.self, forKey: .score) {
            self.score = d
        } else if let i = try? container.decodeIfPresent(Int.self, forKey: .score) {
            self.score = Double(i)
        } else {
            self.score = nil
        }

        // Decode confidence flexibly (support Double or Int)
        if let d = try? container.decodeIfPresent(Double.self, forKey: .confidence) {
            self.confidence = d
        } else if let i = try? container.decodeIfPresent(Int.self, forKey: .confidence) {
            self.confidence = Double(i)
        } else {
            self.confidence = nil
        }

        self.refusal = try container.decodeIfPresent(String.self, forKey: .refusal)

        // In probabilities: support decoding either an array [ProbabilityEntry] OR a dictionary [String: Double] if OpenAI sends either format.
        if container.contains(.probabilities) && (try? container.decodeNil(forKey: .probabilities)) == false {
            if let entries = try? container.decode([ProbabilityEntry].self, forKey: .probabilities) {
                self.probabilities = entries
            } else if let dict = try? container.decode([String: Double].self, forKey: .probabilities) {
                self.probabilities = dict.sorted(by: { $0.key < $1.key }).map {
                    ProbabilityEntry(value: $0.key, probability: $0.value)
                }
            } else if let intDict = try? container.decode([String: Int].self, forKey: .probabilities) {
                self.probabilities = intDict.sorted(by: { $0.key < $1.key }).map {
                    ProbabilityEntry(value: $0.key, probability: Double($0.value))
                }
            } else {
                self.probabilities = nil
            }
        } else {
            self.probabilities = nil
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        try container.encodeIfPresent(type, forKey: .type)
        try container.encodeIfPresent(probability, forKey: .probability)
        try container.encodeIfPresent(choice, forKey: .choice)
        try container.encodeIfPresent(score, forKey: .score)
        try container.encodeIfPresent(confidence, forKey: .confidence)
        try container.encodeIfPresent(refusal, forKey: .refusal)
        try container.encodeIfPresent(probabilities, forKey: .probabilities)
    }

    public struct ProbabilityEntry: Codable, Sendable, Equatable {
        public let value: String
        public let probability: Double
        public let label: String?

        private enum CodingKeys: String, CodingKey {
            case value
            case probability
            case label
        }

        public init(value: String, probability: Double, label: String? = nil) {
            self.value = value
            self.probability = probability
            self.label = label
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.probability = try container.decode(Double.self, forKey: .probability)
            self.label = try container.decodeIfPresent(String.self, forKey: .label)
            if let stringValue = try? container.decode(String.self, forKey: .value) {
                self.value = stringValue
            } else if let intValue = try? container.decode(Int.self, forKey: .value) {
                self.value = String(intValue)
            } else if let doubleValue = try? container.decode(Double.self, forKey: .value) {
                self.value = String(doubleValue)
            } else {
                self.value = try container.decode(String.self, forKey: .value)
            }
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(value, forKey: .value)
            try container.encode(probability, forKey: .probability)
            if let label {
                try container.encode(label, forKey: .label)
            }
        }
    }
}

// MARK: - Error Envelope DTO

/// Standard OpenAI API error envelope.
public struct OpenAIErrorEnvelope: Codable, Sendable {
    public struct ErrorDetail: Codable, Sendable {
        public let message: String?
        public let type: String?
        public let param: String?
        public let code: String?

        public init(message: String?, type: String? = nil, param: String? = nil, code: String? = nil) {
            self.message = message
            self.type = type
            self.param = param
            self.code = code
        }
    }

    public let error: ErrorDetail?

    public init(error: ErrorDetail?) {
        self.error = error
    }
}
