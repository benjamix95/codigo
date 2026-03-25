import Foundation
import OSLog

private let trigramPipelineLogger = Logger(subsystem: "com.solocode.CoderEngine", category: "TrigramPipeline")

// MARK: - CodebaseIndex Trigram Pipeline

extension CodebaseIndex {

    /// Lazily-created trigram search service.
    var trigramService: TrigramSearchService? {
        guard ProcessInfo.processInfo.environment["SOLOCODE_ENABLE_TRIGRAM_INDEX"] == "1" else {
            return nil
        }
        if Self._sharedTrigramService == nil {
            Self._sharedTrigramService = TrigramSearchService()
        }
        return Self._sharedTrigramService
    }

    private static var _sharedTrigramService: TrigramSearchService?

    // MARK: - Build

    /// Build the trigram index from all indexed files.
    /// Called after the main file scan completes.
    func buildTrigramIndex() async {
        guard let service = trigramService else { return }

        let files: [(path: String, content: String, contentHash: UInt64)] = indexedFiles.compactMap { (path, indexedFile) in
            guard let absPath = resolveAbsolutePath(for: indexedFile) else { return nil }
            guard let content = try? String(contentsOfFile: absPath, encoding: .utf8) else { return nil }
            let hash = contentHashes[absPath] ?? 0
            return (path: path, content: content, contentHash: hash)
        }

        guard !files.isEmpty else {
            trigramPipelineLogger.info("No files to build trigram index for")
            return
        }

        trigramPipelineLogger.info("Building trigram index for \(files.count) files")
        await service.buildIndex(files: files)
    }

    /// Update the trigram index with changed files.
    func updateTrigramIndex(changedFiles: [(path: String, absolutePath: String)]) async {
        guard let service = trigramService else { return }

        let files: [(path: String, content: String, contentHash: UInt64)] = changedFiles.compactMap { (path, absPath) in
            guard let content = try? String(contentsOfFile: absPath, encoding: .utf8) else { return nil }
            let hash = contentHashes[absPath] ?? 0
            return (path: path, content: content, contentHash: hash)
        }

        guard !files.isEmpty else { return }
        await service.updateIndex(changedFiles: files)
    }

    /// Search using the trigram index if available.
    public func trigramSearch(
        pattern: String,
        maxResults: Int = 200,
        caseSensitive: Bool = false
    ) async -> TrigramSearchResult? {
        guard let service = trigramService else { return nil }
        return await service.search(
            pattern: pattern,
            maxResults: maxResults,
            caseSensitive: caseSensitive
        )
    }

    // MARK: - Private

    /// Resolve absolute path for an indexed file.
    private func resolveAbsolutePath(for file: IndexedFile) -> String? {
        if !file.absolutePath.isEmpty {
            return file.absolutePath
        }
        for root in currentWorkspacePaths {
            let candidate = root.appendingPathComponent(file.relativePath).path
            if FileManager.default.fileExists(atPath: candidate) {
                return candidate
            }
        }
        return nil
    }
}
