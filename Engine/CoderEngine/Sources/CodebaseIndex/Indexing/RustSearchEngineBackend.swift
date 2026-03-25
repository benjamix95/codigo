import Foundation

struct RustSearchEngineBackend: SearchEngineBackend {
    let kind: SearchEngineBackendKind = .rust

    /// Swift fallback used when Rust dylib is unavailable (e.g. in XCTest).
    private let swiftFallback = SwiftSearchEngineBackend()

    func search(
        query: SearchQueryInput,
        snapshot: SemanticIndexSearchSnapshot
    ) -> SearchEngineBackendResponse {
        if let response = RustSearchFFIClient.shared.performSearch(query: query, snapshot: snapshot) {
            return response
        }

        // Fallback to Swift backend when Rust dylib is unavailable.
        SemanticIndex.logger.info("rust search backend unavailable; falling back to Swift BM25")
        let fallbackResponse = swiftFallback.search(query: query, snapshot: snapshot)
        return SearchEngineBackendResponse(
            hits: fallbackResponse.hits,
            metrics: SearchBackendMetrics(
                backendKind: .rust,
                elapsedMs: fallbackResponse.metrics.elapsedMs,
                hitCount: fallbackResponse.metrics.hitCount,
                usedFallback: true,
                loadedRustLibrary: false,
                errorMessage: nil
            )
        )
    }
}
