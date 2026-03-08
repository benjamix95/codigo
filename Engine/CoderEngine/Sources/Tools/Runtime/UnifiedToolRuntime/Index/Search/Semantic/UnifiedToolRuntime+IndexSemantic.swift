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
        let (hits, grepSkipReason) = await collectHybridSearchHits(request: request, index: codebaseIndex)
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

    private struct SemanticScopeResolution {
        let targetDirectoryPrefixes: [String]
        let searchPaths: [String]
        let invalidTargets: [String]
    }

    private func resolveSemanticSearchScopes(
        targetDirectories: [String],
        workspacePaths: [String]
    ) -> SemanticScopeResolution {
        let normalizedRoots = normalizeWorkspacePaths(workspacePaths)
        guard !targetDirectories.isEmpty else {
            return SemanticScopeResolution(
                targetDirectoryPrefixes: [],
                searchPaths: normalizedRoots,
                invalidTargets: []
            )
        }

        var prefixes: [String] = []
        var searchPaths: [String] = []
        var invalidTargets: [String] = []
        var seenPrefixes = Set<String>()
        var seenPaths = Set<String>()

        for rawTarget in targetDirectories {
            let trimmed = rawTarget.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }

            let candidates: [String]
            if (trimmed as NSString).isAbsolutePath {
                candidates = [URL(fileURLWithPath: trimmed).standardizedFileURL.path]
            } else {
                candidates = normalizedRoots.map { root in
                    URL(fileURLWithPath: root).appendingPathComponent(trimmed).standardizedFileURL.path
                }
            }

            var insertedAny = false
            for candidate in candidates {
                guard let root = workspaceRoot(containing: candidate, workspacePaths: normalizedRoots) else {
                    continue
                }
                if seenPaths.insert(candidate).inserted {
                    searchPaths.append(candidate)
                }
                let prefix = relativeScopePrefix(searchPath: candidate, workspaceRoot: root)
                if seenPrefixes.insert(prefix).inserted {
                    prefixes.append(prefix)
                }
                insertedAny = true
            }

            if !insertedAny {
                invalidTargets.append(trimmed)
            }
        }

        return SemanticScopeResolution(
            targetDirectoryPrefixes: prefixes,
            searchPaths: searchPaths,
            invalidTargets: invalidTargets
        )
    }

    private func workspaceRoot(containing path: String, workspacePaths: [String]) -> String? {
        let normalized = URL(fileURLWithPath: path).standardizedFileURL.path
        let sortedRoots = workspacePaths.sorted { $0.count > $1.count }
        for root in sortedRoots {
            if normalized == root { return root }
            let prefix = root.hasSuffix("/") ? root : root + "/"
            if normalized.hasPrefix(prefix) { return root }
        }
        return nil
    }

    private func relativeScopePrefix(searchPath: String, workspaceRoot: String) -> String {
        let rootName = (workspaceRoot as NSString).lastPathComponent
        let normalizedSearch = URL(fileURLWithPath: searchPath).standardizedFileURL.path
        let rootPrefix = workspaceRoot.hasSuffix("/") ? workspaceRoot : workspaceRoot + "/"
        guard normalizedSearch != workspaceRoot, normalizedSearch.hasPrefix(rootPrefix) else {
            return rootName
        }
        let tail = String(normalizedSearch.dropFirst(rootPrefix.count))
        return tail.isEmpty ? rootName : "\(rootName)/\(tail)"
    }

    private func tokenizeSemanticQuery(_ query: String) -> [String] {
        let primary = query.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count >= 2 }
        if !primary.isEmpty { return primary }

        let fallback = query
            .lowercased()
            .components(separatedBy: .whitespacesAndNewlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return fallback
    }

    private func parseSemanticTargetDirectories(_ raw: String) -> [String] {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        if trimmed.hasPrefix("["),
           let data = trimmed.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data, options: []),
           let array = json as? [Any]
        {
            return array
                .compactMap { value -> String? in
                    if let string = value as? String { return string }
                    if let number = value as? NSNumber { return number.stringValue }
                    return nil
                }
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        }

        return trimmed
            .components(separatedBy: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private func parseBooleanArgument(_ raw: String?) -> Bool {
        guard let raw else { return false }
        switch raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "1", "true", "yes", "on":
            return true
        default:
            return false
        }
    }

    private func updateSemanticSourceTelemetry(with diagnostics: HybridSearchDiagnostics) -> String {
        for (source, count) in diagnostics.sourceUsedInTop where count > 0 {
            semanticSourceUsageCounters[source, default: 0] += count
        }
        let total = semanticSourceUsageCounters.values.reduce(0, +)
        guard total > 0 else { return "n/a" }
        return HybridSearchSource.allCases
            .map { source -> String in
                let count = semanticSourceUsageCounters[source, default: 0]
                let ratio = (Double(count) / Double(total)) * 100.0
                return "\(source.rawValue)=\(String(format: "%.1f", ratio))%"
            }
            .joined(separator: ", ")
    }
}
