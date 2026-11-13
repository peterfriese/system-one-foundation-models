import Foundation

/// Synthesizes System One answers into valid JSON payloads matching `@Generable` shapes.
public struct ResponseSynthesizer: Sendable {
    public init() {}

    /// Synthesizes the text payload to be delivered through `LanguageModelExecutorGenerationChannel`.
    public func synthesize(
        answers: [String: SystemOneAnswer],
        layout: SchemaRootLayout
    ) throws -> String {
        switch layout {
        case .object(let properties, _):
            let dictionary = try buildObjectDictionary(properties: properties, answers: answers)
            let data = try JSONSerialization.data(
                withJSONObject: dictionary,
                options: [.sortedKeys, .fragmentsAllowed]
            )
            guard let jsonString = String(data: data, encoding: .utf8) else {
                throw SystemOneError.decodingError("Failed to convert synthesized dictionary to UTF-8 JSON string.")
            }
            return jsonString

        case .choice(let options, let questionKey):
            let answer = answers[questionKey]
            guard let choice = answer?.choice ?? options.first else {
                throw SystemOneError.decodingError("No choice answer returned for root enum question '\(questionKey)'.")
            }
            return choice

        case .boolean(let questionKey):
            let answer = answers[questionKey]
            let boolValue: Bool
            if let noul = answer?.noul {
                boolValue = (noul >= 0.5)
            } else if let choice = answer?.choice {
                boolValue = (choice.lowercased() == "true")
            } else {
                boolValue = false
            }
            return boolValue ? "true" : "false"

        case .score(let min, let max, let isInteger, let questionKey):
            let answer = answers[questionKey]
            let value = computeScoreValue(answer: answer, min: min, max: max, isInteger: isInteger)
            if isInteger {
                return "\(ScoreValue.clampedInt(from: value))"
            } else {
                return "\(value)"
            }
        }
    }

    /// Extracts calibrated probability distributions from System One answers into a JSON string.
    public func extractProbabilitiesJSON(from answers: [String: SystemOneAnswer]) -> String? {
        var probs: [String: Any] = [:]
        for (key, answer) in answers {
            if let distribution = answer.probabilities {
                probs[key] = distribution
            } else if let noul = answer.noul {
                probs[key] = [
                    "true": noul,
                    "false": max(0.0, 1.0 - noul)
                ]
            }
        }
        guard !probs.isEmpty,
              let data = try? JSONSerialization.data(withJSONObject: probs, options: [.sortedKeys]),
              let json = String(data: data, encoding: .utf8) else {
            return nil
        }
        return json
    }

    /// Extracts confidence scores from System One answers into a JSON string.
    public func extractConfidenceJSON(from answers: [String: SystemOneAnswer]) -> String? {
        var confs: [String: Double] = [:]
        for (key, answer) in answers {
            if let confidence = answer.confidence {
                confs[key] = confidence
            } else if let noul = answer.noul {
                confs[key] = abs(noul - 0.5) * 2.0
            }
        }
        guard !confs.isEmpty,
              let data = try? JSONSerialization.data(withJSONObject: confs, options: [.sortedKeys]),
              let json = String(data: data, encoding: .utf8) else {
            return nil
        }
        return json
    }

    /// Extracts typed ScoreValue models from System One answers into a JSON string.
    public func extractScoresJSON(from answers: [String: SystemOneAnswer], layout: SchemaRootLayout? = nil) -> String? {
        var scores: [String: ScoreValue] = [:]
        let scoreMetadata = layout.map(scoreQuestionMetadata) ?? [:]
        for (key, answer) in answers {
            if let metadata = scoreMetadata[key] {
                if let scoreVal = answer.scoreValue(
                    minimum: metadata.minimum,
                    maximum: metadata.maximum,
                    isInteger: metadata.isInteger
                ) {
                    scores[key] = scoreVal
                }
            } else if let scoreVal = answer.scoreValue {
                scores[key] = scoreVal
            }
        }
        guard !scores.isEmpty,
              let data = try? JSONEncoder().encode(scores),
              let json = String(data: data, encoding: .utf8) else {
            return nil
        }
        return json
    }

    // MARK: - Internal Helpers

