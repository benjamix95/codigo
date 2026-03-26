import Foundation

/// Centralized feature flags for the codebase index.
/// Reads from UserDefaults (set by AppStorage in Settings UI)
/// with environment variable override for tests/CI.
public enum IndexFeatureFlags {

    // MARK: - Vector Search

    /// Whether vector search (pgvector + CoreML embeddings) is enabled.
    /// Reads `vector_search_enabled` from UserDefaults (default: true).
    /// Override: set env `SOLOCODE_ENABLE_VECTOR_SEARCH=0` to force OFF.
    public static var vectorSearchEnabled: Bool {
        if let envOverride = ProcessInfo.processInfo.environment["SOLOCODE_ENABLE_VECTOR_SEARCH"] {
            return envOverride == "1"
        }
        return UserDefaults.standard.object(forKey: "vector_search_enabled") as? Bool ?? true
    }

    /// Chunk per chiamata a `embedBatch` durante l’indicizzazione (default 64).
    /// Env: `SOLOCODE_EMBEDDING_BATCH_SIZE` (1…256). UserDefaults: `embedding_index_batch_size`.
    public static var embeddingIndexBatchSize: Int {
        if let raw = ProcessInfo.processInfo.environment["SOLOCODE_EMBEDDING_BATCH_SIZE"],
           let v = Int(raw), v > 0, v <= 256 {
            return v
        }
        if let v = UserDefaults.standard.object(forKey: "embedding_index_batch_size") as? Int,
           v > 0, v <= 256 {
            return v
        }
        return 64
    }

    /// Soglia minima testi per provare prima il backend Rust (batch ONNX) rispetto a CoreML sequenziale.
    public static var embeddingRustPreferredMinBatch: Int {
        if let raw = ProcessInfo.processInfo.environment["SOLOCODE_EMBEDDING_RUST_MIN_BATCH"],
           let v = Int(raw), v >= 1, v <= 256 {
            return v
        }
        return 8
    }

    // MARK: - Trigram / Instant Grep

    /// Whether the trigram inverted index (instant grep) is enabled.
    /// Reads `trigram_index_enabled` from UserDefaults (default: true).
    public static var trigramIndexEnabled: Bool {
        if let envOverride = ProcessInfo.processInfo.environment["SOLOCODE_ENABLE_TRIGRAM_INDEX"] {
            return envOverride == "1"
        }
        return UserDefaults.standard.object(forKey: "trigram_index_enabled") as? Bool ?? true
    }

    // MARK: - Respect .gitignore

    /// Whether to respect .gitignore rules during indexing.
    /// Reads `codebase_index_respect_gitignore` from UserDefaults (default: true).
    public static var respectGitignore: Bool {
        UserDefaults.standard.object(forKey: "codebase_index_respect_gitignore") as? Bool ?? true
    }
}
