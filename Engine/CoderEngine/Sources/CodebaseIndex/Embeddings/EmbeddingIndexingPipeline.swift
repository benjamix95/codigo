import Foundation
import OSLog

private let logger = Logger(subsystem: "com.solocode.CoderEngine", category: "EmbeddingPipeline")

// MARK: - EmbeddingIndexingPipeline

/// Manages the background embedding queue for codebase indexing.
///
/// Chunks are submitted to the pipeline and embedded in batches of
/// `batchSize`. Results are stored in pgvector via `PostgresPersistenceStore`.
/// The pipeline runs on a utility-priority task and reports progress.
public actor EmbeddingIndexingPipeline {

    /// Fallback se non si usa `IndexFeatureFlags.embeddingIndexBatchSize`.
    public static let defaultBatchSize = 64

    // MARK: - State

    private let embeddingService: EmbeddingService
    private let store: PostgresPersistenceStore
    private let batchSize: Int

    private var pendingChunks: [SemanticChunk] = []
    private var isRunning = false
    private var processedCount = 0
    private var totalCount = 0
    private var currentTask: Task<Void, Never>?

    // MARK: - Init

    public init(
        embeddingService: EmbeddingService,
        store: PostgresPersistenceStore = .shared,
        batchSize: Int = IndexFeatureFlags.embeddingIndexBatchSize
    ) {
        self.embeddingService = embeddingService
        self.store = store
        self.batchSize = max(1, min(256, batchSize))
    }

    // MARK: - Public API

    /// Submit chunks for embedding. Processing starts automatically.
    public func submit(chunks: [SemanticChunk]) {
        pendingChunks.append(contentsOf: chunks)
        totalCount += chunks.count
        startIfNeeded()
    }

    /// Submit chunks but skip those already embedded with matching content hash.
    public func submitIncremental(chunks: [SemanticChunk], existingHashes: [String: UInt64]) {
        let newChunks = chunks.filter { chunk in
            guard let existingHash = existingHashes[chunk.id] else { return true }
            return existingHash != UInt64(chunk.contentWeight)
        }
        guard !newChunks.isEmpty else {
            logger.info("All \(chunks.count) chunks already embedded — skipping")
            return
        }
        logger.info("Submitting \(newChunks.count)/\(chunks.count) changed chunks for embedding")
        submit(chunks: newChunks)
    }

    /// Cancel any in-progress embedding work.
    public func cancel() {
        currentTask?.cancel()
        currentTask = nil
        isRunning = false
        pendingChunks.removeAll()
        logger.info("Embedding pipeline cancelled")
    }

    /// Current progress as a fraction [0, 1].
    public var progress: Double {
        guard totalCount > 0 else { return 0 }
        return Double(processedCount) / Double(totalCount)
    }

    /// Whether the pipeline is currently processing chunks.
    public var active: Bool { isRunning }

    /// How many chunks remain in the queue.
    public var remaining: Int { pendingChunks.count }

    // MARK: - Private

    private func startIfNeeded() {
        guard !isRunning, !pendingChunks.isEmpty else { return }
        isRunning = true

        currentTask = Task.detached(priority: .utility) { [weak self] in
            await self?.processQueue()
        }
    }

    private func processQueue() async {
        while !pendingChunks.isEmpty {
            if Task.isCancelled { break }

            let batch = Array(pendingChunks.prefix(batchSize))
            pendingChunks.removeFirst(min(batchSize, pendingChunks.count))

            await processBatch(batch)
            processedCount += batch.count
        }

        isRunning = false
        if pendingChunks.isEmpty {
            let processed = self.processedCount
            let total = self.totalCount
            logger.info("Embedding pipeline finished: \(processed)/\(total) chunks")
        }
    }

    private func processBatch(_ chunks: [SemanticChunk]) async {
        let texts = chunks.map { $0.contextualizedText }
        let embeddings = await embeddingService.embedBatch(texts)

        var payloads: [EmbeddingUpsertPayload] = []
        for (chunk, embeddingOpt) in zip(chunks, embeddings) {
            guard let embedding = embeddingOpt else { continue }
            payloads.append(EmbeddingUpsertPayload(
                chunkId: chunk.id,
                filePath: chunk.filePath,
                contentHash: UInt64(chunk.contentWeight),
                embedding: embedding,
                scope: chunk.scope,
                kind: chunk.kind,
                startLine: chunk.startLine,
                endLine: chunk.endLine,
                language: chunk.language,
                symbolNames: chunk.symbolNames
            ))
        }

        guard !payloads.isEmpty else { return }

        do {
            try store.upsertEmbeddingsBatch(payloads)
        } catch {
            logger.error("Failed to store \(payloads.count) embeddings: \(error.localizedDescription)")
        }
    }

    /// Reset counters (used after a full re-index cycle).
    public func resetProgress() {
        processedCount = 0
        totalCount = 0
    }
}
