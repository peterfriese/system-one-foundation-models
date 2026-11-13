import Foundation
import SystemOneCore

/// A native Swift tokenizer for mmBERT multilingual backbones (`laya-multilingual` 322M).
///
/// Supports 100+ languages using a 256k token vocabulary based on SentencePiece unigram/BPE.
/// See `tech-notes/0008-on-device-coreml-decision-engine.md`.
public struct MMBERTTokenizer: LayaTokenizer, Sendable {
    public let clsTokenId: Int
    public let sepTokenId: Int
    public let padTokenId: Int
    public let maskTokenId: Int
    public let maskToken: String

    private let vocab: [String: Int]
    private let invVocab: [Int: String]
    private let unkTokenId: Int
    private let usesMetaspace: Bool

    public init(
        vocab: [String: Int],
        clsTokenId: Int = 2,
        sepTokenId: Int = 1,
        padTokenId: Int = 0,
        maskTokenId: Int = 4,
        maskToken: String = "<mask_1>",
        unkTokenId: Int = 3
    ) {
        self.vocab = vocab
        var inverse: [Int: String] = [:]
        var foundMetaspace = false
        for (k, v) in vocab {
            inverse[v] = k
            if !foundMetaspace && k.hasPrefix("\u{2581}") {
                foundMetaspace = true
            }
        }
        self.invVocab = inverse
        self.usesMetaspace = foundMetaspace
        self.clsTokenId = clsTokenId
        self.sepTokenId = sepTokenId
        self.padTokenId = padTokenId
        self.maskTokenId = maskTokenId
        self.maskToken = maskToken
        self.unkTokenId = unkTokenId
    }

    /// Initializes a tokenizer by loading a Hugging Face `tokenizer.json` file (supporting both BPE dictionary
    /// `vocab: {token: id}` and SentencePiece Unigram `vocab: [[piece, score], ...]`, plus `added_tokens`).
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
              let rawVocab = model["vocab"] else {
            throw SystemOneError.modelExecutionError(
                "Invalid MMBERT tokenizer.json at '\(jsonURL.path)': missing model.vocab."
            )
        }

        var vocabDict: [String: Int] = [:]
        if let dictVocab = rawVocab as? [String: Any] {
            vocabDict.reserveCapacity(dictVocab.count)
            for (token, rawId) in dictVocab {
                if let intId = rawId as? Int {
                    vocabDict[token] = intId
                } else if let numId = rawId as? NSNumber {
                    vocabDict[token] = numId.intValue
                }
            }
        } else if let unigramList = rawVocab as? [[Any]] {
            vocabDict.reserveCapacity(unigramList.count)
            for (index, entry) in unigramList.enumerated() {
                if let piece = entry.first as? String, vocabDict[piece] == nil {
                    vocabDict[piece] = index
                }
            }
        } else {
            throw SystemOneError.modelExecutionError(
                "Invalid MMBERT tokenizer.json at '\(jsonURL.path)': unsupported model.vocab format."
            )
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
                "Invalid MMBERT tokenizer.json at '\(jsonURL.path)': vocabulary is empty."
            )
        }

        let resolvedMaskToken = vocabDict["<mask_1>"] != nil ? "<mask_1>" : (vocabDict["<mask>"] != nil ? "<mask>" : "<mask_1>")
        self.init(
            vocab: vocabDict,
            clsTokenId: vocabDict["<bos>"] ?? vocabDict["<s>"] ?? vocabDict["[CLS]"] ?? 2,
            sepTokenId: vocabDict["<eos>"] ?? vocabDict["</s>"] ?? vocabDict["[SEP]"] ?? 1,
            padTokenId: vocabDict["<pad>"] ?? vocabDict["[PAD]"] ?? 0,
            maskTokenId: vocabDict[resolvedMaskToken] ?? 4,
            maskToken: resolvedMaskToken,
            unkTokenId: vocabDict["<unk>"] ?? vocabDict["[UNK]"] ?? 3
        )
    }

    /// Creates a default tokenizer with fallback multilingual tokens for testing.
    public static func defaultTokenizer() -> MMBERTTokenizer {
        var sampleVocab: [String: Int] = [
            "<pad>": 0,
            "<eos>": 1,
            "<bos>": 2,
            "<unk>": 3,
            "<mask_1>": 4,
            "choice": 10,
            "score": 11,
            "noul": 12,
            "question:": 13,
            "true": 14,
            "false": 15,
            "level": 16
        ]
        for code in 32...126 {
            let charStr = String(UnicodeScalar(code)!)
            if sampleVocab[charStr] == nil {
                sampleVocab[charStr] = code + 1000
            }
        }
        return MMBERTTokenizer(vocab: sampleVocab)
    }

    public func encode(_ text: String, addSpecialTokens: Bool = false) -> [Int] {
        var tokenIds: [Int] = []
        if addSpecialTokens {
            tokenIds.append(clsTokenId)
        }

        let words = text.split(whereSeparator: \.isWhitespace).map(String.init)
        for word in words {
            tokenIds.append(contentsOf: tokenizeWord(word))
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
        let metaspaceWord = "\u{2581}" + word
        if usesMetaspace, let directMeta = vocab[metaspaceWord] {
            return [directMeta]
        }
        if let direct = vocab[word] {
            return [direct]
        }

        let target = usesMetaspace ? metaspaceWord : word
        var result: [Int] = []
        var remaining = target[...]
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
                if firstChar != "\u{2581}" {
                    result.append(vocab[firstChar] ?? unkTokenId)
                }
                remaining = remaining.dropFirst(1)
            }
        }
        return result
    }
}
