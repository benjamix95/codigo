import Foundation

extension ToolEnabledLLMProvider {
    func inferredQueryToolName(from payload: [String: String]) -> String {
        let query = (payload["query"] ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return "" }

        let scope = inferredQueryScope(from: payload)
        if hasNonEmptyValue(in: payload, keys: Self.semanticQueryKeys) {
            return "semantic_search"
        }
        if hasNonEmptyValue(in: payload, keys: Self.grepQueryKeys) || queryLooksRegexLike(query) {
            return "grep"
        }
        if scope.isEmpty, hasNonEmptyValue(in: payload, keys: Self.webQueryKeys) {
            return "web_search"
        }
        if scope.isEmpty {
            return "semantic_search"
        }
        return looksLikeNaturalLanguageSemanticQuery(query) ? "semantic_search" : "grep"
    }

    private func inferredQueryScope(from payload: [String: String]) -> String {
        [
            payload["pathScope"],
            payload["path_scope"],
            payload["target_directories"],
            payload["targetDirectories"],
            payload["path"],
        ]
        .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
        .first(where: { !$0.isEmpty }) ?? ""
    }

    private func hasNonEmptyValue(in payload: [String: String], keys: Set<String>) -> Bool {
        keys.contains { key in
            let value = payload[key]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return !value.isEmpty
        }
    }

    private func looksLikeNaturalLanguageSemanticQuery(_ query: String) -> Bool {
        let lower = query.lowercased()
        let tokens = lower.split(whereSeparator: \.isWhitespace)
        if tokens.count >= 3 { return true }
        if lower.contains("?") { return true }
        let intentSignals = [
            "where", "which", "how", "why", "what", "flow", "logic", "handle",
            "handled", "manages", "manage", "responsible", "used", "called",
        ]
        return intentSignals.contains { lower.contains($0) }
    }

    private func queryLooksRegexLike(_ query: String) -> Bool {
        let regexSignals = CharacterSet(charactersIn: "*+?|[](){}^$")
        return query.rangeOfCharacter(from: regexSignals) != nil
    }

    private static let grepQueryKeys: Set<String> = [
        "fileType", "glob", "context_lines", "case_sensitive", "multiline",
        "output_mode", "maxResults", "max_results",
    ]

    private static let semanticQueryKeys: Set<String> = [
        "target_directories", "targetDirectories", "num_results", "limit",
        "min_confidence", "show_scoring", "strict_scope",
    ]

    private static let webQueryKeys: Set<String> = [
        "domains", "domain", "explanation", "timeout",
    ]
}
