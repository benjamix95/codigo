import Foundation
import os

// MARK: - SemanticIndex

/// BM25-based semantic index for code search by meaning.
/// Uses AST-aware semantic chunks and inverted indexing for fast retrieval.
public actor SemanticIndex {
    static let logger = Logger(subsystem: "com.codigo.CoderEngine", category: "SemanticIndex")

    // MARK: - BM25 Parameters
    let k1: Double = 1.2
    let b: Double = 0.75

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

    // MARK: - Chunk Budget (LRU Eviction)
    /// Limite massimo di chunk in memoria. Default 50K.
    let maxChunks: Int
    /// Timestamp di ultimo accesso per ogni chunkId (LRU tracking).
    var chunkAccessOrder: [String: Date] = [:]
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
