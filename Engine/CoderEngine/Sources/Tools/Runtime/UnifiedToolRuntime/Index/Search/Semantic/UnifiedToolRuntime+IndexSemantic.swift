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
        let targetDirs = parseSemanticTargetDirectories(targetDirectoriesRaw)
        let rawLimit = call.args["limit"] ?? call.args["num_results"] ?? "25"
        let numResults = min(max(Int(rawLimit) ?? 25, 1), 50)
        let allWorkspacePaths = preferredWorkspacePaths(for: context).map(\.path)
        let scopeResolution = resolveSemanticSearchScopes(
            targetDirectories: targetDirs,
            workspacePaths: allWorkspacePaths
        )
        if !targetDirs.isEmpty && scopeResolution.searchPaths.isEmpty {
            let detail: String
            if scopeResolution.invalidTargets.isEmpty {
                detail = "No valid target directories inside workspace scope"
            } else {
                detail = "Invalid target directories: \(scopeResolution.invalidTargets.joined(separator: ", "))"
            }
            return failure(detail, errorCode: "validation", startDate: startDate)
        }

        let queryTokens = tokenizeSemanticQuery(query)
        guard !queryTokens.isEmpty else {
            return success([
                "title": "semantic_search",
                "query": query,
                "detail": "No results found",
                "output": "No matches found for: \(query)",
                "count": "0",
            ], startDate: startDate)
        }
        let parsedMinConfidence = Double(call.args["min_confidence"] ?? "0.45") ?? 0.45
        let finiteMinConfidence = parsedMinConfidence.isFinite ? parsedMinConfidence : 0.45
        let minConfidence = min(max(finiteMinConfidence, 0.0), 1.0)
        let showScoring = parseBooleanArgument(call.args["show_scoring"])
        let strictScope = parseBooleanArgument(call.args["strict_scope"])

        if let index = codebaseIndex {
            await ensureSemanticIndexReadyIfNeeded(index: index, context: context)
        }
        let request = HybridSearchRequest(
            query: query,
            queryTokens: queryTokens,
            targetDirectories: scopeResolution.targetDirectoryPrefixes,
            numResults: numResults,
            minConfidence: minConfidence,
            workspacePaths: allWorkspacePaths,
            searchPaths: scopeResolution.searchPaths,
            showScoring: showScoring,
            strictScope: strictScope
        )
        var searchIndex = codebaseIndex
        if let codebaseIndex {
            let preparation = await prepareIndexForSemanticSearch(
                index: codebaseIndex,
                context: context,
                request: request
            )
            if case .fallbackOnly = preparation {
                searchIndex = nil
            }
        }
        let (hits, grepSkipReason) = await collectHybridSearchHits(request: request, index: searchIndex)
        let (top, diagnostics) = fuseHybridSearchResults(hits: hits, request: request, grepFallbackSkippedReason: grepSkipReason)
        let telemetry = updateSemanticSourceTelemetry(with: diagnostics)
        guard !top.isEmpty else {
            return success([
                "title": "semantic_search",
                "query": query,
                "detail": "No results found",
                "output": "No matches found for: \(query)",
                "count": "0",
                "diagnostics": renderHybridDiagnostics(diagnostics) + "\ntelemetry: " + telemetry,
            ], startDate: startDate)
        }
        let output = renderHybridSearchOutput(top, showScoring: showScoring)
        let sourceKinds = diagnostics.sourceUsedInTop
            .filter { $0.value > 0 }
            .map { "\(detailLabel(for: $0.key))=\($0.value)" }
            .sorted()
            .joined(separator: ", ")
        let usedOnlyGrepFallback =
            !diagnostics.sourceUsedInTop.isEmpty
            && diagnostics.sourceUsedInTop.allSatisfy { source, count in
                source == .grepFallback && count > 0
            }
        let detailSuffix: String
        if usedOnlyGrepFallback {
            detailSuffix = sourceKinds.isEmpty ? "grep fallback" : "grep fallback (\(sourceKinds))"
        } else {
            detailSuffix = sourceKinds.isEmpty ? "hybrid fusion" : "hybrid fusion (\(sourceKinds))"
        }

        return success([
            "title": "semantic_search",
            "query": query,
            "detail": "\(top.count) results (\(detailSuffix))",
            "output": truncate(output, maxBytes: context.policy.maxBashOutputBytes),
            "count": "\(top.count)",
            "pathScope": targetDirs.isEmpty ? "." : targetDirs.joined(separator: ","),
            "diagnostics": renderHybridDiagnostics(diagnostics) + "\ntelemetry: " + telemetry,
        ], startDate: startDate)
    }

    private func displayName(for source: HybridSearchSource) -> String {
        switch source {
        case .semanticIndex:
            return "semantic_index"
        case .vectorIndex:
            return "vector_index"
        case .symbolIndex:
            return "symbol_index"
        case .grepFallback:
            return "grep_fallback"
        }
    }

    private func detailLabel(for source: HybridSearchSource) -> String {
        switch source {
        case .semanticIndex:
            return "semantic index"
        case .vectorIndex:
            return "vector index"
        case .symbolIndex:
            return "symbol index"
        case .grepFallback:
            return "text fallback"
        }
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
        }

        let refreshedStatus = await index.status()
        guard shouldPerformSemanticFullReindex(statusInfo: refreshedStatus, requestedWorkspacePaths: requestedPaths)
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

    func runSemanticTextSearch(
        pattern: String,
        searchPath: String,
        workspace: String,
        timeoutMs: Int = 10_000
    ) async -> String {
        let command = """
        if command -v rg >/dev/null 2>&1; then
          rg --no-heading -n --max-count=10 -i '\(shellEscaped(pattern))' '\(shellEscaped(searchPath))' --glob '!.build' --glob '!node_modules' --glob '!.git' 2>/dev/null
        else
          grep -RIn -m 10 -i --exclude-dir=.build --exclude-dir=node_modules --exclude-dir=.git -- '\(shellEscaped(pattern))' '\(shellEscaped(searchPath))' 2>/dev/null
        fi
        """
        let (output, _, _) = await shellExec(
            args: ["/bin/sh", "-lc", command],
            cwd: workspace,
            timeout: timeoutMs
        )
        return output
    }

    struct SemanticScopeResolution {
        let targetDirectoryPrefixes: [String]
        let searchPaths: [String]
        let invalidTargets: [String]
    }
}
