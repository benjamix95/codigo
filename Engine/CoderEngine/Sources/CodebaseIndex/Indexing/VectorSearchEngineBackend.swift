import Foundation
import OSLog

private let logger = Logger(subsystem: "com.solocode.CoderEngine", category: "VectorSearchBackend")

// MARK: - VectorSearchEngineBackend

/// Search backend that queries pgvector for cosine-similarity matches.
/// Used as a component inside `HybridSearchEngineBackend`.
public struct VectorSearchEngineBackend: SearchEngineBackend {

    public let kind: SearchEngineBackendKind = .vector
    public let supportsVectorSearch: Bool = true

    private nonisolated(unsafe) let store: PostgresPersistenceStore

    public init(store: PostgresPersistenceStore = .shared) {
        self.store = store
    }

    // MARK: - Lexical search (not supported — use HybridSearchEngineBackend)

    public func search(
        query: SearchQueryInput,
        snapshot: SemanticIndexSearchSnapshot
    ) -> SearchEngineBackendResponse {
        // Vector backend does not do lexical search.
        SearchEngineBackendResponse(
            hits: [],
            metrics: SearchBackendMetrics(
                backendKind: .vector,
                elapsedMs: 0,
                hitCount: 0,
                usedFallback: false,
                loadedRustLibrary: false,
                errorMessage: "vector-only backend — use vectorSearch()"
            )
        )
    }

    // MARK: - Vector search

    public func vectorSearch(
        queryEmbedding: [Float],
        limit: Int,
        threshold: Double
    ) async -> [SearchHitOutput] {
        let start = Date()
        do {
            let hits = try store.vectorSearch(
                queryEmbedding: queryEmbedding,
                limit: limit,
                threshold: threshold
            )
            let elapsed = Int(Date().timeIntervalSince(start) * 1000)
            logger.info("Vector search: \(hits.count) hits in \(elapsed)ms")
            return hits.map { SearchHitOutput(chunkId: $0.id, score: $0.score) }
        } catch {
            logger.error("Vector search failed: \(error.localizedDescription)")
            return []
        }
    }

    /// Check if pgvector is available in the database.
    public func isAvailable() -> Bool {
        (try? store.isVectorSearchAvailable()) ?? false
    }
}
