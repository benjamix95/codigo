import Foundation

extension UnifiedToolRuntime {
    func executeSearchHealthCheck(
        call: ToolCall,
        context: ToolExecutionContext,
        startDate: Date
    ) async -> ToolResult {
        let workspaces = preferredWorkspacePaths(for: context).map(\.path)
        let rgAvailable = await isCommandAvailable("rg")
        let vectorEnabled = IndexFeatureFlags.vectorSearchEnabled
        let trigramEnabled = IndexFeatureFlags.trigramIndexEnabled
        let vectorDBAvailable = (try? PostgresPersistenceStore.shared.isVectorSearchAvailable()) ?? false
        let vectorStats = (try? PostgresPersistenceStore.shared.vectorSearchTableStats())
            ?? VectorSearchTableStats(rowCount: 0, fileCount: 0)
        let postgresConfiguration = ManagedPostgresConfiguration.default

        var payload: [String: String] = [
            "title": "search_health_check",
            "workspace_count": "\(workspaces.count)",
            "rg_available": rgAvailable ? "true" : "false",
            "grep_cache_entries": "\(grepFallbackCacheOrder.count)",
            "vector_enabled": vectorEnabled ? "true" : "false",
            "vector_db_available": vectorDBAvailable ? "true" : "false",
            "embedding_row_count": "\(vectorStats.rowCount)",
            "embedding_file_count": "\(vectorStats.fileCount)",
            "trigram_enabled": trigramEnabled ? "true" : "false",
            "postgres_port": "\(postgresConfiguration.port)",
            "postgres_root": postgresConfiguration.rootDirectory.path,
        ]

        if let codebaseIndex {
            let status = await codebaseIndex.status()
            let semanticStatus = await codebaseIndex.semanticIndex.status()
            payload["index_status"] = status.status.rawValue
            payload["indexed_files"] = "\(status.totalSourceFiles)"
            payload["semantic_chunks"] = "\(semanticStatus.totalChunks)"
            payload["semantic_tokens"] = "\(semanticStatus.totalTokens)"
            if let embeddingService = await codebaseIndex.embeddingServiceIfAvailable {
                let embeddingAvailable = await embeddingService.isAvailable()
                payload["embedding_service_available"] = embeddingAvailable ? "true" : "false"
                payload["embedding_backend"] = await embeddingService.currentBackend()?.rawValue
                    ?? (embeddingAvailable ? "ready" : "unavailable")
            } else {
                payload["embedding_service_available"] = "false"
                payload["embedding_backend"] = vectorEnabled ? "unavailable" : "disabled"
            }
        } else {
            payload["index_status"] = "unavailable"
            payload["embedding_service_available"] = "false"
            payload["embedding_backend"] = vectorEnabled ? "unknown" : "disabled"
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
        - vector_enabled: \(vectorEnabled ? "yes" : "no")
        - vector_db_available: \(vectorDBAvailable ? "yes" : "no")
        - embedding_row_count: \(vectorStats.rowCount)
        - embedding_file_count: \(vectorStats.fileCount)
        - trigram_enabled: \(trigramEnabled ? "yes" : "no")
        - embedding_backend: \(payload["embedding_backend"] ?? "unknown")
        - postgres_port: \(payload["postgres_port"] ?? "unknown")
        - postgres_root: \(payload["postgres_root"] ?? "unknown")
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
