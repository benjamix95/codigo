import Foundation

extension UnifiedToolRuntime {
    func executeGrep(call: ToolCall, context: ToolExecutionContext, startDate: Date) async -> ToolResult {
        let query = (call.args["query"] ?? call.args["pattern"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let rawScope = (call.args["pathScope"] ?? call.args["path"] ?? ".")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let scopeParts = rawScope
            .components(separatedBy: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let allWorkspacePaths = context.workspaceContext.workspacePaths.map(\.path)
        let preferredRoot = context.workspaceContext.activeRootPath
        let primaryWorkspace = context.workspaceContext.workspacePath.path
        let scopes: [String] = {
            if scopeParts.isEmpty || (scopeParts.count == 1 && scopeParts[0] == ".") {
                return allWorkspacePaths.isEmpty ? ["."] : allWorkspacePaths
            }
            var out: [String] = []
            var seen = Set<String>()
            for item in scopeParts where seen.insert(item).inserted {
                if let resolvedPath = resolvePath(
                    item,
                    workspacePaths: allWorkspacePaths,
                    preferredRoot: preferredRoot,
                    sandboxMode: context.policy.sandboxMode
                ) {
                    out.append(resolvedPath)
                }
            }
            return out
        }()
        let fileType = call.args["fileType"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let globPattern = call.args["glob"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let rawMaxResults = call.args["maxResults"] ?? call.args["max_results"] ?? ""
        let maxMatchesPerScope = min(max(Int(rawMaxResults) ?? 200, 1), 2000)
        let contextLines = Int(call.args["context_lines"] ?? "") ?? 2
        let caseSensitive = (call.args["case_sensitive"] ?? "false").lowercased() == "true"
        let multiline = (call.args["multiline"] ?? "false").lowercased() == "true"
        let outputModeRaw = (call.args["output_mode"] ?? "content").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let outputMode: String = {
            switch outputModeRaw {
            case "files_only", "files", "paths":
                return "files_only"
            case "count":
                return "count"
            default:
                return "content"
            }
        }()
        let shouldUseContentMode = outputMode == "content"

        // Guard against empty queries that would match every line
        guard !query.isEmpty else {
            return ToolResult(ok: false, payload: [
                "title": "Grep",
                "detail": "query is required — provide a non-empty search pattern",
            ], durationMs: 0)
        }

        if scopes.isEmpty {
            return failure(
                "Path is not allowed by sandbox policy",
                errorCode: "sandbox_violation",
                startDate: startDate,
                payload: [
                    "title": "Grep \(query)",
                    "query": query,
                    "pathScope": rawScope,
                ]
            )
        }

        // If query looks like a symbol name (no regex chars) and index is available, try index first.
        // Use a short timeout (200ms) to avoid blocking grep when the index is still building.
        if shouldUseContentMode, let indexTools, let codebaseIndex, !query.isEmpty, !containsRegexChars(query) {
            let indexReady = await codebaseIndex.waitUntilReady(timeoutMs: 200)
            if indexReady {
                let indexEvents = await indexTools.execute(
                    toolName: "codebase_search",
                    args: ["query": query, "kind": "all"],
                    callId: call.id,
                    workspacePaths: preferredWorkspacePaths(for: context),
                    excludedPaths: excludedPaths
                )
                let indexResult = toolResultFromIndexEvents(indexEvents, startDate: startDate)
                if indexResult.ok,
                   let output = indexResult.payload["output"],
                    !output.isEmpty,
                    !output.contains("No symbols found") {
                    var payload = indexResult.payload
                    payload["title"] = "Grep \(query) (index + rg)"
                    payload["pathScope"] = (rawScope.isEmpty || rawScope == ".") ? scopes.joined(separator: ",") : rawScope
                    return ToolResult(ok: true, payload: payload, durationMs: indexResult.durationMs)
                }
            } else {
                Self.logger.debug("executeGrep: index not ready within 200ms, skipping to ripgrep for '\(query, privacy: .public)'")
            }
        }

        let maxContext = min(max(contextLines, 0), 10)
        var searchOutput = ""
        var searchError = ""
        var usedFallback = false

        // Trigram pre-filter: if the trigram index is available, use it
        // to narrow down candidate files before running ripgrep.
        if let codebaseIndex, ProcessInfo.processInfo.environment["SOLOCODE_ENABLE_TRIGRAM_INDEX"] == "1" {
            let trigramResult = await codebaseIndex.trigramSearch(
                pattern: query,
                maxResults: maxMatchesPerScope,
                caseSensitive: caseSensitive
            )
            if let result = trigramResult, !result.matches.isEmpty {
                let formatted = formatTrigramAsGrepOutput(
                    result: result,
                    outputMode: outputMode,
                    query: query,
                    maxContext: maxContext
                )
                let elapsedMs = Int(Date().timeIntervalSince(startDate) * 1000)
                let count = result.matches.count
                return ToolResult(ok: true, payload: [
                    "title": "Grep \(query) (trigram: \(count) hits, \(result.elapsedUs/1000)ms)",
                    "output": formatted,
                    "query": query,
                    "pathScope": rawScope.isEmpty ? "." : rawScope,
                    "matchCount": "\(count)",
                ], durationMs: elapsedMs)
            }
        }

        // Primary: ripgrep — when multiple scopes (roots), search each; cwd uses first scope
        let rgCwd = scopes.first ?? primaryWorkspace
        var rgArgs = ["/usr/bin/env", "rg", "-n", "--no-heading", "--max-count", "\(maxMatchesPerScope)"]
        if !caseSensitive { rgArgs.append("-i") }
        if multiline { rgArgs.append("-U") }
        if !fileType.isEmpty { rgArgs.append(contentsOf: ["--type", fileType]) }
        if !globPattern.isEmpty { rgArgs.append(contentsOf: ["--glob", globPattern]) }
        if shouldUseContentMode, maxContext > 0 { rgArgs.append(contentsOf: ["-C", "\(maxContext)"]) }
        if outputMode == "files_only" { rgArgs.append("-l") }
        if outputMode == "count" { rgArgs.append("--count") }
        rgArgs.append(query)
        rgArgs.append(contentsOf: scopes)
        rgArgs.append(contentsOf: ["--glob", "!.build", "--glob", "!node_modules", "--glob", "!.git"])

        let (rgOut, rgErr, rgExit) = await shellExec(
            args: rgArgs,
            cwd: rgCwd,
            timeout: context.policy.timeoutMs
        )
        searchOutput = rgOut
        searchError = rgErr

        // Fallback: grep when rg is not available.
        let rgMissing = rgExit == 127
            || rgErr.lowercased().contains("command not found")
            || rgErr.lowercased().contains("no such file or directory")
        if rgMissing {
            usedFallback = true
            var grepArgs = ["/usr/bin/env", "grep", "-RIn"]
            if !caseSensitive { grepArgs.append("-i") }
            grepArgs.append(contentsOf: ["-m", "\(maxMatchesPerScope)"])
            if shouldUseContentMode, maxContext > 0 { grepArgs.append(contentsOf: ["-C", "\(maxContext)"]) }
            if outputMode == "files_only" { grepArgs.append("-l") }
            if outputMode == "count" { grepArgs.append("-c") }
            grepArgs.append(query)
            grepArgs.append(contentsOf: scopes)

            let (grepOut, grepErr, _) = await shellExec(
                args: grepArgs,
                cwd: rgCwd,
                timeout: context.policy.timeoutMs
            )
            searchOutput = grepOut
            searchError = grepErr
        }

        let durationMs = max(1, Int(Date().timeIntervalSince(startDate) * 1000))
        let trimmedOutput = searchOutput.trimmingCharacters(in: .whitespacesAndNewlines)

        // If both engines are unavailable or failed unexpectedly, report transport failure.
        if trimmedOutput.isEmpty, usedFallback, searchError.lowercased().contains("not found") {
            return failure(
                "Text search tools are unavailable (rg/grep not found)",
                errorCode: "transport",
                startDate: startDate,
                payload: [
                    "title": "Grep \(query)",
                    "pathScope": (rawScope.isEmpty || rawScope == ".") ? scopes.joined(separator: ",") : rawScope,
                ]
            )
        }

        // No matches is a successful search with zero results.
        if trimmedOutput.isEmpty {
            return ToolResult(ok: true, payload: [
                "title": "Grep \(query)",
                "query": query,
                "detail": "No matches found",
                "output": "",
                "count": "0",
                "previewLines": "",
                "output_mode": outputMode,
                "pathScope": (rawScope.isEmpty || rawScope == ".") ? scopes.joined(separator: ",") : rawScope,
            ], durationMs: durationMs)
        }

        let renderedOutput: String
        let matchCount: Int
        let previewLines: String
        let detail: String

        switch outputMode {
        case "files_only":
            let files = trimmedOutput
                .components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            renderedOutput = files.joined(separator: "\n")
            matchCount = files.count
            previewLines = files.prefix(8).joined(separator: "\n")
            detail = "\(matchCount) files matched"
        case "count":
            let rows = trimmedOutput
                .components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            let total = rows.reduce(0) { partial, row in
                guard let tail = row.split(separator: ":").last,
                      let value = Int(tail.trimmingCharacters(in: .whitespacesAndNewlines)) else {
                    return partial
                }
                return partial + value
            }
            renderedOutput = rows.joined(separator: "\n")
            matchCount = max(0, total)
            previewLines = rows.prefix(8).joined(separator: "\n")
            detail = "\(matchCount) total matches"
        default:
            let ranked = rankGrepResults(searchOutput, query: query)
            let matchLines = extractSearchMatchLines(ranked, limit: 500)
            renderedOutput = ranked
            matchCount = matchLines.count
            previewLines = matchLines.prefix(8).joined(separator: "\n")
            detail = "\(matchCount) matches"
        }

        let pathScopeForPayload = (rawScope.isEmpty || rawScope == ".") ? scopes.joined(separator: ",") : rawScope
        return ToolResult(ok: true, payload: [
            "title": "Grep \(query)",
            "query": query,
            "detail": detail,
            "output": truncate(renderedOutput, maxBytes: context.policy.maxBashOutputBytes),
            "count": "\(matchCount)",
            "previewLines": previewLines,
            "output_mode": outputMode,
            "pathScope": pathScopeForPayload,
            "glob": globPattern,
        ], durationMs: durationMs)
    }

    /// Format trigram search results in ripgrep-compatible output.
    private func formatTrigramAsGrepOutput(
        result: TrigramSearchResult,
        outputMode: String,
        query: String,
        maxContext: Int
    ) -> String {
        switch outputMode {
        case "files_only":
            let files = Set(result.matches.map(\.filePath))
            return files.sorted().joined(separator: "\n")
        case "count":
            var counts: [String: Int] = [:]
            for match in result.matches {
                counts[match.filePath, default: 0] += 1
            }
            return counts.sorted(by: { $0.key < $1.key })
                .map { "\($0.key):\($0.value)" }
                .joined(separator: "\n")
        default:
            return result.matches.map { hit in
                "\(hit.filePath):\(hit.line):\(hit.snippet)"
            }.joined(separator: "\n")
        }
    }
}
