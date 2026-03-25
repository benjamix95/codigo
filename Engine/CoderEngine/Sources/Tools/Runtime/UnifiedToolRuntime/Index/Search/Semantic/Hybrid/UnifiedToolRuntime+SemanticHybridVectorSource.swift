import Foundation
import OSLog

private let vectorSourceLogger = Logger(subsystem: "com.solocode.CoderEngine", category: "HybridVectorSource")

extension UnifiedToolRuntime {

    /// Collect hits from the pgvector embedding index.
    /// Returns empty if vector search is disabled or the embedding service is unavailable.
    func collectVectorIndexHits(
        request: HybridSearchRequest,
        index: CodebaseIndex
    ) async -> [HybridSourceHit] {
        // Check feature flag.
        guard ProcessInfo.processInfo.environment["SOLOCODE_ENABLE_VECTOR_SEARCH"] == "1" else {
            return []
        }

        guard let embeddingService = await index.embeddingServiceIfAvailable else {
            return []
        }

        // Embed the query text.
        guard let queryEmbedding = await embeddingService.embed(request.query) else {
            vectorSourceLogger.info("Vector source: could not embed query — skipping")
            return []
        }

        // Query pgvector.
        let store = PostgresPersistenceStore.shared
        let vectorHits: [VectorSearchHit]
        do {
            vectorHits = try store.vectorSearch(
                queryEmbedding: queryEmbedding,
                limit: max(20, request.numResults * 3),
                threshold: max(0.25, request.minConfidence * 0.6)
            )
        } catch {
            vectorSourceLogger.error("Vector search query failed: \(error.localizedDescription)")
            return []
        }

        guard !vectorHits.isEmpty else { return [] }

        // Convert to HybridSourceHit.
        let maxScore = max(vectorHits.first?.score ?? 1.0, 0.01)
        return vectorHits.enumerated().map { idx, hit in
            let confidence = max(0.05, min(1.0, hit.score / maxScore))
            return HybridSourceHit(
                key: buildHitKey(filePath: hit.filePath, lineStart: hit.startLine),
                source: .vectorIndex,
                rank: idx + 1,
                sourceScore: hit.score,
                sourceConfidence: confidence,
                filePath: hit.filePath,
                lineStart: hit.startLine,
                lineEnd: hit.endLine,
                scope: hit.scope,
                snippet: hit.symbolNames.joined(separator: ", ")
            )
        }
    }
}
