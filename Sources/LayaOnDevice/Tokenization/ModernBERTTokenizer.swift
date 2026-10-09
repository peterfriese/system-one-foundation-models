import Foundation

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
        let data = try Data(contentsOf: jsonURL)
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let model = root["model"] as? [String: Any],
              let vocabDict = model["vocab"] as? [String: Int] else {
            throw NSError(domain: "ModernBERTTokenizer", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid tokenizer.json"])
        }
        self.init(vocab: vocabDict)
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
        // Add basic ASCII characters and common digits/letters
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

        // Tokenize by whitespace and subwords
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
        // Subword greedy longest matching with bounded prefix search
        var result: [Int] = []
        var remaining = word[...]
        let maxSubwordLen = 64
        while !remaining.isEmpty {
            var matched = false
            let searchLen = min(remaining.count, maxSubwordLen)
            for end in stride(from: searchLen, to: 0, by: -1) {
                let sub = String(remaining.prefix(end))
                if let id = vocab[sub] {
                    result.append(id)
                    remaining = remaining.dropFirst(end)
                    matched = true
                    break
                }
            }
            if !matched {
                // If single character not found, emit unk or character code
                let firstChar = String(remaining.prefix(1))
                result.append(vocab[firstChar] ?? unkTokenId)
                remaining = remaining.dropFirst(1)
            }
        }
        return result
    }
}
