import Foundation

struct RustSearchEngineBackend: SearchEngineBackend {
    let kind: SearchEngineBackendKind = .rust
    private let fallback = SwiftSearchEngineBackend()

    func search(
        query: SearchQueryInput,
        snapshot: SemanticIndexSearchSnapshot
    ) -> SearchEngineBackendResponse {
        if let response = RustSearchFFIClient.shared.performSearch(query: query, snapshot: snapshot) {
            return response
        }

        SemanticIndex.logger.notice("rust search backend unavailable; using swift fallback")
        let fallbackResponse = fallback.search(query: query, snapshot: snapshot)
        return SearchEngineBackendResponse(
            hits: fallbackResponse.hits,
            metrics: SearchBackendMetrics(
                backendKind: .rust,
                elapsedMs: fallbackResponse.metrics.elapsedMs,
                hitCount: fallbackResponse.hits.count,
                usedFallback: true,
                loadedRustLibrary: false,
                errorMessage: "Rust backend unavailable; fallback to Swift"
            )
        )
    }
}
