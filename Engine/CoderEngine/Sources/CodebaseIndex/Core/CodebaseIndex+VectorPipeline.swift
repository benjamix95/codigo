import Foundation
import OSLog

// File-private logger (avoids conflict with CodebaseIndex.logger which is static).
private let vectorPipelineLogger = Logger(subsystem: "com.solocode.CoderEngine", category: "VectorPipeline")

// MARK: - CodebaseIndex Vector Pipeline

extension CodebaseIndex {

    /// Lazily-created embedding service.
    /// Returns nil if vector search is disabled or model unavailable.
    public var embeddingServiceIfAvailable: EmbeddingService? {
        guard IndexFeatureFlags.vectorSearchEnabled else {
            return nil
        }
        return _embeddingService
    }

    /// Internal storage for the embedding service (created on first access).
    private var _embeddingService: EmbeddingService? {
        if let cached = _cachedEmbeddingService { return cached }
        let service = EmbeddingService()
        _cachedEmbeddingService = service
        return service
    }

    // Using a global to avoid stored property in extension.
    // (In production, this should be a proper stored property on the actor.)
    private static var _sharedEmbeddingService: EmbeddingService?
    private var _cachedEmbeddingService: EmbeddingService? {
        get { Self._sharedEmbeddingService }
        set { Self._sharedEmbeddingService = newValue }
    }

    /// Lazily-created embedding indexing pipeline.
    private var _embeddingPipeline: EmbeddingIndexingPipeline? {
        guard let service = embeddingServiceIfAvailable else { return nil }
        if Self._sharedPipeline == nil {
            Self._sharedPipeline = EmbeddingIndexingPipeline(embeddingService: service)
        }
        return Self._sharedPipeline
    }

    private static var _sharedPipeline: EmbeddingIndexingPipeline?

    // MARK: - Public API

    /// Generate and store embeddings for newly indexed chunks.
    /// Called after BM25 index is built/updated.
    func generateEmbeddingsForChunks(_ chunks: [SemanticChunk]) async {
        guard let pipeline = _embeddingPipeline else { return }

        // Get existing hashes from pgvector to skip already-embedded chunks (una query per tutti i file).
        var existingHashes: [String: UInt64] = [:]
        let filePaths = Array(Set(chunks.map(\.filePath)))
        if let records = try? PostgresPersistenceStore.shared.embeddedChunkRecords(forFiles: filePaths) {
            for record in records {
                existingHashes[record.chunkId] = record.contentHash
            }
        }

        await pipeline.submitIncremental(chunks: chunks, existingHashes: existingHashes)
        vectorPipelineLogger.info("Submitted \(chunks.count) chunks to embedding pipeline (existing: \(existingHashes.count))")
    }

    /// Remove embeddings for files that were deleted or re-indexed.
    func removeEmbeddingsForFile(_ filePath: String) {
        guard IndexFeatureFlags.vectorSearchEnabled else {
            return
        }
        do {
            try PostgresPersistenceStore.shared.deleteEmbeddingsForFile(filePath)
        } catch {
            vectorPipelineLogger.error("Failed to delete embeddings for \(filePath): \(error.localizedDescription)")
        }
    }

    /// Current embedding pipeline progress (0..1).
    var embeddingProgress: Double {
        get async {
            guard let pipeline = _embeddingPipeline else { return 0 }
            return await pipeline.progress
        }
    }

    /// Whether the embedding pipeline is actively processing.
    var isEmbeddingActive: Bool {
        get async {
            guard let pipeline = _embeddingPipeline else { return false }
            return await pipeline.active
        }
    }
}
