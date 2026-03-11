import Foundation

public struct SearchEngineBackendResponse: Sendable {
    public let hits: [SearchHitOutput]
    public let metrics: SearchBackendMetrics

    public init(hits: [SearchHitOutput], metrics: SearchBackendMetrics) {
        self.hits = hits
        self.metrics = metrics
    }
}

struct RustSearchChunkPayload: Codable {
    let chunkId: String
    let filePath: String
    let scope: String
    let kind: String
    let content: String
    let symbolNames: [String]
    let contextualizedText: String
}

struct RustSearchSnapshotPayload: Codable {
    let chunks: [RustSearchChunkPayload]
    let invertedIndex: [String: [String]]
    let termFrequencies: [String: [String: Int]]
    let docLengths: [String: Int]
    let avgDocLength: Double
    let totalDocs: Int
    let k1: Double
    let b: Double
}

struct RustSearchRequestPayload: Codable {
    let query: SearchQueryInput
    let snapshot: RustSearchSnapshotPayload
}

struct RustSearchResponsePayload: Codable {
    let hits: [SearchHitOutput]
    let error: RustFFIErrorPayload?
}

struct RustTokenizeRequestPayload: Codable {
    let text: String
}

struct RustTokenizeResponsePayload: Codable {
    let hits: [String]
}

struct RustFFIErrorPayload: Codable, Equatable {
    let code: String
    let message: String
}
