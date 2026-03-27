import Foundation
import os

// MARK: - SemanticIndex

/// BM25-based semantic index for code search by meaning.
/// Uses AST-aware semantic chunks and inverted indexing for fast retrieval.
public actor SemanticIndex {
    static let logger = Logger(subsystem: "com.solocode.CoderEngine", category: "SemanticIndex")

    // MARK: - BM25 Parameters
    // swiftlint:disable identifier_name
    let k1: Double = 1.2
    let b: Double = 0.75
    // swiftlint:enable identifier_name

    // MARK: - State
    var chunks: [String: SemanticChunk] = [:]  // chunkId → chunk
    var invertedIndex: [String: Set<String>] = [:]
    var termFrequencies: [String: [String: Int]] = [:]
    var docLengths: [String: Int] = [:]
    var avgDocLength: Double = 0
    var totalDocs: Int { chunks.count }
    var merkleRoot: MerkleNode?
    var currentSimHash: UInt64 = 0
    var fileToChunks: [String: [String]] = [:]
    var persistencePath: URL?
    var deferredMerkleTouchedFiles: Int = 0
    let searchBackend: any SearchEngineBackend
    var lastSearchMetrics: SearchBackendMetrics?

    // MARK: - Debounced Persistence
    /// Task per il debounce della persistenza. Cancellato e ricreato ad ogni modifica.
    var persistDebounceTask: Task<Void, Never>?
    /// Intervallo di debounce in nanosecondi (2 secondi).
    static let persistDebounceNs: UInt64 = 2_000_000_000

    // MARK: - Chunk Budget (LRU Eviction)
    /// Limite massimo di chunk in memoria. Default 50K.
    let maxChunks: Int
    /// Timestamp di ultimo accesso per ogni chunkId (LRU tracking).
    var chunkAccessOrder: [String: Date] = [:]
    /// File paths modified since last persist. Only dirty files trigger a full rewrite.
    var dirtyFilePaths: Set<String> = []
    /// Running total of all token counts across documents. Updated incrementally
    /// by addChunks/removeChunksForFile/removeChunk so that avgDocLength can be
    /// recomputed in O(1) instead of O(n).
    var totalTokenCount: Int = 0
    /// Cached JSON snapshot for Rust semantic search requests. Rebuilt only
    /// when the index simhash changes.
    var cachedRustSearchSnapshotSimHash: UInt64?
    var cachedRustSearchSnapshotJSONString: String?
    /// Soglia di warning (80% della capacità).
    static let capacityWarningThreshold: Double = 0.8

    // MARK: - Init
    public init(
        persistencePath: URL? = nil,
        maxChunks: Int = 50_000,
        searchBackend: (any SearchEngineBackend)? = nil
    ) {
        precondition(maxChunks > 0, "maxChunks deve essere positivo")
        self.persistencePath = persistencePath
        self.maxChunks = maxChunks
        self.searchBackend = searchBackend ?? SearchEngineBackendFactory.makeFromEnvironment()
    }

    /// Set or update persistence path.
    public func setPersistencePath(_ path: URL?) {
        self.persistencePath = path
    }

    public func configuredSearchBackendKind() -> SearchEngineBackendKind {
        searchBackend.kind
    }

    public func lastSearchMetricsSnapshot() -> SearchBackendMetrics? {
        lastSearchMetrics
    }

    // MARK: - Result Types

    public struct IndexStatus: Sendable {
        public let totalChunks: Int
        public let totalTokens: Int
        public let totalFiles: Int
        public let avgDocLength: Double
        public let simHash: UInt64
        public let hasMerkleTree: Bool
    }

    public struct SearchResult: Sendable {
        public let chunk: SemanticChunk
        public let score: Double

        public var displayLine: String {
            let lineInfo = chunk.startLine == chunk.endLine
                ? ":\(chunk.startLine)"
                : ":\(chunk.startLine)-\(chunk.endLine)"
            let scopeInfo = chunk.scope.isEmpty ? "" : " [\(chunk.scope)]"
            return "\(chunk.filePath)\(lineInfo)\(scopeInfo) (score: \(String(format: "%.2f", score)))"
        }
    }
}
