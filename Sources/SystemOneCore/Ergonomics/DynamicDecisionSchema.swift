import Foundation
import FoundationModels

/// Utility for building runtime `GenerationSchema` instances for System One decision shortcuts.
public enum DynamicDecisionSchema {
    /// Builds a binary decision schema evaluating the probability of truth for a statement.
    ///
    /// - Parameters:
    ///   - instructions: The assertion or instruction to evaluate.
    ///   - whenTrue: An optional qualification defining when the statement evaluates to true.
    ///   - whenFalse: An optional qualification defining when the statement evaluates to false.
    /// - Returns: A strongly-typed `GenerationSchema` ready for `LanguageModelSession.respond`.
    public static func makeBinarySchema(
        instructions: String,
        whenTrue: String? = nil,
        whenFalse: String? = nil
    ) throws -> GenerationSchema {
        var fullInstructions = instructions
        if let whenTrue, let whenFalse {
            fullInstructions += " (True if: \(whenTrue); False if: \(whenFalse))"
        } else if let whenTrue {
            fullInstructions += " (True if: \(whenTrue))"
        } else if let whenFalse {
            fullInstructions += " (False if: \(whenFalse))"
        }

        let booleanProperty = DynamicGenerationSchema.Property(
            name: "decision",
            description: fullInstructions,
            schema: DynamicGenerationSchema(type: Bool.self, guides: []),
            isOptional: false
        )

        let root = DynamicGenerationSchema(
            name: "BinaryDecision",
            description: fullInstructions,
            properties: [booleanProperty]
        )

        return try GenerationSchema(root: root, dependencies: [])
    }

    /// Builds a categorical choice schema selecting among candidate discrete options.
    ///
    /// - Parameters:
    ///   - instructions: The instruction defining how to select among options.
    ///   - options: Tuples containing the candidate option names and optional descriptions.
    /// - Returns: A strongly-typed `GenerationSchema` ready for `LanguageModelSession.respond`.
    public static func makeChoiceSchema(
        instructions: String,
        options: [(name: String, description: String?)]
    ) throws -> GenerationSchema {
        guard !options.isEmpty else {
            throw SystemOneError.invalidSchema("Choice schema requires at least one candidate option.")
        }

        var fullInstructions = instructions
        let hasDescriptions = options.contains { $0.description != nil }
        if hasDescriptions {
            let descSummary = options.map { opt in
                if let desc = opt.description, !desc.isEmpty {
                    return "\(opt.name): \(desc)"
                } else {
                    return opt.name
                }
            }.joined(separator: "; ")
            fullInstructions += " (Options: \(descSummary))"
        }

        let root = DynamicGenerationSchema(
            name: "Choice",
            description: fullInstructions,
            anyOf: options.map(\.name)
        )

        return try GenerationSchema(root: root, dependencies: [])
    }

    /// Builds an ordinal rubric score schema evaluating numeric/integer levels.
    ///
    /// - Parameters:
    ///   - instructions: The scoring rubric instructions.
    ///   - levels: An array of descriptive level labels (e.g. `["Low", "Medium", "High"]`).
    /// - Returns: A strongly-typed `GenerationSchema` ready for `LanguageModelSession.respond`.
    public static func makeScoreSchema(
        instructions: String,
        levels: [String]
    ) throws -> GenerationSchema {
        guard !levels.isEmpty else {
            throw SystemOneError.invalidSchema("Score schema requires at least one rubric level.")
        }
        guard levels.count <= 32 else {
            throw SystemOneError.invalidSchema("Score schema supports at most 32 discrete rubric levels (got \(levels.count)).")
        }

        var fullInstructions = instructions
        let rubricSummary = levels.enumerated().map { "\($0): \($1)" }.joined(separator: ", ")
        fullInstructions += " (Rubric: \(rubricSummary))"

        let maxLevel = Swift.max(0, levels.count - 1)
        let scoreType = DynamicGenerationSchema(type: Int.self, guides: [.range(0...maxLevel)])

        let scoreProperty = DynamicGenerationSchema.Property(
            name: "score",
            description: fullInstructions,
            schema: scoreType,
            isOptional: false
        )

        let root = DynamicGenerationSchema(
            name: "ScoreDecision",
            description: fullInstructions,
            properties: [scoreProperty]
        )

        return try GenerationSchema(root: root, dependencies: [])
    }
}
