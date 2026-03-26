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

    // MARK: - Async Search (cooperative-thread-pool safe)

    /// Async variant that runs lexical + vector search concurrently without
    /// blocking the cooperative thread pool. Callers inside actors (e.g.
    /// SemanticIndex) MUST prefer this over the sync `search()`.
    public func asyncSearch(
        query: SearchQueryInput,
        snapshot: SemanticIndexSearchSnapshot
    ) async -> SearchEngineBackendResponse {
        let start = Date()

        // Run lexical search on a non-cooperative thread to avoid actor hop issues.
        let lexicalResponse = lexicalBackend.search(query: query, snapshot: snapshot)

        // Vector search — fully async, no semaphore needed.
        let vectorHits = await mergeWithVectorAsync(query: query)

        let merged: [SearchHitOutput]
        if vectorHits.isEmpty {
            merged = lexicalResponse.hits
        } else {
            merged = rrfMerge(
                lexicalHits: lexicalResponse.hits,
                vectorHits: vectorHits,
                limit: query.numResults
            )
        }

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

    /// Async vector search with timeout — no DispatchSemaphore, fully
    /// cooperative-thread-pool safe.
    private func mergeWithVectorAsync(
        query: SearchQueryInput
    ) async -> [SearchHitOutput] {
        do {
            return try await withThrowingTaskGroup(of: [SearchHitOutput].self) { group in
                group.addTask { [weak self] in
                    guard let self else { return [] }
                    guard let embedding = await self.embeddingService.embed(query.query) else {
                        return []
                    }
                    return await self.vectorBackend.vectorSearch(
                        queryEmbedding: embedding,
                        limit: query.numResults,
                        threshold: 0.3
                    )
                }

                // 2-second timeout task.
                group.addTask {
                    try await Task.sleep(nanoseconds: 2_000_000_000)
                    return []
                }

                // Return the first result; if timeout wins, cancel the rest.
                if let first = try await group.next() {
                    if !first.isEmpty {
                        group.cancelAll()
                        return first
                    }
                    // First returned empty — could be timeout or no results.
                    // Try second if available.
                    if let second = try await group.next(), !second.isEmpty {
                        return second
                    }
                }
                return []
            }
        } catch {
            logger.warning("mergeWithVectorAsync: vector search failed: \(error.localizedDescription)")
            return []
        }
    }

    // MARK: - RRF Fusion (legacy sync path)

    /// Thread-safe box for bridging async results to sync contexts.
    private final class SendableBox<T: Sendable>: @unchecked Sendable {
        private let lock = NSLock()
        private var value: T
        init(_ initial: T) { self.value = initial }
        func set(_ newValue: T) { lock.lock(); value = newValue; lock.unlock() }
        func get() -> T { lock.lock(); defer { lock.unlock() }; return value }
    }

    /// Legacy sync bridge — retained for backward compatibility with callers
    /// that cannot use `asyncSearch()`. Prefer `asyncSearch()` in actor contexts.
    private func mergeWithVectorSync(
        lexicalHits: [SearchHitOutput],
        query: SearchQueryInput
    ) -> [SearchHitOutput] {
        let box = SendableBox<[SearchHitOutput]>([])
        let semaphore = DispatchSemaphore(value: 0)

        Task.detached { [weak self] in
            defer { semaphore.signal() }
            guard let self else { return }
            guard let embedding = await self.embeddingService.embed(query.query) else { return }
            let hits = await self.vectorBackend.vectorSearch(
                queryEmbedding: embedding,
                limit: query.numResults,
                threshold: 0.3
            )
            box.set(hits)
        }

        let waitResult = semaphore.wait(timeout: .now() + 2.0)
        if waitResult == .timedOut {
            logger.warning("mergeWithVectorSync: vector search timed out after 2s, returning lexical only")
        }

        let vectorHits = box.get()
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
