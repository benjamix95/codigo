import Foundation

extension UnifiedToolRuntime {
    func renderHybridSearchOutput(_ results: [HybridScoredResult], showScoring: Bool) -> String {
        var output = ""
        for (idx, result) in results.enumerated() {
            let lineRange: String = {
                if result.lineStart <= 0 { return "" }
                if result.lineStart == result.lineEnd { return ":\(result.lineStart)" }
                return ":\(result.lineStart)-\(result.lineEnd)"
            }()
            let scopeInfo = result.scope.isEmpty ? "" : " [\(result.scope)]"
            output += "\(idx + 1). \(result.filePath)\(lineRange)\(scopeInfo) (score: \(String(format: "%.3f", result.fusedScore)), conf: \(String(format: "%.2f", result.confidence)))\n"
            if !result.snippet.isEmpty {
                let trimmed = result.snippet.count > 120 ? String(result.snippet.prefix(120)) + "…" : result.snippet
                output += "   \(trimmed)\n"
            }
            if showScoring {
                let breakdown = formatScoringBreakdown(result.sourceBreakdown)
                output += "   sources: \(breakdown)\n"
            }
        }
        return output
    }

    func renderHybridDiagnostics(_ diagnostics: HybridSearchDiagnostics) -> String {
        var lines: [String] = [diagnostics.summaryLine]
        let usage = HybridSearchSource.allCases
            .map { source in
                let count = diagnostics.sourceUsedInTop[source, default: 0]
                return "\(source.rawValue)=\(count)"
            }
            .joined(separator: ", ")
        lines.append("top_sources: \(usage)")
        return lines.joined(separator: "\n")
    }

    private func formatScoringBreakdown(_ breakdown: [HybridSearchSource: Double]) -> String {
        let segments = breakdown
            .sorted { lhs, rhs in
                if lhs.value != rhs.value { return lhs.value > rhs.value }
                return lhs.key.rawValue < rhs.key.rawValue
            }
            .map { source, value in
                "\(source.rawValue)=\(String(format: "%.3f", value))"
            }
        return segments.isEmpty ? "n/a" : segments.joined(separator: ", ")
    }
}
