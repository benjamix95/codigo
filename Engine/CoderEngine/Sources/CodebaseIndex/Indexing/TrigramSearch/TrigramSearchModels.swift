import Foundation

// MARK: - TrigramSearchHit

/// A single match from the trigram-accelerated grep.
public struct TrigramSearchHit: Sendable, Identifiable {
    public let id = UUID()
    public let filePath: String
    public let line: Int
    public let column: Int
    public let snippet: String
}

// MARK: - TrigramSearchResult

/// Result of a trigram grep search.
public struct TrigramSearchResult: Sendable {
    public let matches: [TrigramSearchHit]
    public let candidatesChecked: Int
    public let totalFiles: Int
    public let elapsedUs: Int
}

// MARK: - TrigramIndexStatus

/// Status of the trigram index.
public struct TrigramIndexStatus: Sendable {
    public let fileCount: Int
    public let trigramCount: Int
    public let isReady: Bool
    public let lastBuildMs: Int
}

// MARK: - FFI JSON models (internal)

struct TrigramBuildRequest: Encodable {
    let files: [TrigramBuildFileEntry]
}

struct TrigramBuildFileEntry: Encodable {
    let path: String
    let content: String
    let contentHash: UInt64
}

struct TrigramBuildResponse: Decodable {
    let fileCount: Int
    let trigramCount: Int
    let elapsedMs: Int
}

struct TrigramSearchRequest: Encodable {
    let pattern: String
    let maxResults: Int?
    let caseSensitive: Bool?
    let fileContents: [UInt32: String]?
}

struct TrigramSearchResponse: Decodable {
    let matches: [TrigramMatchResponse]
    let candidatesChecked: Int
    let totalFiles: Int
    let elapsedUs: Int
}

struct TrigramMatchResponse: Decodable {
    let filePath: String
    let line: Int
    let column: Int
    let snippet: String
}
