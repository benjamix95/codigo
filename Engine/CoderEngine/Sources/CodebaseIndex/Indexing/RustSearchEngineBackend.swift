import Foundation

struct RustSearchEngineBackend: SearchEngineBackend {
    let kind: SearchEngineBackendKind = .rust
    private let fallback = SwiftSearchEngineBackend()

    func search(
        query: SearchQueryInput,
        snapshot: SemanticIndexSearchSnapshot
    ) -> [SearchHitOutput] {
        SemanticIndex.logger.notice(
            "rust search backend requested but bridge is not linked; using swift fallback"
        )
        return fallback.search(query: query, snapshot: snapshot)
    }
}
