import Foundation

public enum SearchEngineBackendKind: String, Codable, Sendable, Equatable {
    case swift
    case rust
    case vector
    case hybrid
}

public struct SearchQueryInput: Codable, Sendable, Equatable {
    public let query: String
    public let targetDirectories: [String]
    public let numResults: Int

    public init(
        query: String,
        targetDirectories: [String] = [],
        numResults: Int = 25
    ) {
        self.query = query
        self.targetDirectories = targetDirectories
        self.numResults = numResults
    }
}

public struct SearchHitOutput: Codable, Sendable, Equatable {
    public let chunkId: String
    public let score: Double

    public init(chunkId: String, score: Double) {
        self.chunkId = chunkId
        self.score = score
    }
}

public struct IndexStatsOutput: Codable, Sendable, Equatable {
    public let totalChunks: Int
    public let totalTokens: Int
    public let totalFiles: Int
    public let avgDocLength: Double
    public let hasMerkleTree: Bool

    public init(
        totalChunks: Int,
        totalTokens: Int,
        totalFiles: Int,
        avgDocLength: Double,
        hasMerkleTree: Bool
    ) {
        self.totalChunks = totalChunks
        self.totalTokens = totalTokens
        self.totalFiles = totalFiles
        self.avgDocLength = avgDocLength
        self.hasMerkleTree = hasMerkleTree
    }
}

public struct SemanticIndexSearchSnapshot: Codable, Sendable {
    public let chunks: [String: SemanticChunk]
    public let invertedIndex: [String: Set<String>]
    public let termFrequencies: [String: [String: Int]]
    public let docLengths: [String: Int]
    public let avgDocLength: Double
    public let totalDocs: Int
    public let k1: Double
    public let b: Double

    public init(
        chunks: [String: SemanticChunk],
        invertedIndex: [String: Set<String>],
        termFrequencies: [String: [String: Int]],
        docLengths: [String: Int],
        avgDocLength: Double,
        totalDocs: Int,
        k1: Double,
        b: Double
    ) {
        self.chunks = chunks
        self.invertedIndex = invertedIndex
        self.termFrequencies = termFrequencies
        self.docLengths = docLengths
        self.avgDocLength = avgDocLength
        self.totalDocs = totalDocs
        self.k1 = k1
        self.b = b
    }
}

public protocol SearchEngineBackend: Sendable {
    var kind: SearchEngineBackendKind { get }
    func search(
        query: SearchQueryInput,
        snapshot: SemanticIndexSearchSnapshot
    ) -> SearchEngineBackendResponse

    /// Vector-based semantic search (optional — default returns empty).
    func vectorSearch(
        queryEmbedding: [Float],
        limit: Int,
        threshold: Double
    ) async -> [SearchHitOutput]

    /// Whether this backend supports vector similarity search.
    var supportsVectorSearch: Bool { get }
}

// Default implementations for backward compatibility.
public extension SearchEngineBackend {
    func vectorSearch(
        queryEmbedding: [Float],
        limit: Int,
        threshold: Double
    ) async -> [SearchHitOutput] { [] }

    var supportsVectorSearch: Bool { false }
}

enum SearchEngineBackendFactory {
    static func makeFromEnvironment(
        embeddingService: EmbeddingService? = nil,
        store: PostgresPersistenceStore? = nil
    ) -> any SearchEngineBackend {
        let raw = ProcessInfo.processInfo.environment["SOLOCODE_SEMANTIC_SEARCH_BACKEND"]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        let vectorEnabled = ProcessInfo.processInfo.environment["SOLOCODE_ENABLE_VECTOR_SEARCH"] == "1"

        let lexicalBackend: any SearchEngineBackend = {
            switch raw {
            case SearchEngineBackendKind.swift.rawValue:
                return SwiftSearchEngineBackend()
            default:
                return RustSearchEngineBackend()
            }
        }()

        if vectorEnabled, let embeddingService, let store {
            let vectorBackend = VectorSearchEngineBackend(store: store)
            return HybridSearchEngineBackend(
                lexicalBackend: lexicalBackend,
                vectorBackend: vectorBackend,
                embeddingService: embeddingService
            )
        }

        return lexicalBackend
    }
}

enum SemanticSearchQueryParser {
    static func splitNegations(_ query: String) -> (positive: String, negative: [String]) {
        let words = query.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
        var positiveWords: [String] = []
        var negativeTokens: [String] = []

        for word in words {
            let stripped = String(word.drop(while: { $0 == "-" }))
            let isNegated = stripped.count < word.count && !stripped.isEmpty

            if isNegated && stripped.count >= 2 {
                negativeTokens.append(
                    contentsOf: SemanticIndex.tokenizeStatic(stripped)
                        .filter { !SemanticIndex.stopWords.contains($0) }
                )
            } else {
                positiveWords.append(word)
            }
        }

        return (positiveWords.joined(separator: " "), negativeTokens)
    }
}
