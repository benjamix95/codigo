import Foundation
import OSLog

private let logger = Logger(subsystem: "com.solocode.CoderEngine", category: "TrigramSearch")

// MARK: - TrigramSearchService

/// Actor that manages the trigram inverted index for instant grep.
/// The index is built in the background and queried via Rust FFI.
public actor TrigramSearchService {

    private var status: TrigramIndexStatus = TrigramIndexStatus(
        fileCount: 0, trigramCount: 0, isReady: false, lastBuildMs: 0
    )
    private var buildTask: Task<Void, Never>?

    // MARK: - Build

    /// Build the trigram index from all workspace files.
    /// Runs on a background task and does not block.
    public func buildIndex(files: [(path: String, content: String, contentHash: UInt64)]) {
        guard ProcessInfo.processInfo.environment["SOLOCODE_ENABLE_TRIGRAM_INDEX"] == "1" else {
            return
        }
        buildTask?.cancel()
        buildTask = Task.detached(priority: .utility) { [files] in
            let start = Date()
            guard let response = TrigramSearchFFIBridge.buildIndex(files: files) else {
                logger.error("Trigram index build failed")
                return
            }
            let elapsed = Int(Date().timeIntervalSince(start) * 1000)
            logger.info("Trigram index built: \(response.fileCount) files, \(response.trigramCount) trigrams in \(elapsed)ms")

            await MainActor.run { }  // yield
        }
    }

    /// Update the index with changed files (incremental).
    public func updateIndex(changedFiles: [(path: String, content: String, contentHash: UInt64)]) {
        guard status.isReady, !changedFiles.isEmpty else { return }
        Task.detached(priority: .utility) { [changedFiles] in
            _ = TrigramSearchFFIBridge.updateIndex(files: changedFiles)
            logger.info("Trigram index updated: \(changedFiles.count) files")
        }
    }

    // MARK: - Search

    /// Search using the trigram index. Returns nil if index is not ready.
    public func search(
        pattern: String,
        maxResults: Int = 200,
        caseSensitive: Bool = false
    ) -> TrigramSearchResult? {
        guard status.isReady else { return nil }

        guard let response = TrigramSearchFFIBridge.search(
            pattern: pattern,
            maxResults: maxResults,
            caseSensitive: caseSensitive
        ) else { return nil }

        let hits = response.matches.map {
            TrigramSearchHit(
                filePath: $0.filePath,
                line: $0.line,
                column: $0.column,
                snippet: $0.snippet
            )
        }

        return TrigramSearchResult(
            matches: hits,
            candidatesChecked: response.candidatesChecked,
            totalFiles: response.totalFiles,
            elapsedUs: response.elapsedUs
        )
    }

    // MARK: - Status

    /// Current index status.
    public func currentStatus() -> TrigramIndexStatus {
        status
    }

    /// Whether the trigram index is ready for queries.
    public var isReady: Bool { status.isReady }

    /// Update status after a successful build.
    func updateStatus(_ newStatus: TrigramIndexStatus) {
        self.status = newStatus
    }
}
