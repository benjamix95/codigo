import Foundation

extension UnifiedToolRuntime {
    func fuseHybridSearchResults(
        hits: [HybridSourceHit],
        request: HybridSearchRequest,
        grepFallbackSkippedReason: String?
    ) -> ([HybridScoredResult], HybridSearchDiagnostics) {
        let weights: [HybridSearchSource: Double] = [
            .semanticIndex: 0.8,
            .vectorIndex: 1.2,
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
            var semanticContribution: Double
        }

        var sourceHits: [HybridSearchSource: Int] = [:]
        var accumulators: [String: Accumulator] = [:]
        var order = 0
        var dedupedCount = 0

        for hit in hits {
            sourceHits[hit.source, default: 0] += 1
            let weight = weights[hit.source, default: 0.2]
            let rrfScore = weight / (rrfK + Double(hit.rank))
            let confidence = max(0.05, hit.sourceConfidence)
            let contribution = rrfScore * confidence
            let qualityNudge: Double = {
                switch hit.source {
                case .vectorIndex: return 0.010 * confidence
                case .semanticIndex: return 0.008 * confidence
                default: return 0.004 * confidence
                }
            }()

            if var current = accumulators[hit.key] {
                dedupedCount += 1
                current.fusedScore += contribution + qualityNudge
                current.weightedConfidenceSum += weight * hit.sourceConfidence
                current.weightSum += weight
                current.sourceBreakdown[hit.source, default: 0] += contribution
                if hit.source == .semanticIndex {
                    current.semanticContribution += contribution
                }
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
                    fusedScore: contribution + qualityNudge,
                    weightedConfidenceSum: weight * hit.sourceConfidence,
                    weightSum: weight,
                    firstSeenOrder: order,
                    sourceBreakdown: [hit.source: contribution],
                    semanticContribution: hit.source == .semanticIndex ? contribution : 0
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
            if abs(lhs.fusedScore - rhs.fusedScore) < 0.0005 {
                if lhs.confidence != rhs.confidence { return lhs.confidence > rhs.confidence }
                let lhsSemantic = accumulators[lhs.key]?.semanticContribution ?? 0
                let rhsSemantic = accumulators[rhs.key]?.semanticContribution ?? 0
                if lhsSemantic != rhsSemantic { return lhsSemantic > rhsSemantic }
            }
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
            dedupedCount: dedupedCount,
            grepFallbackSkippedReason: grepFallbackSkippedReason
        )
        return (top, diagnostics)
    }
}
