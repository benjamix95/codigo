import Foundation

extension UnifiedToolRuntime {
    enum HybridSearchSource: String, CaseIterable, Sendable {
        case semanticIndex = "semantic"
        case vectorIndex = "vector"
        case symbolIndex = "symbol"
        case grepFallback = "grep"
    }

    struct HybridSearchRequest: Sendable {
        let query: String
        let queryTokens: [String]
        let targetDirectories: [String]
        let numResults: Int
        let minConfidence: Double
        let workspacePaths: [String]
        let searchPaths: [String]
        let showScoring: Bool
        let strictScope: Bool
    }

    struct HybridSourceHit: Sendable {
        let key: String
        let source: HybridSearchSource
        let rank: Int
        let sourceScore: Double
        let sourceConfidence: Double
        let filePath: String
        let lineStart: Int
        let lineEnd: Int
        let scope: String
        let snippet: String
    }

    struct HybridScoredResult: Sendable {
        let key: String
        let filePath: String
        let lineStart: Int
        let lineEnd: Int
        let scope: String
        let snippet: String
        let fusedScore: Double
        let confidence: Double
        let sourceBreakdown: [HybridSearchSource: Double]
    }

    struct HybridSearchDiagnostics: Sendable {
        let sourceHits: [HybridSearchSource: Int]
        let sourceUsedInTop: [HybridSearchSource: Int]
        let minConfidence: Double
        let droppedByConfidence: Int
        let dedupedCount: Int
        let grepFallbackSkippedReason: String?

        var summaryLine: String {
            let sourceStats = HybridSearchSource.allCases.map { source in
                let hits = sourceHits[source, default: 0]
                return "\(source.rawValue)=\(hits)"
            }.joined(separator: ", ")
            let skipped = grepFallbackSkippedReason.map { "; grep=\($0)" } ?? ""
            return "hybrid: \(sourceStats); dedup=\(dedupedCount); filtered=\(droppedByConfidence); min_conf=\(String(format: "%.2f", minConfidence))\(skipped)"
        }
    }
}