    private func buildObjectDictionary(
        properties: [String: SchemaPropertyDescriptor],
        answers: [String: SystemOneAnswer]
    ) throws -> [String: Any] {
        var dictionary: [String: Any] = [:]

        for (name, descriptor) in properties {
            if let value = extractPropertyValue(descriptor: descriptor, answers: answers) {
                dictionary[name] = value
            } else if descriptor.isRequired {
                dictionary[name] = defaultFallbackValue(for: descriptor)
            }
        }

        return dictionary
    }

    private func extractPropertyValue(
        descriptor: SchemaPropertyDescriptor,
        answers: [String: SystemOneAnswer]
    ) -> Any? {
        let answer = answers[descriptor.questionKey]

        switch descriptor.kind {
        case .boolean:
            if let noul = answer?.noul {
                return (noul >= 0.5)
            } else if let choice = answer?.choice {
                return (choice.lowercased() == "true")
            }
            return nil

        case .choice:
            if let choice = answer?.choice {
                return choice
            }
            return nil

        case .score(let min, let max, let isInteger):
            guard answer != nil else { return nil }
            let val = computeScoreValue(answer: answer, min: min, max: max, isInteger: isInteger)
            return isInteger ? ScoreValue.clampedInt(from: val) : val

        case .nested(let childDescriptors):
            if !descriptor.isRequired && !hasAnyAnswer(in: descriptor, answers: answers) {
                return nil
            }
            var childDict: [String: Any] = [:]
            for (childName, childDesc) in childDescriptors {
                if let childVal = extractPropertyValue(descriptor: childDesc, answers: answers) {
                    childDict[childName] = childVal
                } else if childDesc.isRequired {
                    childDict[childName] = defaultFallbackValue(for: childDesc)
                }
            }
            return childDict
        }
    }

    private func hasAnyAnswer(
        in descriptor: SchemaPropertyDescriptor,
        answers: [String: SystemOneAnswer]
    ) -> Bool {
        switch descriptor.kind {
        case .boolean:
            let answer = answers[descriptor.questionKey]
            return answer?.noul != nil || answer?.choice != nil
        case .choice:
            return answers[descriptor.questionKey]?.choice != nil
        case .score:
            return answers[descriptor.questionKey]?.score != nil
        case .nested(let children):
            return children.values.contains { hasAnyAnswer(in: $0, answers: answers) }
        }
    }

    private func computeScoreValue(
        answer: SystemOneAnswer?,
        min: Double,
        max: Double,
        isInteger: Bool
    ) -> Double {
        guard let scoreValue = answer?.scoreValue(minimum: min, maximum: max, isInteger: isInteger) else {
            return min
        }
        return isInteger ? round(scoreValue.value) : scoreValue.value
    }

    private func defaultFallbackValue(for descriptor: SchemaPropertyDescriptor) -> Any {
        switch descriptor.kind {
        case .boolean:
            return false
        case .choice(let options):
            return options.first ?? ""
        case .score(let min, _, let isInteger):
            return isInteger ? ScoreValue.clampedInt(from: min) : min
        case .nested(let children):
            var dict: [String: Any] = [:]
            for (k, v) in children where v.isRequired {
                dict[k] = defaultFallbackValue(for: v)
            }
            return dict
        }
    }

    private func scoreQuestionMetadata(for layout: SchemaRootLayout) -> [String: (minimum: Double, maximum: Double, isInteger: Bool)] {
        switch layout {
        case .object(let properties, _):
            var metadata: [String: (minimum: Double, maximum: Double, isInteger: Bool)] = [:]
            for descriptor in properties.values {
                metadata.merge(scoreQuestionMetadata(for: descriptor), uniquingKeysWith: { current, _ in current })
            }
            return metadata
        case .score(let minimum, let maximum, let isInteger, let questionKey):
            return [questionKey: (minimum, maximum, isInteger)]
        case .choice, .boolean:
            return [:]
        }
    }

    private func scoreQuestionMetadata(
        for descriptor: SchemaPropertyDescriptor
    ) -> [String: (minimum: Double, maximum: Double, isInteger: Bool)] {
        switch descriptor.kind {
        case .score(let minimum, let maximum, let isInteger):
            return [descriptor.questionKey: (minimum, maximum, isInteger)]
        case .nested(let children):
            var metadata: [String: (minimum: Double, maximum: Double, isInteger: Bool)] = [:]
            for child in children.values {
                metadata.merge(scoreQuestionMetadata(for: child), uniquingKeysWith: { current, _ in current })
            }
            return metadata
        case .boolean, .choice:
            return [:]
        }
    }
}
