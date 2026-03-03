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

        // Primary: BM25 SemanticIndex (AST-aware chunks + inverted index)
        if let index = codebaseIndex {
            await ensureSemanticIndexReadyIfNeeded(index: index, context: context)
            let results = await index.semanticIndex.search(
                query: query,
                targetDirectories: targetDirs,
                numResults: numResults
            )

            if !results.isEmpty {
                var output = ""
                for (i, result) in results.enumerated() {
                    let chunk = result.chunk
                    let lineRange = chunk.startLine == chunk.endLine
                        ? ":\(chunk.startLine)"
                        : ":\(chunk.startLine)-\(chunk.endLine)"
                    let scopeInfo = chunk.scope.isEmpty ? "" : " [\(chunk.scope)]"
                    output += "\(i + 1). \(chunk.filePath)\(lineRange)\(scopeInfo) (score: \(String(format: "%.2f", result.score)))\n"

                    // Include a compact code preview (first 3 meaningful lines)
                    let previewLines = chunk.content
                        .components(separatedBy: "\n")
                        .map { $0.trimmingCharacters(in: .whitespaces) }
                        .filter { !$0.isEmpty }
                        .prefix(3)
                    for line in previewLines {
                        let trimmed = line.count > 120 ? String(line.prefix(120)) + "…" : line
                        output += "   \(trimmed)\n"
                    }
                }

                return success([
                    "title": "semantic_search",
                    "query": query,
                    "detail": "\(results.count) results (BM25 index)",
                    "output": truncate(output, maxBytes: context.policy.maxBashOutputBytes),
                    "count": "\(results.count)",
                    "pathScope": targetDirs.isEmpty ? "." : targetDirs.joined(separator: ",")
                ], startDate: startDate)
            }
        }

        // Fallback: grep-based search when SemanticIndex is empty or unavailable
        let queryTokens = query.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count >= 2 }

        guard !queryTokens.isEmpty else {
            return success([
                "title": "semantic_search",
                "query": query,
                "detail": "No results found",
                "output": "No matches found for: \(query)",
                "count": "0"
            ], startDate: startDate)
        }

        // Generate grep patterns from query tokens (camelCase, snake_case, raw)
        var patterns: [String] = []
        if queryTokens.count >= 2 {
            patterns.append(queryTokens.joined(separator: ".*"))
            let camel = queryTokens[0] + queryTokens.dropFirst().map { $0.capitalized }.joined()
            patterns.append(camel)
            let pascal = queryTokens.map { $0.capitalized }.joined()
            patterns.append(pascal)
            patterns.append(queryTokens.joined(separator: "_"))
        }
        for token in queryTokens where token.count >= 3 {
            patterns.append(token)
        }

        struct FallbackResult: Comparable {
            let file: String; let line: Int; let snippet: String; let score: Double
            static func < (lhs: FallbackResult, rhs: FallbackResult) -> Bool { lhs.score > rhs.score }
        }

        func relativePathForDisplay(absolutePath: String) -> String {
            let normalized = (absolutePath as NSString).standardizingPath
            for root in allWorkspacePaths {
                let rootNorm = (root as NSString).standardizingPath
                if normalized == rootNorm { return (root as NSString).lastPathComponent }
                let prefix = rootNorm.hasSuffix("/") ? rootNorm : rootNorm + "/"
                if normalized.hasPrefix(prefix) {
                    let tail = String(normalized.dropFirst(prefix.count))
                    return ((root as NSString).lastPathComponent) + "/" + tail
                }
            }
            return normalized
        }

        var grepResults: [FallbackResult] = []
        for pattern in patterns.prefix(5) {
            for searchPath in searchPaths {
                let output = await runSemanticTextSearch(
                    pattern: pattern,
                    searchPath: searchPath,
                    workspace: searchPath
                )
                guard !output.isEmpty else { continue }

                for line in output.components(separatedBy: "\n") where !line.isEmpty {
                    let parts = line.split(separator: ":", maxSplits: 2).map(String.init)
                    guard parts.count >= 3 else { continue }
                    let filePath = parts[0]
                    let lineNum = Int(parts[1]) ?? 0
                    let content = parts[2].trimmingCharacters(in: .whitespaces)
                    let contentLower = content.lowercased()
                    var score = 0.5
                    for token in queryTokens where contentLower.contains(token) { score += 0.8 }
                    if contentLower.contains("func ") || contentLower.contains("class ") ||
                       contentLower.contains("struct ") || contentLower.contains("protocol ") ||
                       contentLower.contains("enum ") || contentLower.contains("def ") ||
                       contentLower.contains("function ") {
                        score += 1.5
                    }
                    let relPath = relativePathForDisplay(absolutePath: filePath)
                    grepResults.append(FallbackResult(file: relPath, line: lineNum, snippet: content, score: score))
                }
            }
        }

        var seen = Set<String>()
        let deduped = grepResults.sorted().filter { r in
            let key = "\(r.file):\(r.line)"
            guard !seen.contains(key) else { return false }
            seen.insert(key)
            return true
        }
        let top = Array(deduped.prefix(numResults))

        if top.isEmpty {
            return success([
                "title": "semantic_search",
                "query": query,
                "detail": "No results found",
                "output": "No matches found for: \(query)",
                "count": "0"
            ], startDate: startDate)
        }

        var output = ""
        for (i, r) in top.enumerated() {
            let lineInfo = r.line > 0 ? ":\(r.line)" : ""
            output += "\(i + 1). \(r.file)\(lineInfo) (score: \(String(format: "%.1f", r.score)))\n"
            if !r.snippet.isEmpty {
                let trimmed = r.snippet.count > 120 ? String(r.snippet.prefix(120)) + "…" : r.snippet
                output += "   \(trimmed)\n"
            }
        }

        return success([
            "title": "semantic_search",
            "query": query,
            "detail": "\(top.count) results (grep fallback)",
            "output": truncate(output, maxBytes: context.policy.maxBashOutputBytes),
            "count": "\(top.count)",
            "pathScope": targetDirs.isEmpty ? "." : targetDirs.joined(separator: ",")
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
