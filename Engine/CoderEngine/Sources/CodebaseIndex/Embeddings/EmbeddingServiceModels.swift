import Foundation

// MARK: - EmbeddingBackendKind

/// Which backend produced the embeddings.
public enum EmbeddingBackendKind: String, Sendable, Codable {
    case coreML = "coreml"
    case rustONNX = "rust_onnx"
    case pseudoHash = "pseudo_hash"
}

// MARK: - EmbeddingResult

/// A single embedding result.
public struct EmbeddingResult: Sendable {
    public let text: String
    public let vector: [Float]
    public let backend: EmbeddingBackendKind
}

// MARK: - EmbeddingBatchResult

/// Result of a batch embedding call.
public struct EmbeddingBatchResult: Sendable {
    public let results: [EmbeddingResult]
    public let backend: EmbeddingBackendKind
    public let elapsedMs: Int
}

// MARK: - RustEmbedRequest / Response (FFI JSON models)

struct RustEmbedRequest: Encodable {
    let texts: [String]
    let modelPath: String?
}

struct RustEmbedResponse: Decodable {
    let embeddings: [[Float]]
    let error: RustEmbedError?
}

struct RustEmbedError: Decodable {
    let code: String
    let message: String
}
