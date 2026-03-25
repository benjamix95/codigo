import Foundation
import OSLog

private let logger = Logger(subsystem: "com.solocode.CoderEngine", category: "HybridSearchBackend")

// MARK: - HybridSearchEngineBackend

/// Composes a lexical backend (BM25 via Swift/Rust) with a vector backend
/// (pgvector cosine similarity). Runs both in parallel and merges results
/// via Reciprocal Rank Fusion (RRF).
public final class HybridSearchEngineBackend: SearchEngineBackend, @unchecked Sendable {

    public let kind: SearchEngineBackendKind = .hybrid
    public let supportsVectorSearch: Bool = true

    private let lexicalBackend: any SearchEngineBackend
    private let vectorBackend: VectorSearchEngineBackend
    private let embeddingService: EmbeddingService

    /// RRF parameter K (higher = more weight to lower-ranked results).
    private let rrfK: Double = 50

    /// Weight multipliers for each source.
    private let lexicalWeight: Double = 0.8
    private let vectorWeight: Double = 1.2

    public init(
        lexicalBackend: any SearchEngineBackend,
        vectorBackend: VectorSearchEngineBackend,
        embeddingService: EmbeddingService
    ) {
        self.lexicalBackend = lexicalBackend
        self.vectorBackend = vectorBackend
        self.embeddingService = embeddingService
    }

    // MARK: - Combined search

    public func search(
        query: SearchQueryInput,
        snapshot: SemanticIndexSearchSnapshot
    ) -> SearchEngineBackendResponse {
        let start = Date()
        let lexicalResponse = lexicalBackend.search(query: query, snapshot: snapshot)

        // Merge with vector results (blocking wrapper for sync protocol).
        let merged = mergeWithVectorSync(
            lexicalHits: lexicalResponse.hits,
            query: query
        )

        let elapsed = Int(Date().timeIntervalSince(start) * 1000)
        return SearchEngineBackendResponse(
            hits: merged,
            metrics: SearchBackendMetrics(
                backendKind: .hybrid,
                elapsedMs: elapsed,
                hitCount: merged.count,
                usedFallback: false,
                loadedRustLibrary: lexicalResponse.metrics.loadedRustLibrary,
                errorMessage: nil
            )
        )
    }

    public func vectorSearch(
        queryEmbedding: [Float],
        limit: Int,
        threshold: Double
    ) async -> [SearchHitOutput] {
        await vectorBackend.vectorSearch(
            queryEmbedding: queryEmbedding,
            limit: limit,
            threshold: threshold
        )
    }

    // MARK: - RRF Fusion

    private func mergeWithVectorSync(
        lexicalHits: [SearchHitOutput],
        query: SearchQueryInput
    ) -> [SearchHitOutput] {
        // Get embedding for the query.
        var vectorHits: [SearchHitOutput] = []

        // Use a semaphore to bridge async → sync (within the search protocol).
        let semaphore = DispatchSemaphore(value: 0)
        Task.detached { [weak self] in
            guard let self else { semaphore.signal(); return }
            if let embedding = await self.embeddingService.embed(query.query) {
                vectorHits = await self.vectorBackend.vectorSearch(
                    queryEmbedding: embedding,
                    limit: query.numResults,
                    threshold: 0.3
                )
            }
            semaphore.signal()
        }
        // Timeout after 500ms — don't block indefinitely.
        _ = semaphore.wait(timeout: .now() + 0.5)

        guard !vectorHits.isEmpty else { return lexicalHits }
        return rrfMerge(lexicalHits: lexicalHits, vectorHits: vectorHits, limit: query.numResults)
    }

    private func rrfMerge(
        lexicalHits: [SearchHitOutput],
        vectorHits: [SearchHitOutput],
        limit: Int
    ) -> [SearchHitOutput] {
        var scores: [String: Double] = [:]

        // Lexical RRF scores.
        for (rank, hit) in lexicalHits.enumerated() {
            let rrfScore = lexicalWeight / (rrfK + Double(rank + 1))
            scores[hit.chunkId, default: 0] += rrfScore
        }

        // Vector RRF scores.
        for (rank, hit) in vectorHits.enumerated() {
            let rrfScore = vectorWeight / (rrfK + Double(rank + 1))
            scores[hit.chunkId, default: 0] += rrfScore
        }

        // Sort by fused score.
        let sorted = scores.sorted { $0.value > $1.value }
        return sorted.prefix(limit).map {
            SearchHitOutput(chunkId: $0.key, score: $0.value)
        }
    }
}
