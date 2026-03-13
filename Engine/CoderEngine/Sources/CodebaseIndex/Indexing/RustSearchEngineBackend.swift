import Foundation

struct RustSearchEngineBackend: SearchEngineBackend {
    let kind: SearchEngineBackendKind = .rust

    func search(
        query: SearchQueryInput,
        snapshot: SemanticIndexSearchSnapshot
    ) -> SearchEngineBackendResponse {
        if let response = RustSearchFFIClient.shared.performSearch(query: query, snapshot: snapshot) {
            return response
        }

        SemanticIndex.logger.error("rust search backend unavailable; semantic search aborted")
        return SearchEngineBackendResponse(
            hits: [],
            metrics: SearchBackendMetrics(
                backendKind: .rust,
                elapsedMs: 0,
                hitCount: 0,
                usedFallback: false,
                loadedRustLibrary: false,
                errorMessage: "Rust backend unavailable; semantic search requires Rust core"
            )
        )
    }
}
