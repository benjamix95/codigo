import Foundation

extension UnifiedToolRuntime {
    func fuseHybridSearchResults(
        hits: [HybridSourceHit],
        request: HybridSearchRequest
    ) -> ([HybridScoredResult], HybridSearchDiagnostics) {
        let weights: [HybridSearchSource: Double] = [
            .semanticIndex: 1.0,
            .symbolIndex: 0.8,
            .grepFallback: 0.45,
        ]
        let rrfK = 50.0

        struct Accumulator {
            var filePath: String
            var lineStart: Int
            var lineEnd: Int
            var scope: String
            var snippet: String
            var fusedScore: Double
            var weightedConfidenceSum: Double
            var weightSum: Double
            var firstSeenOrder: Int
            var sourceBreakdown: [HybridSearchSource: Double]
        }

        var sourceHits: [HybridSearchSource: Int] = [:]
        var accumulators: [String: Accumulator] = [:]
        var order = 0
        var dedupedCount = 0

        for hit in hits {
            sourceHits[hit.source, default: 0] += 1
            let weight = weights[hit.source, default: 0.2]
            let rrfScore = weight / (rrfK + Double(hit.rank))
            let contribution = rrfScore * max(0.05, hit.sourceConfidence)

            if var current = accumulators[hit.key] {
                dedupedCount += 1
                current.fusedScore += contribution
                current.weightedConfidenceSum += weight * hit.sourceConfidence
                current.weightSum += weight
                current.sourceBreakdown[hit.source, default: 0] += contribution
                if current.scope.isEmpty && !hit.scope.isEmpty { current.scope = hit.scope }
                if current.snippet.isEmpty && !hit.snippet.isEmpty { current.snippet = hit.snippet }
                current.lineEnd = max(current.lineEnd, hit.lineEnd)
                accumulators[hit.key] = current
            } else {
                accumulators[hit.key] = Accumulator(
                    filePath: hit.filePath,
                    lineStart: hit.lineStart,
                    lineEnd: hit.lineEnd,
                    scope: hit.scope,
                    snippet: hit.snippet,
                    fusedScore: contribution,
                    weightedConfidenceSum: weight * hit.sourceConfidence,
                    weightSum: weight,
                    firstSeenOrder: order,
                    sourceBreakdown: [hit.source: contribution]
                )
                order += 1
            }
        }

        var droppedByConfidence = 0
        let scored = accumulators.map { key, value -> HybridScoredResult? in
            let confidence = value.weightSum > 0 ? value.weightedConfidenceSum / value.weightSum : 0
            if confidence < request.minConfidence {
                droppedByConfidence += 1
                return nil
            }
            return HybridScoredResult(
                key: key,
                filePath: value.filePath,
                lineStart: value.lineStart,
                lineEnd: value.lineEnd,
                scope: value.scope,
                snippet: value.snippet,
                fusedScore: value.fusedScore,
                confidence: confidence,
                sourceBreakdown: value.sourceBreakdown
            )
        }
        .compactMap { $0 }
        .sorted { lhs, rhs in
            if lhs.fusedScore != rhs.fusedScore { return lhs.fusedScore > rhs.fusedScore }
            let lhsOrder = accumulators[lhs.key]?.firstSeenOrder ?? .max
            let rhsOrder = accumulators[rhs.key]?.firstSeenOrder ?? .max
            if lhsOrder != rhsOrder { return lhsOrder < rhsOrder }
            if lhs.filePath != rhs.filePath { return lhs.filePath < rhs.filePath }
            return lhs.lineStart < rhs.lineStart
        }

        let top = Array(scored.prefix(request.numResults))
        var sourceUsedInTop: [HybridSearchSource: Int] = [:]
        for result in top {
            for source in result.sourceBreakdown.keys {
                sourceUsedInTop[source, default: 0] += 1
            }
        }

        let diagnostics = HybridSearchDiagnostics(
            sourceHits: sourceHits,
            sourceUsedInTop: sourceUsedInTop,
            minConfidence: request.minConfidence,
            droppedByConfidence: droppedByConfidence,
            dedupedCount: dedupedCount
        )
        return (top, diagnostics)
    }
}
