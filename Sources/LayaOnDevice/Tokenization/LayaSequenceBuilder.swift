import Foundation
import SystemOneCore

/// The result of tokenizing and formatting a System One question and state into a model input sequence.
public struct FormattedQuestionSequence: Sendable, Equatable {
    /// Token IDs representing `[CLS] <type> question: <instructions> [SEP] [MASK] opt0 ... [SEP] state [SEP]`.
    public let inputIds: [Int]
    /// Indices of each `[MASK]` token within `inputIds` corresponding to each option.
    public let markerPositions: [Int]
    /// Option keys/labels matching the marker positions in order.
    public let optionKeys: [String]
    /// The numeric question type (0 = choice, 1 = score, 2 = noul).
    public let qtype: Int
}

/// Builds sequence tokens and marker positions matching Laya's non-autoregressive decision model format.
///
/// See `tech-notes/0008-on-device-coreml-decision-engine.md`.
public struct LayaSequenceBuilder: Sendable {
    public let tokenizer: any LayaTokenizer
    public let maxLen: Int
    public let headMaxLen: Int

    public init(
        tokenizer: any LayaTokenizer,
        maxLen: Int = 512,
        headMaxLen: Int = 192
    ) {
        self.tokenizer = tokenizer
        self.maxLen = maxLen
        self.headMaxLen = headMaxLen
    }

    private static let reservedDelimiters = [
        "[CLS]", "[SEP]", "[MASK]", "[PAD]", "[UNK]",
        "<s>", "</s>", "<bos>", "<eos>", "<cls>", "<sep>",
        "<mask>", "<pad>", "<unk>", "<mask_1>"
    ]

    private func sanitize(_ text: String) -> String {
        var clean = text.replacingOccurrences(of: tokenizer.maskToken, with: " ")
        for delimiter in Self.reservedDelimiters {
            if clean.contains(delimiter) {
                clean = clean.replacingOccurrences(of: delimiter, with: " ")
            }
        }
        return clean
    }

    /// Pre-tokenizes and sanitizes application state text once for batch question evaluation.
    public func pretokenizeState(_ state: String) -> [Int] {
        tokenizer.encode(sanitize(state), addSpecialTokens: false)
    }

    /// Formats a question and application state into an input sequence with gathered marker positions.
    public func buildSequence(
        state: String,
        question: SystemOneQuestion
    ) throws -> FormattedQuestionSequence {
        let stateIds = pretokenizeState(state)
        return try buildSequence(pretokenizedStateIds: stateIds, question: question)
    }

    /// Formats a question and pre-tokenized application state into an input sequence with gathered marker positions.
    public func buildSequence(
        pretokenizedStateIds: [Int],
        question: SystemOneQuestion
    ) throws -> FormattedQuestionSequence {
        let (qtype, typeName, instructions, options, keys) = unpackQuestion(question)

        let cleanInstructions = sanitize(instructions)
        var headIds = tokenizer.encode("\(typeName) question: \(cleanInstructions)", addSpecialTokens: false)

        var optIds: [[Int]] = []
        for opt in options {
            let cleanOpt = sanitize(opt)
            var optTokens = tokenizer.encode(" " + cleanOpt, addSpecialTokens: false)
            if optTokens.count > 48 {
                optTokens = Array(optTokens.prefix(48))
            }
            optIds.append([tokenizer.maskTokenId] + optTokens)
        }

        var totalOptTokens = optIds.reduce(0) { $0 + $1.count }
        var optBudget = headMaxLen - totalOptTokens
        if optBudget < 16 {
            let per = max(4, (headMaxLen - 16) / max(1, optIds.count))
            optIds = optIds.map { Array($0.prefix(per)) }
            totalOptTokens = optIds.reduce(0) { $0 + $1.count }
            optBudget = headMaxLen - totalOptTokens
        }

        let maxHead = max(8, optBudget)
        if headIds.count > maxHead {
            headIds = Array(headIds.prefix(maxHead))
        }

        var ids: [Int] = [tokenizer.clsTokenId] + headIds + [tokenizer.sepTokenId]
        var markers: [Int] = []

        for o in optIds {
            markers.append(ids.count)
            ids.append(contentsOf: o)
        }
        ids.append(tokenizer.sepTokenId)

        let room = max(0, maxLen - ids.count - 1)
        var stateIds = pretokenizedStateIds
        if stateIds.count > room {
            stateIds = Array(stateIds.prefix(room))
        }
        ids.append(contentsOf: stateIds)
        ids.append(tokenizer.sepTokenId)

        let finalIds = Array(ids.prefix(maxLen))
        let validMarkers = markers.filter { $0 < maxLen }

        return FormattedQuestionSequence(
            inputIds: finalIds,
            markerPositions: validMarkers,
            optionKeys: keys,
            qtype: qtype
        )
    }

    private func unpackQuestion(_ question: SystemOneQuestion) -> (
        qtype: Int,
        typeName: String,
        instructions: String,
        options: [String],
        keys: [String]
    ) {
        switch question {
        case .choice(let instructions, let criteria):
            let sortedKeys = criteria.keys.sorted()
            let options = sortedKeys.map { key -> String in
                let desc = criteria[key] ?? ""
                return desc.isEmpty ? key : "\(key): \(desc)"
            }
            return (0, "choice", instructions, options, sortedKeys)

        case .score(let instructions, let criteria):
            let options = criteria.enumerated().map { i, desc in
                "level \(i): \(desc)"
            }
            let keys = criteria.indices.map { String($0) }
            return (1, "score", instructions, options, keys)

        case .noul(let instructions):
            let options = [
                "false: no, the statement does not hold",
                "true: yes, the statement holds"
            ]
            let keys = ["false", "true"]
            return (2, "noul", instructions, options, keys)
        }
    }
}
