import Foundation
import OSLog

private let logger = Logger(subsystem: "com.solocode.CoderEngine", category: "EmbeddingService")

// MARK: - EmbeddingService

/// Unified embedding service that tries CoreML first, then Rust ONNX fallback.
/// Thread-safe actor that batches requests for optimal throughput.
public actor EmbeddingService {

    public static let embeddingDim = 384

    private let coreMLBackend: CoreMLEmbeddingBackend?
    private let rustBackend: RustEmbeddingBackend
    private var activeBackend: EmbeddingBackendKind?

    // MARK: - Init

    public init(vocabURL: URL? = nil) {
        if let vocabURL, let tokenizer = try? WordPieceTokenizer(vocabURL: vocabURL) {
            self.coreMLBackend = CoreMLEmbeddingBackend(tokenizer: tokenizer)
        } else if let bundleVocab = Self.findBundleVocab() {
            self.coreMLBackend = (try? WordPieceTokenizer(vocabURL: bundleVocab))
                .map { CoreMLEmbeddingBackend(tokenizer: $0) }
        } else {
            self.coreMLBackend = nil
        }
        self.rustBackend = RustEmbeddingBackend()
    }

    // MARK: - Public API

    /// Embed a single text → 384-dim vector.
    /// Falls back to deterministic pseudo-hash embeddings if no native backend is available.
    public func embed(_ text: String) async -> [Float]? {
        // Try CoreML.
        if let backend = coreMLBackend {
            if let result = await backend.embed(text) {
                activeBackend = .coreML
                return result
            }
        }
        // Try Rust.
        if let result = await rustBackend.embed(text) {
            activeBackend = .rustONNX
            return result
        }
        activeBackend = .pseudoHash
        logger.warning("No native embedding backend available for text (\(text.prefix(50))...) — using pseudo-hash fallback")
        return PseudoHashEmbeddingBackend.embed(text)
    }

    /// Embed a batch of texts. Returns one vector per input (same order).
    /// Texts whose embedding fails produce nil in the output.
    public func embedBatch(_ texts: [String]) async -> [[Float]?] {
        guard !texts.isEmpty else { return [] }

        let rustFirst = texts.count >= IndexFeatureFlags.embeddingRustPreferredMinBatch

        if rustFirst, await rustBackend.isAvailable {
            if let results = await rustBackend.embedBatch(texts) {
                let hasNonZero = results.contains { v in v.contains { $0 != 0 } }
                if hasNonZero {
                    activeBackend = .rustONNX
                    return results.map { Optional($0) }
                }
            }
        }

        if let backend = coreMLBackend {
            let results = await backend.embedBatch(texts)
            let hasNonZero = results.contains { v in v.contains { $0 != 0 } }
            if hasNonZero {
                activeBackend = .coreML
                return results.map { Optional($0) }
            }
        }

        if !rustFirst, await rustBackend.isAvailable {
            if let results = await rustBackend.embedBatch(texts) {
                let hasNonZero = results.contains { v in v.contains { $0 != 0 } }
                if hasNonZero {
                    activeBackend = .rustONNX
                    return results.map { Optional($0) }
                }
            }
        }

        activeBackend = .pseudoHash
        logger.warning("No native embedding backend available for batch of \(texts.count) texts — using pseudo-hash fallback")
        return PseudoHashEmbeddingBackend.embedBatch(texts).map(Optional.init)
    }

    /// Which backend is currently active.
    public func currentBackend() -> EmbeddingBackendKind? {
        activeBackend
    }

    /// Whether any embedding backend is available.
    public func isAvailable() async -> Bool {
        if let backend = coreMLBackend, await backend.isAvailable { return true }
        if await rustBackend.isAvailable { return true }
        return true
    }

    // MARK: - Private

    /// Find vocab.txt in the app bundle.
    private static func findBundleVocab() -> URL? {
        if let url = Bundle.main.url(forResource: "vocab", withExtension: "txt") {
            return url
        }
        let modelsDir = Bundle.main.bundleURL
            .deletingLastPathComponent()
            .appendingPathComponent("Models")
        let fallback = modelsDir.appendingPathComponent("vocab.txt")
        if FileManager.default.fileExists(atPath: fallback.path) {
            return fallback
        }
        return nil
    }
}
