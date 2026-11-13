import Foundation
import FoundationModels

// MARK: - LanguageModelSession System One Ergonomic Decision Shortcuts

public extension LanguageModelSession {
    /// Evaluates the probability of truth (0.0 to 1.0) for a statement given context state.
    func probability(
        of instructions: String,
        state: String,
        criteria: (whenTrue: String, whenFalse: String)? = nil
    ) async throws -> Double {
        let schema = try DynamicDecisionSchema.makeBinarySchema(
            instructions: instructions,
            whenTrue: criteria?.whenTrue,
            whenFalse: criteria?.whenFalse
        )
        let response = try await self.respond(to: state, schema: schema)
        return Self.decodeProbabilityResponse(response)
    }

    /// Evaluates the probability of truth (0.0 to 1.0) for a statement given a multimodal `Prompt`.
    func probability(
        of instructions: String,
        prompt: Prompt,
        criteria: (whenTrue: String, whenFalse: String)? = nil
    ) async throws -> Double {
        let schema = try DynamicDecisionSchema.makeBinarySchema(
            instructions: instructions,
            whenTrue: criteria?.whenTrue,
            whenFalse: criteria?.whenFalse
        )
        let response = try await self.respond(to: prompt, schema: schema)
        return Self.decodeProbabilityResponse(response)
    }

    /// Evaluates the probability of truth (0.0 to 1.0) for a statement using a `@PromptBuilder` closure.
    func probability(
        of instructions: String,
        criteria: (whenTrue: String, whenFalse: String)? = nil,
        @PromptBuilder prompt: () throws -> Prompt
    ) async throws -> Double {
        let builtPrompt = try prompt()
        return try await probability(of: instructions, prompt: builtPrompt, criteria: criteria)
    }

    /// Evaluates a discrete categorical decision among cases of a `Choosable` enum.
    func choice<Option: Choosable>(
        _ instructions: String,
        from type: Option.Type = Option.self,
        state: String
    ) async throws -> Choice<Option> {
        let schema = try Self.buildChoosableSchema(instructions: instructions, type: type)
        let response = try await self.respond(to: state, schema: schema)
        return Self.decodeChoosableResponse(response, type: type)
    }

    /// Evaluates a discrete categorical decision among cases of a `Choosable` enum given a multimodal `Prompt`.
    func choice<Option: Choosable>(
        _ instructions: String,
        from type: Option.Type = Option.self,
        prompt: Prompt
    ) async throws -> Choice<Option> {
        let schema = try Self.buildChoosableSchema(instructions: instructions, type: type)
        let response = try await self.respond(to: prompt, schema: schema)
        return Self.decodeChoosableResponse(response, type: type)
    }

    /// Evaluates a discrete categorical decision among cases of a `Choosable` enum using a `@PromptBuilder` closure.
    func choice<Option: Choosable>(
        _ instructions: String,
        from type: Option.Type = Option.self,
        @PromptBuilder prompt: () throws -> Prompt
    ) async throws -> Choice<Option> {
        let builtPrompt = try prompt()
        return try await choice(instructions, from: type, prompt: builtPrompt)
    }

    /// Evaluates a discrete categorical decision among dynamic string options.
    func choice(
        _ instructions: String,
        options: [String],
        state: String
    ) async throws -> Choice<String> {
        let schema = try Self.buildStringChoiceSchema(instructions: instructions, options: options)
        let response = try await self.respond(to: state, schema: schema)
        return Self.decodeStringChoiceResponse(response, options: options)
    }

    /// Evaluates a discrete categorical decision among dynamic string options given a multimodal `Prompt`.
    func choice(
        _ instructions: String,
        options: [String],
        prompt: Prompt
    ) async throws -> Choice<String> {
        let schema = try Self.buildStringChoiceSchema(instructions: instructions, options: options)
        let response = try await self.respond(to: prompt, schema: schema)
        return Self.decodeStringChoiceResponse(response, options: options)
    }

    /// Evaluates a discrete categorical decision among dynamic string options using a `@PromptBuilder` closure.
    func choice(
        _ instructions: String,
        options: [String],
        @PromptBuilder prompt: () throws -> Prompt
    ) async throws -> Choice<String> {
        let builtPrompt = try prompt()
        return try await choice(instructions, options: options, prompt: builtPrompt)
    }

