import Foundation

extension UnifiedToolRuntime {
    func executeSemanticSearch(call: ToolCall, context: ToolExecutionContext, startDate: Date) async -> ToolResult {
        let query = (call.args["query"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            return failure("query is required", errorCode: "validation", startDate: startDate)
        }
        let targetDirectoriesRaw =
            call.args["target_directories"]
            ?? call.args["targetDirectories"]
            ?? call.args["pathScope"]
            ?? call.args["path"]
            ?? ""
        let targetDirs = targetDirectoriesRaw
            .components(separatedBy: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let rawLimit = call.args["limit"] ?? call.args["num_results"] ?? "25"
        let numResults = min(max(Int(rawLimit) ?? 25, 1), 50)
        let allWorkspacePaths = context.workspaceContext.workspacePaths.map(\.path)
        let searchPaths: [String] = {
            if targetDirs.isEmpty {
                return allWorkspacePaths
            }
            let paths = targetDirs.flatMap { dir -> [String] in
                if (dir as NSString).isAbsolutePath {
                    return [dir]
                }
                return allWorkspacePaths.map { root in
                    (root as NSString).appendingPathComponent(dir)
                }
            }
            var deduped: [String] = []
            var seen = Set<String>()
            for path in paths where seen.insert(path).inserted {
                deduped.append(path)
            }
            return deduped
        }()
        let queryTokens = query.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count >= 2 }
        guard !queryTokens.isEmpty else {
            return success([
                "title": "semantic_search",
                "query": query,
                "detail": "No results found",
                "output": "No matches found for: \(query)",
                "count": "0",
            ], startDate: startDate)
        }
        let minConfidence = min(max(Double(call.args["min_confidence"] ?? "0.45") ?? 0.45, 0.0), 1.0)

        if let index = codebaseIndex {
            await ensureSemanticIndexReadyIfNeeded(index: index, context: context)
        }
        let request = HybridSearchRequest(
            query: query,
            queryTokens: queryTokens,
            targetDirectories: targetDirs,
            numResults: numResults,
            minConfidence: minConfidence,
            workspacePaths: allWorkspacePaths,
            searchPaths: searchPaths
        )
        let hits = await collectHybridSearchHits(request: request, index: codebaseIndex)
        let (top, diagnostics) = fuseHybridSearchResults(hits: hits, request: request)
        guard !top.isEmpty else {
            return success([
                "title": "semantic_search",
                "query": query,
                "detail": "No results found",
                "output": "No matches found for: \(query)",
                "count": "0",
                "diagnostics": renderHybridDiagnostics(diagnostics),
            ], startDate: startDate)
        }
        let output = renderHybridSearchOutput(top)
        let sourceKinds = diagnostics.sourceUsedInTop
            .filter { $0.value > 0 }
            .map { "\($0.key.rawValue)=\($0.value)" }
            .sorted()
            .joined(separator: ", ")
        let detailSuffix = sourceKinds.isEmpty ? "hybrid fusion" : "hybrid fusion (\(sourceKinds))"

        return success([
            "title": "semantic_search",
            "query": query,
            "detail": "\(top.count) results (\(detailSuffix))",
            "output": truncate(output, maxBytes: context.policy.maxBashOutputBytes),
            "count": "\(top.count)",
            "pathScope": targetDirs.isEmpty ? "." : targetDirs.joined(separator: ","),
            "diagnostics": renderHybridDiagnostics(diagnostics),
        ], startDate: startDate)
    }

    func ensureSemanticIndexReadyIfNeeded(
        index: CodebaseIndex,
        context: ToolExecutionContext
    ) async {
        let requestedPaths = preferredWorkspacePaths(for: context)
        guard !requestedPaths.isEmpty else { return }

        let status = await index.status()

        // Wait for in-progress indexing to finish before proceeding
        if status.status == .indexing {
            Self.logger.debug("ensureSemanticIndexReady: waiting for in-progress indexing to finish")
            let _ = await index.waitUntilReady(timeoutMs: 30_000)
            return
        }

        guard shouldPerformSemanticFullReindex(statusInfo: status, requestedWorkspacePaths: requestedPaths)
        else { return }

        let _ = await index.indexWorkspace(paths: requestedPaths, excludedPaths: excludedPaths)
    }

    func preferredWorkspacePaths(for context: ToolExecutionContext) -> [URL] {
        if !context.workspaceContext.workspacePaths.isEmpty {
            return context.workspaceContext.workspacePaths
        }
        if !workspacePaths.isEmpty {
            return workspacePaths
        }
        return [context.workspaceContext.workspacePath]
    }

    func shouldPerformSemanticFullReindex(
        statusInfo: IndexStatusInfo,
        requestedWorkspacePaths: [URL]
    ) -> Bool {
        if statusInfo.status == .idle || statusInfo.status == .error {
            return true
        }
        let requested = normalizeWorkspacePaths(requestedWorkspacePaths)
        guard !requested.isEmpty else { return false }
        let indexed = normalizeWorkspacePaths(statusInfo.workspacePaths)
        return requested != indexed
    }

    func normalizeWorkspacePaths(_ paths: [URL]) -> [String] {
        let values = paths.map { $0.standardizedFileURL.path }
        return normalizeWorkspacePaths(values)
    }

    func runSemanticTextSearch(pattern: String, searchPath: String, workspace: String) async -> String {
        let command = """
        if command -v rg >/dev/null 2>&1; then
          rg --no-heading -n --max-count=10 -i '\(shellEscaped(pattern))' '\(shellEscaped(searchPath))' --glob '!.build' --glob '!node_modules' --glob '!.git' 2>/dev/null
        else
          grep -RIn -m 10 -i -- '\(shellEscaped(pattern))' '\(shellEscaped(searchPath))' 2>/dev/null
        fi
        """
        let (output, _, _) = await shellExec(
            args: ["/bin/sh", "-lc", command],
            cwd: workspace,
            timeout: 10_000
        )
        return output
    }
}
