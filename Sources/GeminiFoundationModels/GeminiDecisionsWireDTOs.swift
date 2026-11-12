import Foundation

// MARK: - Request DTOs

/// Wire format request payload for the Google Gemini Decisions API (`POST /v1beta/decisions`).
///
/// See tech-notes/0018-gemini-decisions-api-architecture.md
public struct GeminiDecisionsRequest: Codable, Sendable, Equatable {
    /// The target model identifier (e.g. `gemini-decision-1`).
    public let model: String

    /// The input payload, either a plain text string or multimodal content parts.
    public let input: InputPayload

    /// Dictionary of named question specifications to evaluate in a single forward pass.
    public let questions: [String: GeminiDecisionsQuestion]

    public init(
        model: String = "gemini-decision-1",
        input: InputPayload,
        questions: [String: GeminiDecisionsQuestion]
    ) {
        self.model = model
        self.input = input
        self.questions = questions
    }

    /// Input payload representation: either a plain text string or a flat array of typed multimodal content items (`{"type": "text", ...}`, `{"type": "image", ...}`).
    public enum InputPayload: Codable, Sendable, Equatable {
        case text(String)
        case multimodal([ContentItem])

        public typealias Content = ContentItem

        public enum ContentItem: Codable, Sendable, Equatable {
            case text(String)
            case image(mimeType: String, data: String)

            private enum CodingKeys: String, CodingKey {
                case type
                case text
                case mimeType = "mime_type"
                case data
                case inlineData = "inline_data"
            }

            public func encode(to encoder: Encoder) throws {
                var container = encoder.container(keyedBy: CodingKeys.self)
                switch self {
                case .text(let text):
                    try container.encode("text", forKey: .type)
                    try container.encode(text, forKey: .text)
                case .image(let mimeType, let data):
                    try container.encode("image", forKey: .type)
                    try container.encode(mimeType, forKey: .mimeType)
                    try container.encode(data, forKey: .data)
                }
            }

            public init(from decoder: Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)
                if let type = try container.decodeIfPresent(String.self, forKey: .type) {
                    switch type {
                    case "text":
                        let text = try container.decode(String.self, forKey: .text)
                        self = .text(text)
                    case "image":
                        if let data = try container.decodeIfPresent(String.self, forKey: .data) {
                            let mimeType = try container.decodeIfPresent(String.self, forKey: .mimeType) ?? "image/png"
                            self = .image(mimeType: mimeType, data: data)
                        } else if let inline = try container.decodeIfPresent(Part.InlineData.self, forKey: .inlineData) {
                            self = .image(mimeType: inline.mimeType, data: inline.data)
                        } else {
                            throw DecodingError.dataCorruptedError(
                                forKey: .data,
                                in: container,
                                debugDescription: "Expected 'data' in Gemini image ContentItem"
                            )
                        }
                    default:
                        throw DecodingError.dataCorruptedError(
                            forKey: .type,
                            in: container,
                            debugDescription: "Unsupported Gemini ContentItem type: \(type)"
                        )
                    }
                } else if let text = try container.decodeIfPresent(String.self, forKey: .text) {
                    self = .text(text)
                } else if let inline = try container.decodeIfPresent(Part.InlineData.self, forKey: .inlineData) {
                    self = .image(mimeType: inline.mimeType, data: inline.data)
                } else {
                    throw DecodingError.dataCorrupted(
                        DecodingError.Context(
                            codingPath: decoder.codingPath,
                            debugDescription: "Expected 'type' ('text' or 'image') in Gemini ContentItem"
                        )
                    )
                }
            }
        }

        /// Legacy Gemini `generateContent` part envelope retained for decoding backward compatibility.
        public enum Part: Codable, Sendable, Equatable {
            case text(String)
            case inlineData(mimeType: String, data: String)

            public struct InlineData: Codable, Sendable, Equatable {
                public let mimeType: String
                public let data: String

                private enum CodingKeys: String, CodingKey {
                    case mimeType = "mime_type"
                    case data
                }

