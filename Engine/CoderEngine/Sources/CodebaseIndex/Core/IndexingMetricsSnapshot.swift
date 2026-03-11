import Foundation

public struct IndexingMetricsSnapshot: Codable, Equatable, Sendable {
    public let indexedFiles: Int
    public let indexedSymbols: Int
    public let indexDurationMs: Int
    public let lastFullIndexAt: Date?
    public let semanticChunks: Int
    public let semanticTokens: Int

    public init(
        indexedFiles: Int,
        indexedSymbols: Int,
        indexDurationMs: Int,
        lastFullIndexAt: Date?,
        semanticChunks: Int,
        semanticTokens: Int
    ) {
        self.indexedFiles = indexedFiles
        self.indexedSymbols = indexedSymbols
        self.indexDurationMs = indexDurationMs
        self.lastFullIndexAt = lastFullIndexAt
        self.semanticChunks = semanticChunks
        self.semanticTokens = semanticTokens
    }
}
