import Foundation
import os

// MARK: - CodebaseIndex

/// Main actor that builds and maintains the codebase index.
/// Scans the workspace, extracts symbols from each source file,
/// builds the file tree and provides fast query APIs.
public actor CodebaseIndex {

    static let logger = Logger(subsystem: "com.solocode.CoderEngine", category: "CodebaseIndex")

    // MARK: - State

    /// File tree for each workspace root
    var fileTrees: [String: FileNode] = [:]  // rootPath -> FileNode tree

    /// Indexed files (relativePath -> IndexedFile)
    var indexedFiles: [String: IndexedFile] = [:]

    /// Symbol lookup by name (lowercase name -> [IndexedSymbol])
    var symbolsByName: [String: [IndexedSymbol]] = [:]

    /// Symbol lookup by file (relativePath -> [IndexedSymbol])
    var symbolsByFile: [String: [IndexedSymbol]] = [:]

    /// Symbol lookup by kind
    var symbolsByKind: [SymbolKind: [IndexedSymbol]] = [:]

    /// All file nodes (relativePath -> FileNode)
    var allFileNodes: [String: FileNode] = [:]

    /// Import graph: file -> [imported modules]
    var importGraph: [String: [String]] = [:]

    /// Reverse import graph: module -> [files that import it]
    var reverseImportGraph: [String: [String]] = [:]

    /// Content hashes for cache invalidation (absolutePath -> hash)
    var contentHashes: [String: UInt64] = [:]

    /// Timestamp of the last full indexing
    var lastFullIndexAt: Date?

    /// Currently indexed workspace paths
    var currentWorkspacePaths: [URL] = []

    /// Excluded path patterns
    var excludedPaths: [String] = []

    /// Excluded file patterns (glob)
    var excludedFilePatterns: [String] = []

    /// Parsed .gitignore rules: (pattern, isNegation, isDirectoryOnly)
    var gitignoreRules: [(pattern: String, isNegation: Bool, isDirectoryOnly: Bool)] = []

    /// Parsed .gitignore rules per workspace root name (for multi-root workspaces).
    var gitignoreRulesByRoot: [String: [(pattern: String, isNegation: Bool, isDirectoryOnly: Bool)]] = [:]

    /// Whether to respect .gitignore
    var respectGitignore: Bool = true

    /// Index status
    var _status: IndexStatus = .idle

    /// Indexing progress (non-nil only while indexing)
    var _indexingProgress: (current: Int, total: Int)?

    enum RealtimeChangeKind: Sendable {
        case upsert
        case remove
    }

    struct RealtimeQueuedChange: Sendable {
        let absolutePath: String
        let relativePath: String
        let kind: RealtimeChangeKind
        let enqueuedAt: Date
        let sequence: UInt64
    }

    /// True while `indexWorkspace`/`incrementalUpdate` is rebuilding core maps.
    var isWorkspaceRebuildInProgress = false

    /// File watcher events received during rebuild; flushed when rebuild completes.
    var queuedRealtimeChanges: [String: RealtimeQueuedChange] = [:]
    var realtimeQueueSequence: UInt64 = 0

    /// Semantic search index (BM25 + AST chunking + Merkle tree)
    public let semanticIndex = SemanticIndex()

    /// Counters
    var totalFilesScanned: Int = 0
    var totalSymbolsExtracted: Int = 0
    var indexDurationMs: Int = 0

    // MARK: - Configuration

    /// Default excluded directories
    static let defaultExcludedDirs = ExcludedDirectories.defaultSet

    /// Indexable source file extensions
    static let indexableExtensions: Set<String> = [
        "swift", "m", "mm", "c", "cpp", "cc", "cxx", "h", "hpp", "hxx",
        "py", "pyw", "pyi",
        "js", "mjs", "cjs", "jsx",
        "ts", "mts", "cts", "tsx",
        "go",
        "rs",
        "java",
        "kt", "kts",
        "rb", "rake",
        "php",
        "cs",
        "html", "htm",
        "css", "scss", "sass", "less",
        "json", "jsonc", "json5",
        "yml", "yaml",
        "toml",
        "xml", "plist", "xib", "storyboard",
        "md", "markdown", "rst",
        "sh", "bash", "zsh", "fish",
        "sql",
        "graphql", "gql",
        "proto",
        "dart",
        "ex", "exs",
        "lua",
        "r", "R",
        "scala", "sc",
        "hs",
        "zig",
    ]

    /// Maximum file size to index (1 MB)
    static let maxFileSize: UInt64 = 1_048_576

    /// Maximum number of indexable files
    static let maxFiles: Int = 50_000

    /// File processati in parallelo per onda durante `indexWorkspace` (estrazione simboli).
    static let indexParallelSymbolBatchSize = 96

    // MARK: - Init

    public init() {}

    public func metricsSnapshot() async -> IndexingMetricsSnapshot {
        let semanticStatus = await semanticIndex.status()
        return IndexingMetricsSnapshot(
            indexedFiles: indexedFiles.count,
            indexedSymbols: totalSymbolsExtracted,
            indexDurationMs: indexDurationMs,
            lastFullIndexAt: lastFullIndexAt,
            semanticChunks: semanticStatus.totalChunks,
            semanticTokens: semanticStatus.totalTokens
        )
    }

    // MARK: - Persistence

    /// Sorted, pipe-joined filesystem paths — must match MCP env `SOLOCODE_WORKSPACE_INDEX_PATHS`.
    public static func indexCachePathsKey(for workspacePaths: [URL]) -> String {
        workspacePaths.map(\.path).sorted().joined(separator: "|")
    }

    /// Hex directory name under `…/Caches/Solo Code/index/` — same DJB2 as `mcp_index_cache` (Rust).
    public static func indexCacheDirectoryHashHex(for workspacePaths: [URL]) -> String {
        let pathsString = indexCachePathsKey(for: workspacePaths)
        let hash = pathsString.utf8.reduce(UInt64(5381)) { ($0 &<< 5) &+ $0 &+ UInt64($1) }
        return String(hash, radix: 16, uppercase: false)
    }

    /// Compute a stable cache directory for the given workspace paths.
    static func cacheDirectory(for workspacePaths: [URL]) -> URL {
        let hashHex = indexCacheDirectoryHashHex(for: workspacePaths)

        let cacheDir = (FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory)
            .appendingPathComponent("Solo Code", isDirectory: true)
            .appendingPathComponent("index", isDirectory: true)
            .appendingPathComponent(hashHex, isDirectory: true)

        try? FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
        return cacheDir
    }
}