                public init(mimeType: String, data: String) {
                    self.mimeType = mimeType
                    self.data = data
                }
            }

            private enum CodingKeys: String, CodingKey {
                case text
                case inlineData = "inline_data"
            }

            public func encode(to encoder: Encoder) throws {
                var container = encoder.container(keyedBy: CodingKeys.self)
                switch self {
                case .text(let text):
                    try container.encode(text, forKey: .text)
                case .inlineData(let mimeType, let data):
                    try container.encode(InlineData(mimeType: mimeType, data: data), forKey: .inlineData)
                }
            }

            public init(from decoder: Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)
                if let text = try container.decodeIfPresent(String.self, forKey: .text) {
                    self = .text(text)
                } else if let inline = try container.decodeIfPresent(InlineData.self, forKey: .inlineData) {
                    self = .inlineData(mimeType: inline.mimeType, data: inline.data)
                } else {
                    throw DecodingError.dataCorrupted(
                        DecodingError.Context(
                            codingPath: decoder.codingPath,
                            debugDescription: "Expected 'text' or 'inline_data' in Gemini Part"
                        )
                    )
                }
            }
        }

        private struct LegacyPartsBlock: Decodable {
            let role: String?
            let parts: [Part]
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.singleValueContainer()
            switch self {
            case .text(let string):
                try container.encode(string)
            case .multimodal(let contents):
                try container.encode(contents)
            }
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let string = try? container.decode(String.self) {
                self = .text(string)
            } else if let contents = try? container.decode([ContentItem].self) {
                self = .multimodal(contents)
            } else if let legacyBlocks = try? container.decode([LegacyPartsBlock].self) {
                let flattened = legacyBlocks.flatMap { block in
                    block.parts.map { part -> ContentItem in
                        switch part {
                        case .text(let text):
                            return .text(text)
                        case .inlineData(let mimeType, let data):
                            return .image(mimeType: mimeType, data: data)
                        }
                    }
                }
                self = .multimodal(flattened)
            } else {
                throw DecodingError.dataCorruptedError(
                    in: container,
                    debugDescription: "Expected String or [ContentItem] for Gemini input"
                )
            }
        }
    }
}

/// A single question specification sent to the Google Gemini Decisions API.
public struct GeminiDecisionsQuestion: Codable, Sendable, Equatable {
    /// Primitive type: `"noul"`, `"choice"`, or `"score"`.
    public let type: String

    /// Natural language instructions for evaluating this question.
    public let instructions: String

    /// Criteria payload: `.noul(trueDescription:falseDescription:)`, `.choice([String: String])`, or `.score([String])`.
    public let criteria: QuestionCriteria?

    public typealias CriteriaPayload = QuestionCriteria

    public enum QuestionCriteria: Codable, Sendable, Equatable {
        case noul(trueDescription: String?, falseDescription: String?)
        case choice([String: String])
        case score([String])

        private enum NoulCodingKeys: String, CodingKey {
            case trueDescription = "true_description"
            case falseDescription = "false_description"
        }

        public func encode(to encoder: Encoder) throws {
            switch self {
            case .noul(let trueDesc, let falseDesc):
                var container = encoder.container(keyedBy: NoulCodingKeys.self)
                try container.encodeIfPresent(trueDesc, forKey: .trueDescription)
                try container.encodeIfPresent(falseDesc, forKey: .falseDescription)
            case .choice(let dict):
                var container = encoder.singleValueContainer()
                try container.encode(dict)
            case .score(let list):
                var container = encoder.singleValueContainer()
                try container.encode(list)
            }
        }

        public init(from decoder: Decoder) throws {
            let singleContainer = try decoder.singleValueContainer()
            if let list = try? singleContainer.decode([String].self) {
                self = .score(list)
                return
            }
            if let dict = try? singleContainer.decode([String: String].self) {
                if dict["true_description"] != nil || dict["false_description"] != nil,
                   dict.keys.allSatisfy({ $0 == "true_description" || $0 == "false_description" }) {
                    self = .noul(
                        trueDescription: dict["true_description"],
                        falseDescription: dict["false_description"]
                    )
                } else {
                    self = .choice(dict)
                }
                return
            }
            throw DecodingError.dataCorruptedError(
                in: singleContainer,
                debugDescription: "Expected noul criteria, [String: String], or [String] for question criteria"
            )
        }
    }

