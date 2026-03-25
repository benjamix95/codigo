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
    /// Returns nil if all backends are unavailable.
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
        logger.warning("No embedding backend available for text (\(text.prefix(50))...)")
        return nil
    }

    /// Embed a batch of texts. Returns one vector per input (same order).
    /// Texts whose embedding fails produce nil in the output.
    public func embedBatch(_ texts: [String]) async -> [[Float]?] {
        guard !texts.isEmpty else { return [] }

        // Try CoreML.
        if let backend = coreMLBackend {
            let results = await backend.embedBatch(texts)
            let hasNonZero = results.contains { v in v.contains { $0 != 0 } }
            if hasNonZero {
                activeBackend = .coreML
                return results.map { Optional($0) }
            }
        }

        // Try Rust.
        if let results = await rustBackend.embedBatch(texts) {
            activeBackend = .rustONNX
            return results.map { Optional($0) }
        }

        logger.warning("No embedding backend available for batch of \(texts.count) texts")
        return texts.map { _ in nil }
    }

    /// Which backend is currently active.
    public func currentBackend() -> EmbeddingBackendKind? {
        activeBackend
    }

    /// Whether any embedding backend is available.
    public func isAvailable() async -> Bool {
        if let backend = coreMLBackend, await backend.isAvailable { return true }
        if await rustBackend.isAvailable { return true }
        return false
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
