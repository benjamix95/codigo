import Foundation

extension UnifiedToolRuntime {
    func grepFallbackSkipReason(
        indexedHits: [HybridSourceHit],
        request: HybridSearchRequest
    ) -> String? {
        guard !indexedHits.isEmpty else { return nil }

        let preferredHits = indexedHits.filter { $0.source != .grepFallback }
        guard !preferredHits.isEmpty else { return nil }

        let requiredUniqueHits = min(request.numResults, 3)
        let uniquePreferredHits = Set(preferredHits.map(\.key))
        guard uniquePreferredHits.count >= requiredUniqueHits else { return nil }

        let semanticOrVectorHits = preferredHits.filter {
            $0.source == .semanticIndex || $0.source == .vectorIndex
        }
        let uniqueSemanticOrVectorHits = Set(semanticOrVectorHits.map(\.key))
        let confidenceThreshold = max(request.minConfidence, 0.60)
        let confidentPreferredHits = preferredHits.filter { $0.sourceConfidence >= confidenceThreshold }

        let hasEnoughSemanticSignal = uniqueSemanticOrVectorHits.count >= min(requiredUniqueHits, 2)
        let hasEnoughConfidentResults = confidentPreferredHits.count >= requiredUniqueHits
        guard hasEnoughSemanticSignal || hasEnoughConfidentResults else { return nil }

        return "indexed_hits_sufficient"
    }
}