    private enum CodingKeys: String, CodingKey {
        case type
        case instructions
        case criteria
        case choices
        case levels
    }

    public init(
        type: String,
        instructions: String,
        criteria: QuestionCriteria? = nil
    ) {
        self.type = type
        self.instructions = instructions
        self.criteria = criteria
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.type = try container.decode(String.self, forKey: .type)
        self.instructions = try container.decode(String.self, forKey: .instructions)

        if let decodedCriteria = try container.decodeIfPresent(QuestionCriteria.self, forKey: .criteria) {
            if self.type == "choice", case .score(let list) = decodedCriteria {
                let mapped = Dictionary(uniqueKeysWithValues: list.map { ($0, $0) })
                self.criteria = .choice(mapped)
            } else {
                self.criteria = decodedCriteria
            }
        } else if let choicesList = try? container.decodeIfPresent([String].self, forKey: .choices) {
            let mapped = Dictionary(uniqueKeysWithValues: choicesList.map { ($0, $0) })
            self.criteria = .choice(mapped)
        } else if let choicesDict = try? container.decodeIfPresent([String: String].self, forKey: .choices) {
            self.criteria = .choice(choicesDict)
        } else if let levelsList = try? container.decodeIfPresent([String].self, forKey: .levels) {
            self.criteria = .score(levelsList)
        } else {
            self.criteria = nil
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(type, forKey: .type)
        try container.encode(instructions, forKey: .instructions)
        try container.encodeIfPresent(criteria, forKey: .criteria)
    }
}

// MARK: - Response DTOs

/// Wire format response payload from the Google Gemini Decisions API (`POST /v1beta/decisions`).
public struct GeminiDecisionsResponse: Codable, Sendable, Equatable {
    public let id: String?
    public let model: String
    public let answers: [String: GeminiDecisionsAnswer]
    public let usage: Usage?
    public let usageMetadata: UsageMetadata?

    /// Resolves token usage from either `usage` (`input_tokens` / `output_tokens`) or `usageMetadata` (`promptTokenCount` / `candidatesTokenCount`).
    public var resolvedUsage: Usage? {
        if let usage {
            return usage
        }
        if let usageMetadata {
            return Usage(
                inputTokens: usageMetadata.promptTokenCount,
                outputTokens: usageMetadata.candidatesTokenCount
            )
        }
        return nil
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case model
        case modelVersion
        case answers
        case usage
        case usageMetadata
    }

