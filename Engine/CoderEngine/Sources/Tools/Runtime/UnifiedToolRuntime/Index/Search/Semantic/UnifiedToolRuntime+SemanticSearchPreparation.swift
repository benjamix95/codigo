import Foundation

extension UnifiedToolRuntime {
    enum SemanticSearchIndexPreparation {
        case useIndex
        case fallbackOnly
    }

    func prepareIndexForSemanticSearch(
        index: CodebaseIndex,
        context: ToolExecutionContext,
        request: HybridSearchRequest
    ) async -> SemanticSearchIndexPreparation {
        let requestedPaths = preferredWorkspacePaths(for: context)
        guard !requestedPaths.isEmpty else { return .useIndex }

        let status = await index.status()
        if status.status == .indexing {
            Self.logger.debug("prepareIndexForSemanticSearch: waiting for in-progress indexing")
            let _ = await index.waitUntilReady(timeoutMs: 30_000)
        }

        let refreshedStatus = await index.status()
        guard shouldPerformSemanticFullReindex(
            statusInfo: refreshedStatus,
            requestedWorkspacePaths: requestedPaths
        ) else {
            return .useIndex
        }

        guard shouldFallbackWhileWarmingSemanticIndex(request: request) else {
            let _ = await index.indexWorkspace(paths: requestedPaths, excludedPaths: excludedPaths)
            return .useIndex
        }

        scheduleSemanticIndexWarmupIfNeeded(index: index, requestedPaths: requestedPaths)
        return .fallbackOnly
    }

    func shouldFallbackWhileWarmingSemanticIndex(request: HybridSearchRequest) -> Bool {
        guard !request.queryTokens.isEmpty else { return false }
        guard !request.searchPaths.isEmpty else { return false }
        return !(request.strictScope && request.targetDirectories.isEmpty)
    }

    func scheduleSemanticIndexWarmupIfNeeded(
        index: CodebaseIndex,
        requestedPaths: [URL]
    ) {
        let requestedPaths = requestedPaths
        let excludedPaths = self.excludedPaths
        Task {
            let status = await index.status()
            guard status.status != .indexing else { return }
            guard shouldPerformSemanticFullReindex(
                statusInfo: status,
                requestedWorkspacePaths: requestedPaths
            ) else {
                return
            }
            let _ = await index.indexWorkspace(paths: requestedPaths, excludedPaths: excludedPaths)
        }
    }

    func resolveSemanticSearchScopes(
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

    func workspaceRoot(containing path: String, workspacePaths: [String]) -> String? {
        let normalized = URL(fileURLWithPath: path).standardizedFileURL.path
        let sortedRoots = workspacePaths.sorted { $0.count > $1.count }
        for root in sortedRoots {
            if normalized == root { return root }
            let prefix = root.hasSuffix("/") ? root : root + "/"
            if normalized.hasPrefix(prefix) { return root }
        }
        return nil
    }

    func relativeScopePrefix(searchPath: String, workspaceRoot: String) -> String {
        let rootName = (workspaceRoot as NSString).lastPathComponent
        let normalizedSearch = URL(fileURLWithPath: searchPath).standardizedFileURL.path
        let rootPrefix = workspaceRoot.hasSuffix("/") ? workspaceRoot : workspaceRoot + "/"
        guard normalizedSearch != workspaceRoot, normalizedSearch.hasPrefix(rootPrefix) else {
            return rootName
        }
        let tail = String(normalizedSearch.dropFirst(rootPrefix.count))
        return tail.isEmpty ? rootName : "\(rootName)/\(tail)"
    }

    func tokenizeSemanticQuery(_ query: String) -> [String] {
        let primary = query.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count >= 2 }
        if !primary.isEmpty { return primary }

        return query
            .lowercased()
            .components(separatedBy: .whitespacesAndNewlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    func parseSemanticTargetDirectories(_ raw: String) -> [String] {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        if trimmed.hasPrefix("["),
           let data = trimmed.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data, options: []),
           let array = json as? [Any] {
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

    func parseBooleanArgument(_ raw: String?) -> Bool {
        guard let raw else { return false }
        switch raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "1", "true", "yes", "on":
            return true
        default:
            return false
        }
    }

    func updateSemanticSourceTelemetry(with diagnostics: HybridSearchDiagnostics) -> String {
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
