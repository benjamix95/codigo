import Foundation

// MARK: - WordPieceTokenizer

/// Minimal WordPiece tokenizer compatible with BERT / all-MiniLM-L6-v2.
/// Loads `vocab.txt` from the app bundle and produces `input_ids` +
/// `attention_mask` arrays suitable for CoreML inference.
public final class WordPieceTokenizer: Sendable {

    /// Special token IDs (standard BERT uncased).
    public static let clsTokenId: Int32 = 101
    public static let sepTokenId: Int32 = 102
    public static let padTokenId: Int32 = 0
    public static let unkTokenId: Int32 = 100

    /// Maximum sequence length (model limit).
    public let maxLength: Int

    /// Vocabulary: token string → id.
    private let vocab: [String: Int32]

    // MARK: - Init

    public init(vocabURL: URL, maxLength: Int = 512) throws {
        let text = try String(contentsOf: vocabURL, encoding: .utf8)
        var map = [String: Int32]()
        for (index, line) in text.components(separatedBy: "\n").enumerated() {
            let token = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !token.isEmpty else { continue }
            map[token] = Int32(index)
        }
        self.vocab = map
        self.maxLength = maxLength
    }

    // MARK: - Tokenize

    /// Tokenize a single text string into `input_ids` and `attention_mask`.
    /// Both arrays are padded / truncated to `maxLength`.
    public func encode(_ text: String) -> TokenizedInput {
        let tokens = tokenize(text)
        return buildInput(tokens)
    }

    /// Tokenize a batch of texts.
    public func encodeBatch(_ texts: [String]) -> [TokenizedInput] {
        texts.map { encode($0) }
    }

    // MARK: - Internal

    /// Split text into WordPiece token IDs (without [CLS]/[SEP]).
    func tokenize(_ text: String) -> [Int32] {
        let words = basicTokenize(text)
        var ids = [Int32]()

        for word in words {
            let subTokens = wordPieceSplit(word)
            ids.append(contentsOf: subTokens)
        }
        return ids
    }

    /// Basic pre-tokenization: lowercase, strip accents, split on whitespace
    /// and punctuation (BERT-style).
    private func basicTokenize(_ text: String) -> [String] {
        let lowered = text.lowercased()
        var result = [String]()
        var current = ""

        for char in lowered {
            if char.isWhitespace {
                if !current.isEmpty { result.append(current); current = "" }
            } else if char.isPunctuation || char.isSymbol {
                if !current.isEmpty { result.append(current); current = "" }
                result.append(String(char))
            } else {
                current.append(char)
            }
        }
        if !current.isEmpty { result.append(current) }
        return result
    }

    /// Greedy longest-match WordPiece splitting.
    private func wordPieceSplit(_ word: String) -> [Int32] {
        if let directId = vocab[word] { return [directId] }

        var ids = [Int32]()
        var start = word.startIndex
        var isFirst = true

        while start < word.endIndex {
            var end = word.endIndex
            var found = false

            while start < end {
                let substr = String(word[start..<end])
                let candidate = isFirst ? substr : "##" + substr

                if let tokenId = vocab[candidate] {
                    ids.append(tokenId)
                    start = end
                    found = true
                    isFirst = false
                    break
                }
                end = word.index(before: end)
            }

            if !found {
                ids.append(Self.unkTokenId)
                start = word.index(after: start)
                isFirst = false
            }
        }
        return ids
    }

    /// Wrap token IDs with [CLS] … [SEP], pad/truncate to maxLength.
    private func buildInput(_ tokenIds: [Int32]) -> TokenizedInput {
        // Reserve 2 slots for [CLS] and [SEP].
        let maxContent = maxLength - 2
        let truncated = Array(tokenIds.prefix(maxContent))

        var inputIds = [Int32]()
        inputIds.reserveCapacity(maxLength)
        inputIds.append(Self.clsTokenId)
        inputIds.append(contentsOf: truncated)
        inputIds.append(Self.sepTokenId)

        let attentionLength = inputIds.count
        let padCount = maxLength - attentionLength

        inputIds.append(contentsOf: [Int32](repeating: Self.padTokenId, count: padCount))
        var attentionMask = [Int32](repeating: 1, count: attentionLength)
        attentionMask.append(contentsOf: [Int32](repeating: 0, count: padCount))

        return TokenizedInput(
            inputIds: inputIds,
            attentionMask: attentionMask,
            tokenCount: attentionLength
        )
    }
}

// MARK: - TokenizedInput

/// Output of the WordPiece tokenizer, ready for CoreML.
public struct TokenizedInput: Sendable {
    public let inputIds: [Int32]
    public let attentionMask: [Int32]
    /// Number of real (non-pad) tokens, including [CLS] and [SEP].
    public let tokenCount: Int
}
