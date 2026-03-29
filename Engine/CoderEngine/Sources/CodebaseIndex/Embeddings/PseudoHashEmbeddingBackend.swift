import Foundation

enum PseudoHashEmbeddingBackend {
    static let embeddingDim = 384

    static func embed(_ text: String) -> [Float] {
        var vector = [Float](repeating: 0, count: embeddingDim)
        let bytes = Array(text.utf8)
        var hash: UInt64 = 0xcbf29ce484222325

        for (index, byte) in bytes.enumerated() {
            hash ^= UInt64(byte)
            hash = hash &* 0x100000001b3
            let normalized = (Float(hash) / Float(UInt64.max)) * 2.0 - 1.0
            vector[index % embeddingDim] += normalized
        }

        return l2Normalize(vector)
    }

    static func embedBatch(_ texts: [String]) -> [[Float]] {
        texts.map(embed)
    }

    private static func l2Normalize(_ vector: [Float]) -> [Float] {
        let norm = sqrt(vector.reduce(0) { $0 + ($1 * $1) })
        guard norm > 1e-12 else { return vector }
        return vector.map { $0 / norm }
    }
}
