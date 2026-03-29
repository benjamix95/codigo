import Foundation

extension ToolEnabledLLMProvider {
    func enforcedWorkspaceSearchMarker(
        marker: CoderIDEMarker,
        toolName: String
    ) -> (marker: CoderIDEMarker, toolName: String) {
        let normalizedTool = ProviderToolEventMapper.normalizeToolIdentifier(toolName)
        switch normalizedTool {
        case "grep", "search":
            guard shouldForceSemanticSearch(for: normalizedTool, payload: marker.payload) else {
                return (marker, normalizedTool)
            }
            var payload = marker.payload
            payload["tool"] = "semantic_search"
            payload["name"] = payload["name"].flatMap { $0.isEmpty ? nil : "semantic_search" } ?? payload["name"]
            payload["tool_name"] = payload["tool_name"].flatMap { $0.isEmpty ? nil : "semantic_search" } ?? payload["tool_name"]
            payload["function"] = payload["function"].flatMap { $0.isEmpty ? nil : "semantic_search" } ?? payload["function"]
            payload["function_name"] = payload["function_name"].flatMap { $0.isEmpty ? nil : "semantic_search" } ?? payload["function_name"]
            return (CoderIDEMarker(kind: marker.kind, payload: payload), "semantic_search")
        case "mcp_call":
            guard shouldForceSemanticSearchForMCPCall(payload: marker.payload) else {
                return (marker, normalizedTool)
            }
            var payload = marker.payload
            payload["tool"] = "coderide_semantic_search"
            payload["mcp_tool"] = "coderide_semantic_search"
            payload["tool_name"] = "coderide_semantic_search"
            return (CoderIDEMarker(kind: marker.kind, payload: payload), "mcp_call")
        default:
            return (marker, normalizedTool)
        }
    }

    private func shouldForceSemanticSearchForMCPCall(payload: [String: String]) -> Bool {
        let targetTool = ProviderToolEventMapper.normalizeToolIdentifier(
            payload["mcp_tool"] ?? payload["tool"] ?? payload["tool_name"] ?? ""
        )
        guard targetTool == "grep" || targetTool == "search" || targetTool == "codebase_search" else {
            return false
        }
        return shouldForceSemanticSearch(for: targetTool, payload: payload)
    }

    private func shouldForceSemanticSearch(for toolName: String, payload: [String: String]) -> Bool {
        let query = (payload["query"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return false }
        guard looksLikeNaturalLanguageSemanticQuery(query) else { return false }
        if queryLooksRegexLike(query) { return false }

        let grepSignals = [
            "pattern", "fileType", "glob", "context_lines", "case_sensitive",
            "multiline", "output_mode", "maxResults", "max_results",
        ]
        let hasExactSearchHints = grepSignals.contains {
            let value = payload[$0]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return !value.isEmpty
        }
        if hasExactSearchHints { return false }

        if toolName == "codebase_search" {
            let kind = (payload["kind"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if !kind.isEmpty { return false }
        }

        return true
    }
}
