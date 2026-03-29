import Foundation

extension UnifiedToolRuntime {
    func scheduleVectorBackfillIfNeeded(index: CodebaseIndex) async {
        guard IndexFeatureFlags.vectorSearchEnabled else { return }
        guard let embeddingService = await index.embeddingServiceIfAvailable else { return }
        guard await embeddingService.isAvailable() else { return }
        let embeddingActive = await index.isEmbeddingActive
        guard !embeddingActive else { return }

        let semanticStatus = await index.semanticIndex.status()
        guard semanticStatus.totalChunks > 0 else { return }

        let chunks = await index.semanticIndex.allChunks()
        guard !chunks.isEmpty else { return }

        let filePaths = Array(Set(chunks.map(\.filePath))).sorted()
        let rowCount = (try? PostgresPersistenceStore.shared.vectorSearchRowCount(forFiles: filePaths)) ?? 0
        guard rowCount == 0 else { return }

        await index.generateEmbeddingsForChunks(chunks)
    }
}
