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
