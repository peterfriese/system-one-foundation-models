import Foundation
import SystemOneCore

/// A native Swift Byte-level BPE / WordPiece tokenizer for ModernBERT backbones (`laya` 421M and `laya-typed-decisions`).
///
/// See `tech-notes/0008-on-device-coreml-decision-engine.md`.
public struct ModernBERTTokenizer: LayaTokenizer, Sendable {
    public let clsTokenId: Int
    public let sepTokenId: Int
    public let padTokenId: Int
    public let maskTokenId: Int
    public let maskToken: String

    private let vocab: [String: Int]
    private let invVocab: [Int: String]
    private let unkTokenId: Int

    public init(
        vocab: [String: Int],
        clsTokenId: Int = 50281,
        sepTokenId: Int = 50282,
        padTokenId: Int = 50283,
        maskTokenId: Int = 50284,
        maskToken: String = "[MASK]",
        unkTokenId: Int = 50280
    ) {
        self.vocab = vocab
        var inverse: [Int: String] = [:]
        for (k, v) in vocab {
            inverse[v] = k
        }
        self.invVocab = inverse
        self.clsTokenId = clsTokenId
        self.sepTokenId = sepTokenId
        self.padTokenId = padTokenId
        self.maskTokenId = maskTokenId
        self.maskToken = maskToken
        self.unkTokenId = unkTokenId
    }

    /// Initializes a tokenizer by loading a Hugging Face `tokenizer.json` file.
    public init(jsonURL: URL) throws {
        guard jsonURL.isFileURL else {
            throw SystemOneError.modelExecutionError(
                "Tokenizer URL must be a local file:// URL, got '\(jsonURL.scheme ?? "unknown")'."
            )
        }
        let data: Data
        do {
            data = try Data(contentsOf: jsonURL)
        } catch {
            throw SystemOneError.modelExecutionError(
                "Failed to read tokenizer file at '\(jsonURL.path)': \(error.localizedDescription)"
            )
        }

        let jsonObject: Any
        do {
            jsonObject = try JSONSerialization.jsonObject(with: data)
        } catch {
            throw SystemOneError.modelExecutionError(
                "Failed to parse tokenizer JSON at '\(jsonURL.path)': \(error.localizedDescription)"
            )
        }

        guard let root = jsonObject as? [String: Any],
              let model = root["model"] as? [String: Any],
              let rawVocab = model["vocab"] as? [String: Any] else {
            throw SystemOneError.modelExecutionError(
                "Invalid ModernBERT tokenizer.json at '\(jsonURL.path)': missing model.vocab dictionary."
            )
        }

        var vocabDict: [String: Int] = [:]
        vocabDict.reserveCapacity(rawVocab.count)
        for (token, rawId) in rawVocab {
            if let intId = rawId as? Int {
                vocabDict[token] = intId
            } else if let numId = rawId as? NSNumber {
                vocabDict[token] = numId.intValue
            }
        }

        if let addedTokens = root["added_tokens"] as? [[String: Any]] {
            for entry in addedTokens {
                guard let content = entry["content"] as? String else { continue }
                if let intId = entry["id"] as? Int {
                    vocabDict[content] = intId
                } else if let numId = entry["id"] as? NSNumber {
                    vocabDict[content] = numId.intValue
                }
            }
        }

        guard !vocabDict.isEmpty else {
            throw SystemOneError.modelExecutionError(
                "Invalid ModernBERT tokenizer.json at '\(jsonURL.path)': vocabulary is empty."
            )
        }

        self.init(
            vocab: vocabDict,
            clsTokenId: vocabDict["[CLS]"] ?? 50281,
            sepTokenId: vocabDict["[SEP]"] ?? 50282,
            padTokenId: vocabDict["[PAD]"] ?? 50283,
            maskTokenId: vocabDict["[MASK]"] ?? 50284,
            maskToken: "[MASK]",
            unkTokenId: vocabDict["[UNK]"] ?? 50280
        )
    }

    /// Creates a default tokenizer with common English vocabulary and special tokens for testing or fallback.
    public static func defaultTokenizer() -> ModernBERTTokenizer {
        var sampleVocab: [String: Int] = [
            "[PAD]": 50283,
            "[CLS]": 50281,
            "[SEP]": 50282,
            "[MASK]": 50284,
            "[UNK]": 50280,
            "choice": 1,
            "score": 2,
            "noul": 3,
            "question:": 4,
            "true": 5,
            "false": 6,
            "level": 7,
            "yes": 8,
            "no": 9,
            "is": 10,
            "the": 11,
            "statement": 12,
            "holds": 13,
            "does": 14,
            "not": 15
        ]
        for code in 32...126 {
            let charStr = String(UnicodeScalar(code)!)
            if sampleVocab[charStr] == nil {
                sampleVocab[charStr] = code + 100
            }
        }
        return ModernBERTTokenizer(vocab: sampleVocab)
    }

    public func encode(_ text: String, addSpecialTokens: Bool = false) -> [Int] {
        var tokenIds: [Int] = []
        if addSpecialTokens {
            tokenIds.append(clsTokenId)
        }

        let words = text.split(whereSeparator: \.isWhitespace).map(String.init)
        for word in words {
            let subwords = tokenizeWord(word)
            tokenIds.append(contentsOf: subwords)
        }

        if addSpecialTokens {
            tokenIds.append(sepTokenId)
        }
        return tokenIds
    }

    public func decode(_ tokens: [Int]) -> String {
        let pieces = tokens.compactMap { invVocab[$0] }
        return pieces.joined(separator: " ")
    }

    private func tokenizeWord(_ word: String) -> [Int] {
        if let direct = vocab[word] {
            return [direct]
        }
        var result: [Int] = []
        var remaining = word[...]
        let maxSubwordLen = 64
        while !remaining.isEmpty {
            var matched = false
            let window = remaining.prefix(maxSubwordLen)
            let searchLen = window.count
            for end in stride(from: searchLen, to: 0, by: -1) {
                let sub = String(window.prefix(end))
                if let id = vocab[sub] {
                    result.append(id)
                    remaining = remaining.dropFirst(end)
                    matched = true
                    break
                }
            }
            if !matched {
                let firstChar = String(remaining.prefix(1))
                result.append(vocab[firstChar] ?? unkTokenId)
                remaining = remaining.dropFirst(1)
            }
        }
        return result
    }
}