    /// Evaluates an ordinal rubric score across ordered levels.
    func score(
        _ instructions: String,
        levels: [String],
        state: String
    ) async throws -> ScoreResult {
        let schema = try DynamicDecisionSchema.makeScoreSchema(instructions: instructions, levels: levels)
        let response = try await self.respond(to: state, schema: schema)
        return Self.decodeScoreResponse(response, levels: levels)
    }

    /// Evaluates an ordinal rubric score across ordered levels given a multimodal `Prompt`.
    func score(
        _ instructions: String,
        levels: [String],
        prompt: Prompt
    ) async throws -> ScoreResult {
        let schema = try DynamicDecisionSchema.makeScoreSchema(instructions: instructions, levels: levels)
        let response = try await self.respond(to: prompt, schema: schema)
        return Self.decodeScoreResponse(response, levels: levels)
    }

    /// Evaluates an ordinal rubric score across ordered levels using a `@PromptBuilder` closure.
    func score(
        _ instructions: String,
        levels: [String],
        @PromptBuilder prompt: () throws -> Prompt
    ) async throws -> ScoreResult {
        let builtPrompt = try prompt()
        return try await score(instructions, levels: levels, prompt: builtPrompt)
    }

    // MARK: - InternalShortcut Decoding Helpers

    private static func decodeProbabilityResponse(
        _ response: LanguageModelSession.Response<GeneratedContent>
    ) -> Double {
        if let prob = response.probability(for: "decision") {
            return prob
        }
        if let prob = response.probability(for: "root") {
            return prob
        }
        if let firstEntry = response.probabilities.first, let trueProb = firstEntry.value["true"] {
            return trueProb
        }
        if let boolVal = try? response.content.value(Bool.self, forProperty: "decision") {
            return boolVal ? 1.0 : 0.0
        }
        if let boolVal = try? response.content.value(Bool.self, forProperty: "root") {
            return boolVal ? 1.0 : 0.0
        }
        if let boolVal = try? response.content.value(Bool.self) {
            return boolVal ? 1.0 : 0.0
        }
        return 0.5
    }

