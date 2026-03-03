import Foundation

extension UnifiedToolRuntime {
    func executeSearchHealthCheck(
        call: ToolCall,
        context: ToolExecutionContext,
        startDate: Date
    ) async -> ToolResult {
        let workspaces = preferredWorkspacePaths(for: context).map(\.path)
        let rgAvailable = await isCommandAvailable("rg")

        var payload: [String: String] = [
            "title": "search_health_check",
            "workspace_count": "\(workspaces.count)",
            "rg_available": rgAvailable ? "true" : "false",
            "grep_cache_entries": "\(grepFallbackCacheOrder.count)",
        ]

        if let codebaseIndex {
            let status = await codebaseIndex.status()
            let semanticStatus = await codebaseIndex.semanticIndex.status()
            payload["index_status"] = status.status.rawValue
            payload["indexed_files"] = "\(status.totalSourceFiles)"
            payload["semantic_chunks"] = "\(semanticStatus.totalChunks)"
            payload["semantic_tokens"] = "\(semanticStatus.totalTokens)"
        } else {
            payload["index_status"] = "unavailable"
        }

        let totalSourceUsage = semanticSourceUsageCounters.values.reduce(0, +)
        if totalSourceUsage > 0 {
            payload["source_usage_ratio"] = HybridSearchSource.allCases
                .map { source -> String in
                    let count = semanticSourceUsageCounters[source, default: 0]
                    let ratio = (Double(count) / Double(totalSourceUsage)) * 100.0
                    return "\(source.rawValue)=\(String(format: "%.1f", ratio))%"
                }
                .joined(separator: ", ")
        } else {
            payload["source_usage_ratio"] = "n/a"
        }

        payload["detail"] = "search pipelines healthy"
        payload["output"] = """
        search_health_check
        - workspaces: \(workspaces.count)
        - index_status: \(payload["index_status"] ?? "unknown")
        - rg_available: \(rgAvailable ? "yes" : "no")
        - grep_cache_entries: \(grepFallbackCacheOrder.count)
        - source_usage_ratio: \(payload["source_usage_ratio"] ?? "n/a")
        """
        return success(payload, startDate: startDate)
    }

    private func isCommandAvailable(_ command: String) async -> Bool {
        let script = "command -v \(shellEscaped(command)) >/dev/null 2>&1 && echo ok || echo missing"
        let workspace = workspacePaths.first?.path ?? FileManager.default.currentDirectoryPath
        let (output, _, _) = await shellExec(
            args: ["/bin/sh", "-lc", script],
            cwd: workspace,
            timeout: 1_500
        )
        return output.trimmingCharacters(in: .whitespacesAndNewlines) == "ok"
    }
}
