import Foundation
import OSLog

private let logger = Logger(subsystem: "com.solocode.CoderEngine", category: "RustEmbedding")

// MARK: - RustEmbeddingBackend

/// Fallback embedding backend that calls the Rust `solocode_embed_text` FFI
/// function through the already-loaded `libsolocode_rust_core.dylib`.
public actor RustEmbeddingBackend {

    public static let embeddingDim = 384

    // MARK: - Public API

    /// Embed a batch of texts via Rust FFI.
    /// Returns one 384-dim vector per text, or nil if the FFI is unavailable.
    public func embedBatch(_ texts: [String]) -> [[Float]]? {
        guard let ffiClient = resolveFFIClient() else {
            logger.warning("Rust embedding FFI not available — skipping")
            return nil
        }

        let request = RustEmbedRequest(texts: texts, modelPath: nil)
        guard let payload = try? JSONEncoder().encode(request),
              let jsonString = String(data: payload, encoding: .utf8) else {
            return nil
        }

        do {
            let response: RustEmbedResponse = try ffiClient.callReviewFunction(
                "solocode_embed_text",
                payload: jsonString
            )
            if let error = response.error {
                logger.error("Rust embed error: \(error.code) — \(error.message)")
                return nil
            }
            guard response.embeddings.count == texts.count else {
                logger.error("Rust embed: expected \(texts.count) embeddings, got \(response.embeddings.count)")
                return nil
            }
            return response.embeddings
        } catch {
            logger.error("Rust embed FFI call failed: \(error.localizedDescription)")
            return nil
        }
    }

    /// Embed a single text.
    public func embed(_ text: String) -> [Float]? {
        embedBatch([text])?.first
    }

    /// Check if the Rust FFI is reachable.
    public var isAvailable: Bool {
        resolveFFIClient() != nil
    }

    // MARK: - Private

    private func resolveFFIClient() -> RustSearchFFIClient? {
        let client = RustSearchFFIClient.shared
        // If the dylib is loaded and has the embedding symbol, we're good.
        guard client.loadedVersion() != nil else { return nil }
        return client
    }
}