    private static func buildChoosableSchema<Option: Choosable>(
        instructions: String,
        type: Option.Type
    ) throws -> GenerationSchema {
        guard !Option.allCases.isEmpty else {
            throw SystemOneError.invalidSchema("Choosable enum '\(String(describing: type))' has no cases.")
        }
        var seen: Set<String> = []
        var options: [(name: String, description: String?)] = []
        for opt in Option.allCases {
            let trimmed = opt.optionIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                throw SystemOneError.invalidSchema("Choosable enum '\(String(describing: type))' contains an empty option identifier.")
            }
            guard seen.insert(opt.optionIdentifier).inserted else {
                throw SystemOneError.invalidSchema("Choosable enum '\(String(describing: type))' contains duplicate option identifier '\(opt.optionIdentifier)'.")
            }
            options.append((name: opt.optionIdentifier, description: opt.optionDescription))
        }
        return try DynamicDecisionSchema.makeChoiceSchema(instructions: instructions, options: options)
    }

    private static func decodeChoosableResponse<Option: Choosable>(
        _ response: LanguageModelSession.Response<GeneratedContent>,
        type: Option.Type
    ) -> Choice<Option> {
        let rawString: String
        if let str = try? response.content.value(String.self) {
            rawString = str
        } else if let str = try? response.content.value(String.self, forProperty: "choice") {
            rawString = str
        } else {
            rawString = response.content.jsonString.trimmingCharacters(in: CharacterSet(charactersIn: "\" \t\n\r"))
        }

        let selectedOption = Option.allCases.first(where: { $0.optionIdentifier == rawString })
            ?? Option.allCases.first(where: { "\($0)" == rawString })
            ?? Option.allCases.first!

        let rawDist = response.probabilities["choice"]
            ?? response.probabilities["root"]
            ?? response.probabilities.first?.value
            ?? [:]

        var distribution: [Option: Double] = [:]
        for opt in Option.allCases {
            if let p = rawDist[opt.optionIdentifier] ?? rawDist["\(opt)"] {
                distribution[opt] = p
            }
        }

        let conf = response.confidence(for: "choice")
            ?? response.confidence(for: "root")
            ?? response.confidenceScores.first?.value
            ?? distribution.values.max()
            ?? 0.0

        return Choice(
            value: selectedOption,
            confidence: conf,
            distribution: distribution,
            rawContent: response.content
        )
    }

    private static func buildStringChoiceSchema(
        instructions: String,
        options: [String]
    ) throws -> GenerationSchema {
        guard !options.isEmpty else {
            throw SystemOneError.invalidSchema("Choice requires at least one candidate option.")
        }
        var seen: Set<String> = []
        for opt in options {
            let trimmed = opt.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                throw SystemOneError.invalidSchema("Choice options must not be empty or whitespace-only.")
            }
            guard seen.insert(opt).inserted else {
                throw SystemOneError.invalidSchema("Choice options must be unique; duplicate option '\(opt)'.")
            }
        }
        let schemaOptions = options.map { (name: $0, description: nil as String?) }
        return try DynamicDecisionSchema.makeChoiceSchema(instructions: instructions, options: schemaOptions)
    }

    private static func decodeStringChoiceResponse(
        _ response: LanguageModelSession.Response<GeneratedContent>,
        options: [String]
    ) -> Choice<String> {
        let rawString: String
        if let str = try? response.content.value(String.self) {
            rawString = str
        } else if let str = try? response.content.value(String.self, forProperty: "choice") {
            rawString = str
        } else {
            rawString = response.content.jsonString.trimmingCharacters(in: CharacterSet(charactersIn: "\" \t\n\r"))
        }

        let selectedOption = options.first(where: { $0 == rawString }) ?? options.first ?? rawString

        let rawDist = response.probabilities["choice"]
            ?? response.probabilities["root"]
            ?? response.probabilities.first?.value
            ?? [:]

        let conf = response.confidence(for: "choice")
            ?? response.confidence(for: "root")
            ?? response.confidenceScores.first?.value
            ?? rawDist.values.max()
            ?? 0.0

        return Choice(
            value: selectedOption,
            confidence: conf,
            distribution: rawDist,
            rawContent: response.content
        )
    }

    private static func decodeScoreResponse(
        _ response: LanguageModelSession.Response<GeneratedContent>,
        levels: [String]
    ) -> ScoreResult {
        let scoreVal = response.scoreValue(for: "score")
            ?? response.scoreValue(for: "root")
            ?? response.scoreValues.first?.value

        let value: Double
        let conf: Double
        var probs: [Double]

        if let scoreVal {
            value = scoreVal.value
            conf = scoreVal.confidence
            probs = (0..<levels.count).map { scoreVal.probabilities[$0] ?? 0.0 }
        } else {
            if let num = try? response.content.value(Double.self) {
                value = num
            } else if let num = try? response.content.value(Int.self) {
                value = Double(num)
            } else if let num = try? response.content.value(Double.self, forProperty: "score") {
                value = num
            } else if let num = try? response.content.value(Int.self, forProperty: "score") {
                value = Double(num)
            } else {
                value = 0.0
            }
            conf = response.confidence(for: "score")
                ?? response.confidence(for: "root")
                ?? response.confidenceScores.first?.value
                ?? 0.0
            probs = Array(repeating: 0.0, count: levels.count)
        }

        let mostLikelyIndex: Int
        if let maxProbIndex = probs.indices.max(by: { probs[$0] < probs[$1] }), probs[maxProbIndex] > 0.0 {
            mostLikelyIndex = maxProbIndex
        } else {
            let rounded = ScoreValue.clampedInt(from: value)
            mostLikelyIndex = min(max(rounded, 0), max(0, levels.count - 1))
        }

        if probs.allSatisfy({ $0 == 0.0 }) && probs.indices.contains(mostLikelyIndex) {
            probs[mostLikelyIndex] = 1.0
        }

        let mostLikelyLevel = levels.indices.contains(mostLikelyIndex) ? levels[mostLikelyIndex] : (levels.first ?? "")

        return ScoreResult(
            value: value,
            mostLikelyIndex: mostLikelyIndex,
            mostLikelyLevel: mostLikelyLevel,
            probabilities: probs,
            confidence: conf,
            levels: levels
        )
    }
}