    public init(
        id: String? = nil,
        model: String = "gemini-decision-1",
        answers: [String: GeminiDecisionsAnswer] = [:],
        usage: Usage? = nil,
        usageMetadata: UsageMetadata? = nil
    ) {
        self.id = id
        self.model = model
        self.answers = answers
        self.usage = usage
        self.usageMetadata = usageMetadata
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decodeIfPresent(String.self, forKey: .id)
        if let model = try container.decodeIfPresent(String.self, forKey: .model) {
            self.model = model
        } else if let modelVersion = try container.decodeIfPresent(String.self, forKey: .modelVersion) {
            self.model = modelVersion
        } else {
            self.model = "gemini-decision-1"
        }
        self.answers = try container.decodeIfPresent([String: GeminiDecisionsAnswer].self, forKey: .answers) ?? [:]
        self.usageMetadata = try container.decodeIfPresent(UsageMetadata.self, forKey: .usageMetadata)
        if let directUsage = try container.decodeIfPresent(Usage.self, forKey: .usage) {
            self.usage = directUsage
        } else if let metadata = self.usageMetadata {
            self.usage = Usage(
                inputTokens: metadata.promptTokenCount,
                outputTokens: metadata.candidatesTokenCount
            )
        } else {
            self.usage = nil
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(id, forKey: .id)
        try container.encode(model, forKey: .model)
        try container.encode(answers, forKey: .answers)
        try container.encodeIfPresent(usage, forKey: .usage)
        try container.encodeIfPresent(usageMetadata, forKey: .usageMetadata)
    }

    /// Token usage telemetry supporting both snake_case (`usage`) and Gemini camelCase (`usageMetadata`).
    public struct Usage: Codable, Sendable, Equatable {
        public let inputTokens: Int
        public let outputTokens: Int

        private enum CodingKeys: String, CodingKey {
            case inputTokens = "input_tokens"
            case outputTokens = "output_tokens"
            case totalInputTokens = "total_input_tokens"
            case totalOutputTokens = "total_output_tokens"
            case totalTokens = "total_tokens"
            case promptTokenCount
            case candidatesTokenCount
        }

        public init(inputTokens: Int = 0, outputTokens: Int = 0) {
            self.inputTokens = inputTokens
            self.outputTokens = outputTokens
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            if let input = try container.decodeIfPresent(Int.self, forKey: .inputTokens) {
                self.inputTokens = input
            } else if let totalInput = try container.decodeIfPresent(Int.self, forKey: .totalInputTokens) {
                self.inputTokens = totalInput
            } else if let prompt = try container.decodeIfPresent(Int.self, forKey: .promptTokenCount) {
                self.inputTokens = prompt
            } else if let total = try container.decodeIfPresent(Int.self, forKey: .totalTokens) {
                self.inputTokens = total
            } else {
                self.inputTokens = 0
            }

            if let output = try container.decodeIfPresent(Int.self, forKey: .outputTokens) {
                self.outputTokens = output
            } else if let totalOutput = try container.decodeIfPresent(Int.self, forKey: .totalOutputTokens) {
                self.outputTokens = totalOutput
            } else if let candidates = try container.decodeIfPresent(Int.self, forKey: .candidatesTokenCount) {
                self.outputTokens = candidates
            } else {
                self.outputTokens = 0
            }
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(inputTokens, forKey: .inputTokens)
            try container.encode(outputTokens, forKey: .outputTokens)
        }
    }

    /// Standard Gemini API `usageMetadata` object (`promptTokenCount`, `candidatesTokenCount`, `totalTokenCount`).
    public struct UsageMetadata: Codable, Sendable, Equatable {
        public let promptTokenCount: Int
        public let candidatesTokenCount: Int
        public let totalTokenCount: Int

        private enum CodingKeys: String, CodingKey {
            case promptTokenCount
            case candidatesTokenCount
            case totalTokenCount
        }

        public init(
            promptTokenCount: Int = 0,
            candidatesTokenCount: Int = 0,
            totalTokenCount: Int? = nil
        ) {
            self.promptTokenCount = promptTokenCount
            self.candidatesTokenCount = candidatesTokenCount
            self.totalTokenCount = totalTokenCount ?? (promptTokenCount + candidatesTokenCount)
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let prompt = try container.decodeIfPresent(Int.self, forKey: .promptTokenCount) ?? 0
            let candidates = try container.decodeIfPresent(Int.self, forKey: .candidatesTokenCount) ?? 0
            self.promptTokenCount = prompt
            self.candidatesTokenCount = candidates
            self.totalTokenCount = try container.decodeIfPresent(Int.self, forKey: .totalTokenCount) ?? (prompt + candidates)
        }
    }
}

/// Calibrated answer payload for a single question from the Google Gemini Decisions API.
public struct GeminiDecisionsAnswer: Codable, Sendable, Equatable {
    public let type: String?
    public let noul: Double?
    public let probability: Double?
    public let choice: String?
    public let selected: String?
    public let score: Double?
    public let confidence: Double?
    public let refusal: String?
    public let probabilities: [String: Double]?
    public let legend: [String: String]?

