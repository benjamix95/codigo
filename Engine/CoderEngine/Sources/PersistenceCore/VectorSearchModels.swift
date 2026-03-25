import Foundation

// MARK: - VectorSearchHit

/// A single result returned by pgvector cosine-similarity search.
public struct VectorSearchHit: Sendable, Identifiable, Codable {
    public let id: String          // chunk_id
    public let filePath: String
    public let score: Double       // cosine similarity in [0, 1]
    public let startLine: Int
    public let endLine: Int
    public let scope: String
    public let kind: String
    public let language: String
    public let symbolNames: [String]

    public init(
        id: String,
        filePath: String,
        score: Double,
        startLine: Int,
        endLine: Int,
        scope: String,
        kind: String,
        language: String,
        symbolNames: [String]
    ) {
        self.id = id
        self.filePath = filePath
        self.score = score
        self.startLine = startLine
        self.endLine = endLine
        self.scope = scope
        self.kind = kind
        self.language = language
        self.symbolNames = symbolNames
    }
}

// MARK: - EmbeddingRecord

/// Lightweight record for checking which chunks are already embedded.
public struct EmbeddingRecord: Sendable, Codable {
    public let chunkId: String
    public let contentHash: UInt64
}

// MARK: - EmbeddingUpsertPayload

/// All fields needed to insert or update a single embedding row.
public struct EmbeddingUpsertPayload: Sendable {
    public let chunkId: String
    public let filePath: String
    public let contentHash: UInt64
    public let embedding: [Float]
    public let scope: String
    public let kind: String
    public let startLine: Int
    public let endLine: Int
    public let language: String
    public let symbolNames: [String]

    public init(
        chunkId: String,
        filePath: String,
        contentHash: UInt64,
        embedding: [Float],
        scope: String,
        kind: String,
        startLine: Int,
        endLine: Int,
        language: String,
        symbolNames: [String]
    ) {
        self.chunkId = chunkId
        self.filePath = filePath
        self.contentHash = contentHash
        self.embedding = embedding
        self.scope = scope
        self.kind = kind
        self.startLine = startLine
        self.endLine = endLine
        self.language = language
        self.symbolNames = symbolNames
    }
}