    private enum CodingKeys: String, CodingKey {
        case type
        case noul
        case probability
        case choice
        case selected
        case score
        case confidence
        case refusal
        case probabilities
        case legend
    }

    private struct ProbabilityItem: Decodable {
        let key: String
        let probability: Double
        let label: String?

        private enum ItemKeys: String, CodingKey {
            case value
            case choice
            case key
            case probability
            case label
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: ItemKeys.self)
            if let d = try? container.decode(Double.self, forKey: .probability) {
                self.probability = d
            } else if let i = try? container.decode(Int.self, forKey: .probability) {
                self.probability = Double(i)
            } else {
                self.probability = try container.decode(Double.self, forKey: .probability)
            }

            self.label = try container.decodeIfPresent(String.self, forKey: .label)

            if let str = try? container.decode(String.self, forKey: .value) {
                self.key = str
            } else if let i = try? container.decode(Int.self, forKey: .value) {
                self.key = String(i)
            } else if let d = try? container.decode(Double.self, forKey: .value) {
                self.key = String(d)
            } else if let str = try? container.decode(String.self, forKey: .choice) {
                self.key = str
            } else if let str = try? container.decode(String.self, forKey: .key) {
                self.key = str
            } else {
                self.key = try container.decode(String.self, forKey: .value)
            }
        }
    }

    public init(
        type: String? = nil,
        noul: Double? = nil,
        probability: Double? = nil,
        choice: String? = nil,
        selected: String? = nil,
        score: Double? = nil,
        confidence: Double? = nil,
        refusal: String? = nil,
        probabilities: [String: Double]? = nil,
        legend: [String: String]? = nil
    ) {
        self.type = type
        let resolvedNoul = noul ?? probability
        self.noul = resolvedNoul
        self.probability = probability ?? resolvedNoul
        let resolvedChoice = choice ?? selected
        self.choice = resolvedChoice
        self.selected = selected ?? resolvedChoice
        self.score = score
        self.confidence = confidence
        self.refusal = refusal
        self.probabilities = probabilities
        self.legend = legend
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.type = try container.decodeIfPresent(String.self, forKey: .type)

        // Decode boolean probability from either "noul" or "probability" (Double or Int)
        let decodedNoul: Double?
        if let d = try? container.decodeIfPresent(Double.self, forKey: .noul) {
            decodedNoul = d
        } else if let i = try? container.decodeIfPresent(Int.self, forKey: .noul) {
            decodedNoul = Double(i)
        } else {
            decodedNoul = nil
        }

        let decodedProb: Double?
        if let d = try? container.decodeIfPresent(Double.self, forKey: .probability) {
            decodedProb = d
        } else if let i = try? container.decodeIfPresent(Int.self, forKey: .probability) {
            decodedProb = Double(i)
        } else {
            decodedProb = nil
        }

        self.noul = decodedNoul ?? decodedProb
        self.probability = decodedProb ?? decodedNoul

        // Decode categorical choice from either "choice" or "selected" (String, Int, Double, or Bool)
        let decodedChoice: String?
        if let str = try? container.decodeIfPresent(String.self, forKey: .choice) {
            decodedChoice = str
        } else if let intVal = try? container.decodeIfPresent(Int.self, forKey: .choice) {
            decodedChoice = String(intVal)
        } else if let doubleVal = try? container.decodeIfPresent(Double.self, forKey: .choice) {
            decodedChoice = String(doubleVal)
        } else if let boolVal = try? container.decodeIfPresent(Bool.self, forKey: .choice) {
            decodedChoice = String(boolVal)
        } else {
            decodedChoice = nil
        }

        let decodedSelected: String?
        if let str = try? container.decodeIfPresent(String.self, forKey: .selected) {
            decodedSelected = str
        } else if let intVal = try? container.decodeIfPresent(Int.self, forKey: .selected) {
            decodedSelected = String(intVal)
        } else if let doubleVal = try? container.decodeIfPresent(Double.self, forKey: .selected) {
            decodedSelected = String(doubleVal)
        } else if let boolVal = try? container.decodeIfPresent(Bool.self, forKey: .selected) {
            decodedSelected = String(boolVal)
        } else {
            decodedSelected = nil
        }

        self.choice = decodedChoice ?? decodedSelected
        self.selected = decodedSelected ?? decodedChoice

        // Decode score flexibly (Double or Int)
        if let d = try? container.decodeIfPresent(Double.self, forKey: .score) {
            self.score = d
        } else if let i = try? container.decodeIfPresent(Int.self, forKey: .score) {
            self.score = Double(i)
        } else {
            self.score = nil
        }

        // Decode confidence flexibly (Double or Int)
        if let d = try? container.decodeIfPresent(Double.self, forKey: .confidence) {
            self.confidence = d
        } else if let i = try? container.decodeIfPresent(Int.self, forKey: .confidence) {
            self.confidence = Double(i)
        } else {
            self.confidence = nil
        }

        self.refusal = try container.decodeIfPresent(String.self, forKey: .refusal)

        // Decode legend from either [String: String] or [String]
        var decodedLegend: [String: String]? = nil
        if container.contains(.legend) && (try? container.decodeNil(forKey: .legend)) == false {
            if let dict = try? container.decode([String: String].self, forKey: .legend) {
                decodedLegend = dict
            } else if let list = try? container.decode([String].self, forKey: .legend) {
                decodedLegend = Dictionary(uniqueKeysWithValues: list.enumerated().map { (String($0.offset), $0.element) })
            }
        }

        // Decode probabilities from [String: Double], [String: Int], [Double], or [ProbabilityItem]
        if container.contains(.probabilities) && (try? container.decodeNil(forKey: .probabilities)) == false {
            if let dict = try? container.decode([String: Double].self, forKey: .probabilities) {
                self.probabilities = dict
            } else if let intDict = try? container.decode([String: Int].self, forKey: .probabilities) {
                self.probabilities = intDict.mapValues { Double($0) }
            } else if let items = try? container.decode([ProbabilityItem].self, forKey: .probabilities) {
                self.probabilities = Dictionary(
                    items.map { ($0.key, $0.probability) },
                    uniquingKeysWith: { current, _ in current }
                )
                if decodedLegend == nil {
                    let extractedLegend = Dictionary(
                        items.compactMap { item -> (String, String)? in
                            guard let label = item.label else { return nil }
                            return (item.key, label)
                        },
                        uniquingKeysWith: { current, _ in current }
                    )
                    if !extractedLegend.isEmpty {
                        decodedLegend = extractedLegend
                    }
                }
            } else if let doubleList = try? container.decode([Double].self, forKey: .probabilities) {
                self.probabilities = Dictionary(
                    uniqueKeysWithValues: doubleList.enumerated().map { (String($0.offset), $0.element) }
                )
            } else {
                self.probabilities = nil
            }
        } else {
            self.probabilities = nil
        }

        self.legend = decodedLegend
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(type, forKey: .type)
        try container.encodeIfPresent(noul, forKey: .noul)
        try container.encodeIfPresent(choice, forKey: .choice)
        try container.encodeIfPresent(score, forKey: .score)
        try container.encodeIfPresent(confidence, forKey: .confidence)
        try container.encodeIfPresent(refusal, forKey: .refusal)
        try container.encodeIfPresent(probabilities, forKey: .probabilities)
        try container.encodeIfPresent(legend, forKey: .legend)
    }
}

// MARK: - Google RPC Error Envelope DTO

/// Standard Google Cloud / Generative Language API RPC error envelope.
public struct GeminiErrorEnvelope: Codable, Sendable, Equatable {
    public struct ErrorDetail: Codable, Sendable, Equatable {
        public let code: Int?
        public let message: String?
        public let status: String?

        public init(code: Int? = nil, message: String? = nil, status: String? = nil) {
            self.code = code
            self.message = message
            self.status = status
        }
    }

    public let error: ErrorDetail?

    public init(error: ErrorDetail?) {
        self.error = error
    }
}
