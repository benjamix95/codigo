import Foundation

extension UnifiedToolRuntime {
    func executeSearchSymbols(call: ToolCall, context: ToolExecutionContext, startDate: Date) async -> ToolResult {
        let query = (call.args["query"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if query.isEmpty {
            return failure("query is required", errorCode: "validation", startDate: startDate)
        }

        // Prefer index-powered search if available (supports all languages)
        if let indexTools {
            let events = await indexTools.execute(
                toolName: "codebase_search",
                args: call.args,
                callId: call.id,
                workspacePaths: preferredWorkspacePaths(for: context),
                excludedPaths: excludedPaths
            )
            let result = toolResultFromIndexEvents(events, startDate: startDate)
            if result.ok, let output = result.payload["output"], !output.contains("No symbols found") {
                return result
            }
        }

        // Fallback to multi-language regex-based ripgrep search
        let kind = (call.args["kind"] ?? "all").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let kindPattern: String
        switch kind {
        case "class": kindPattern = "(class|Class)\\s+"
        case "struct": kindPattern = "(struct|Struct)\\s+"
        case "enum": kindPattern = "(enum|Enum)\\s+"
        case "protocol": kindPattern = "(protocol|Protocol|interface|Interface|trait)\\s+"
        case "function", "func": kindPattern = "(func|function|def|fn)\\s+"
        default: kindPattern = "(class|struct|enum|protocol|func|function|def|fn|type|trait|interface|const|let|var)\\s+"
        }
        // Search across all source file types, not just Swift
        let cmd = "rg -n \"\(kindPattern)\(shellEscaped(query))\" --type-add 'src:*.{swift,ts,tsx,js,jsx,py,go,rs,java,kt,rb,cs,php}' --type src . | head -n 200"
        return await runBash(
            command: cmd,
            cwd: context.workspaceContext.workspacePath,
            startDate: startDate,
            title: "Search symbols \(query)",
            timeoutMs: context.policy.timeoutMs,
            maxOutputBytes: context.policy.maxBashOutputBytes,
            policy: context.policy
        )
    }

    func executeWorkspaceStats(call: ToolCall, context: ToolExecutionContext, startDate: Date) async -> ToolResult {
        let scope = (call.args["path"] ?? ".").trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedPath: String
        do {
            resolvedPath = try resolveRequiredPath(scope, context: context)
        } catch {
            return failure("Invalid path: \(scope)", errorCode: "validation", startDate: startDate)
        }
        let statsURL = URL(fileURLWithPath: resolvedPath)
        let excludedSet = Set(context.workspaceContext.excludedPaths)

        let stats = await Task.detached(priority: .utility) {
            var fileCount = 0
            var dirCount = 0
            var totalBytes: Int64 = 0
            let fm = FileManager.default

            if let enumerator = fm.enumerator(
                at: statsURL,
                includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey],
                options: [.skipsHiddenFiles]
            ) {
                while let itemURL = enumerator.nextObject() as? URL {
                    let name = itemURL.lastPathComponent
                    if excludedSet.contains(name) {
                        enumerator.skipDescendants()
                        continue
                    }
                    guard let values = try? itemURL.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey]) else { continue }
                    if values.isDirectory == true {
                        dirCount += 1
                    } else {
                        fileCount += 1
                        totalBytes += Int64(values.fileSize ?? 0)
                    }
                }
            }
            return (fileCount, dirCount, totalBytes)
        }.value

        let sizeStr: String
        if stats.2 > 1_048_576 {
            sizeStr = String(format: "%.1f MB", Double(stats.2) / 1_048_576.0)
        } else if stats.2 > 1024 {
            sizeStr = String(format: "%.1f KB", Double(stats.2) / 1024.0)
        } else {
            sizeStr = "\(stats.2) bytes"
        }

        return success([
            "title": "Workspace stats",
            "path": resolvedPath,
            "detail": "\(stats.0) files, \(stats.1) dirs, \(sizeStr)",
            "output": "files: \(stats.0)\ndirs: \(stats.1)\nsize: \(sizeStr)\nbytes: \(stats.2)"
        ], startDate: startDate)
    }

    func executeDependencyAudit(call: ToolCall, context: ToolExecutionContext, startDate: Date) async -> ToolResult {
        let manager = (call.args["manager"] ?? "swift").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let command: String
        switch manager {
        case "swift":
            command = "swift package show-dependencies --format text"
        case "npm", "node":
            command = "npm audit --json || true"
        case "pnpm":
            command = "pnpm audit --json || true"
        case "yarn":
            command = "yarn audit --json || true"
        default:
            return failure("unsupported manager: \(manager)", errorCode: "validation", startDate: startDate)
        }
        return await runBash(
            command: command,
            cwd: context.workspaceContext.workspacePath,
            startDate: startDate,
            title: "Dependency audit",
            timeoutMs: context.policy.timeoutMs,
            maxOutputBytes: context.policy.maxBashOutputBytes,
            policy: context.policy
        )
    }

    func executeIndexTool(
        name: String,
        call: ToolCall,
        context: ToolExecutionContext,
        startDate: Date
    ) async -> ToolResult {
        let indexTools = await ensureIndexTools(for: context)
        let normalizedArgs = normalizedArgsForIndexTool(name: name, args: call.args)
        let events = await indexTools.execute(
            toolName: name,
            args: normalizedArgs,
            callId: call.id,
            workspacePaths: preferredWorkspacePaths(for: context),
            excludedPaths: excludedPaths
        )
        return toolResultFromIndexEvents(events, startDate: startDate)
    }

    func normalizedArgsForIndexTool(name: String, args: [String: String]) -> [String: String] {
        var normalized = args

        switch name {
        case "find_symbol", "find_references":
            if (normalized["query"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
               let legacyName = normalized["name"]?.trimmingCharacters(in: .whitespacesAndNewlines),
               !legacyName.isEmpty {
                normalized["query"] = legacyName
            }
        case "find_files":
            if (normalized["query"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
               let pattern = normalized["pattern"]?.trimmingCharacters(in: .whitespacesAndNewlines),
               !pattern.isEmpty {
                normalized["query"] = pattern
            }
            if (normalized["filePattern"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
               let pathScope = normalized["path"]?.trimmingCharacters(in: .whitespacesAndNewlines),
               !pathScope.isEmpty {
                normalized["filePattern"] = normalizePathScopeAsFilePattern(pathScope)
            }
        case "codebase_search":
            if (normalized["filePattern"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
               let path = normalized["path"]?.trimmingCharacters(in: .whitespacesAndNewlines),
               !path.isEmpty {
                normalized["filePattern"] = normalizePathScopeAsFilePattern(path)
            }
        default:
            break
        }

        return normalized
    }

    func normalizePathScopeAsFilePattern(_ rawPathScope: String) -> String {
        var normalized = rawPathScope.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return "" }
        if normalized == "." { return "" }
        if normalized.hasPrefix("./") {
            normalized = String(normalized.dropFirst(2))
        }
        while normalized.hasSuffix("/") {
            normalized.removeLast()
        }
        guard !normalized.isEmpty, normalized != "." else { return "" }
        return normalized
    }

    func toolResultFromIndexEvents(_ events: [StreamEvent], startDate: Date) -> ToolResult {
        for event in events {
            guard case .raw(let type, let payload) = event else { continue }
            if type == "tool_execution_error" || payload["status"] == "failed" {
                return failure(
                    payload["detail"] ?? payload["output"] ?? "Index tool failed",
                    errorCode: "transport",
                    startDate: startDate,
                    payload: payload
                )
            }
            if payload["status"] == "completed" {
                return ToolResult(
                    ok: true,
                    payload: payload,
                    durationMs: max(1, Int(Date().timeIntervalSince(startDate) * 1000))
                )
            }
        }
        return failure("No result from index tool", errorCode: "transport", startDate: startDate)
    }

    // MARK: - Improved Grep

    func executeRenameSymbol(call: ToolCall, context: ToolExecutionContext, startDate: Date) async -> ToolResult {
        let query = call.args["query"] ?? ""
        let newName = call.args["new_name"] ?? ""
        guard !query.isEmpty, !newName.isEmpty else {
            return ToolResult(ok: false, payload: ["detail": "Both query and new_name are required"], durationMs: 0)
        }
        let allWorkspacePaths = context.workspaceContext.workspacePaths.map(\.path)
        let primaryWorkspace = allWorkspacePaths.first ?? context.workspaceContext.workspacePath.path

        // Use index to find all references
        var files: [(path: String, line: Int, content: String)] = []
        if indexTools != nil {
            let refCall = ToolCall(id: UUID().uuidString, name: "find_references", args: ["query": query], sourceProvider: call.sourceProvider, swarmId: nil, scope: call.scope)
            let refResult = await executeIndexTool(name: "find_references", call: refCall, context: context, startDate: startDate)
            if refResult.ok, let output = refResult.payload["output"] {
                // Parse references output
                for line in output.components(separatedBy: "\n") {
                    let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                    if trimmed.isEmpty { continue }
                    // Format: "file.swift:42: content..."
                    let parts = trimmed.components(separatedBy: ":")
                    if parts.count >= 2, let lineNum = Int(parts[1].trimmingCharacters(in: .whitespaces)) {
                        let filePath = parts[0].trimmingCharacters(in: .whitespaces)
                        let absPath = (filePath as NSString).isAbsolutePath ? filePath : (primaryWorkspace as NSString).appendingPathComponent(filePath)
                        files.append((path: absPath, line: lineNum, content: trimmed))
                    }
                }
            }
        }

        // Fallback to ripgrep across all workspace folders if no index results
        if files.isEmpty {
            let searchPaths = allWorkspacePaths.isEmpty ? ["."] : allWorkspacePaths
            let rgArgs = ["-rn", "--no-heading", query] + searchPaths
            guard let rgPath = await resolveRipgrepPath(cwd: primaryWorkspace) else {
                let ms = Int(Date().timeIntervalSince(startDate) * 1000)
                return ToolResult(
                    ok: false,
                    payload: ["detail": "ripgrep executable not found. Install 'rg' or provide indexed references."],
                    durationMs: ms
                )
            }
            let (output, _, _) = await shellExec(args: [rgPath] + rgArgs, cwd: primaryWorkspace, timeout: 15_000)
            for line in output.components(separatedBy: "\n") {
                let parts = line.components(separatedBy: ":")
                if parts.count >= 3, let lineNum = Int(parts[1]) {
                    files.append((path: parts[0], line: lineNum, content: line))
                }
            }
        }

        guard !files.isEmpty else {
            return ToolResult(ok: false, payload: ["detail": "Symbol '\(query)' not found in codebase"], durationMs: Int(Date().timeIntervalSince(startDate) * 1000))
        }

        // Get unique file paths and perform replacements
        let uniquePaths = Set(files.map(\.path))
        var replaced = 0
        var errors: [String] = []

        for filePath in uniquePaths {
            guard FileManager.default.fileExists(atPath: filePath) else { continue }
            do {
                var content = try String(contentsOfFile: filePath, encoding: .utf8)
                let originalContent = content
                content = content.replacingOccurrences(of: query, with: newName)
                if content != originalContent {
                    try content.write(toFile: filePath, atomically: true, encoding: .utf8)
                    replaced += 1
                }
            } catch {
                errors.append("\(filePath): \(error.localizedDescription)")
            }
        }

        let detail = "Renamed '\(query)' → '\(newName)' in \(replaced) files (\(files.count) references)"
        let ms = Int(Date().timeIntervalSince(startDate) * 1000)
        return ToolResult(ok: errors.isEmpty, payload: [
            "title": "rename_symbol",
            "detail": errors.isEmpty ? detail : "\(detail); errors: \(errors.joined(separator: "; "))",
            "output": detail
        ], durationMs: ms)
    }

    func executeFindAndReplaceAll(call: ToolCall, context: ToolExecutionContext, startDate: Date) async -> ToolResult {
        let pattern = call.args["pattern"] ?? call.args["query"] ?? ""
        let replacement = call.args["replacement"] ?? call.args["new_string"] ?? ""
        let fileType = call.args["file_type"] ?? call.args["fileType"] ?? ""
        let isRegex = (call.args["regex"] ?? "false").lowercased() == "true"
        let searchPaths = context.workspaceContext.workspacePaths.map(\.path)
        let primaryWorkspace = searchPaths.first ?? context.workspaceContext.workspacePath.path

        guard !pattern.isEmpty else {
            return ToolResult(ok: false, payload: ["detail": "pattern is required"], durationMs: 0)
        }

        // Use ripgrep to find matching files across all workspace folders
        var rgArgs = ["-l", "--no-heading"]
        if !fileType.isEmpty { rgArgs += ["-t", fileType] }
        rgArgs.append(pattern)
        rgArgs.append(contentsOf: searchPaths.isEmpty ? ["."] : searchPaths)

        guard let rgPath = await resolveRipgrepPath(cwd: primaryWorkspace) else {
            let ms = Int(Date().timeIntervalSince(startDate) * 1000)
            return ToolResult(
                ok: false,
                payload: ["detail": "ripgrep executable not found. Install 'rg' to use find_and_replace_all."],
                durationMs: ms
            )
        }
        let (output, _, _) = await shellExec(args: [rgPath] + rgArgs, cwd: primaryWorkspace, timeout: 15_000)
        let matchingFiles = output.components(separatedBy: "\n").filter { !$0.isEmpty }

        guard !matchingFiles.isEmpty else {
            return ToolResult(ok: true, payload: ["detail": "No matches found for '\(pattern)'", "output": "0 files changed"], durationMs: Int(Date().timeIntervalSince(startDate) * 1000))
        }

        var totalReplacements = 0
        var errors: [String] = []

        for filePath in matchingFiles {
            do {
                var content = try String(contentsOfFile: filePath, encoding: .utf8)
                let original = content
                if isRegex {
                    let regex = try NSRegularExpression(pattern: pattern)
                    content = regex.stringByReplacingMatches(in: content, range: NSRange(content.startIndex..., in: content), withTemplate: replacement)
                } else {
                    content = content.replacingOccurrences(of: pattern, with: replacement)
                }
                if content != original {
                    try content.write(toFile: filePath, atomically: true, encoding: String.Encoding.utf8)
                    totalReplacements += 1
                }
            } catch {
                errors.append("\((filePath as NSString).lastPathComponent): \(error.localizedDescription)")
            }
        }

        let detail = "Replaced '\(pattern)' → '\(replacement)' in \(totalReplacements)/\(matchingFiles.count) files"
        let ms = Int(Date().timeIntervalSince(startDate) * 1000)
        return ToolResult(ok: errors.isEmpty, payload: [
            "title": "find_and_replace_all",
            "detail": errors.isEmpty ? detail : "\(detail); errors: \(errors.prefix(5).joined(separator: "; "))",
            "output": detail
        ], durationMs: ms)
    }

    func executeUndoEdit(call: ToolCall, context: ToolExecutionContext, startDate: Date) async -> ToolResult {
        let rawPath = call.args["path"] ?? ""
        guard !rawPath.isEmpty else {
            return ToolResult(ok: false, payload: ["detail": "path is required"], durationMs: 0)
        }
        let workspace = context.workspaceContext.workspacePath.path
        let path: String
        if (rawPath as NSString).isAbsolutePath {
            path = rawPath
        } else {
            path = (workspace as NSString).appendingPathComponent(rawPath)
        }

        // git checkout -- <file> to revert to last committed state
        let (output, stderr, exitCode) = await shellExec(args: ["/usr/bin/git", "checkout", "--", path], cwd: workspace, timeout: 10_000)
        let ms = Int(Date().timeIntervalSince(startDate) * 1000)
        if exitCode == 0 {
            return ToolResult(ok: true, payload: [
                "title": "undo_edit",
                "detail": "Reverted \((path as NSString).lastPathComponent) to last committed state",
                "path": path,
                "output": output.isEmpty ? "File reverted successfully" : output
            ], durationMs: ms)
        } else {
            return ToolResult(ok: false, payload: [
                "title": "undo_edit",
                "detail": "Failed to revert: \(stderr.isEmpty ? output : stderr)",
                "path": path
            ], durationMs: ms)
        }
    }

    func executeSemanticSearch(call: ToolCall, context: ToolExecutionContext, startDate: Date) async -> ToolResult {
        let query = (call.args["query"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            return failure("query is required", errorCode: "validation", startDate: startDate)
        }
        let targetDirs = (call.args["target_directories"] ?? "")
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
            return absolutePath
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

    // MARK: - read_lints: Read current linter/diagnostic state without running a build

    func executeReadLints(call: ToolCall, context: ToolExecutionContext, startDate: Date) async -> ToolResult {
        let workspace = context.workspaceContext.workspacePath.path
        let rawPath = call.args["path"] ?? ""
        let severity = call.args["severity"] ?? "all"  // all, error, warning
        let maxCount = Int(call.args["limit"] ?? "50") ?? 50

        // Strategy: Detect project type and use the fastest lint-only command
        var lintOutput = ""
        var lintErrors: [String] = []
        var toolUsed = ""

        // Check for Swift project
        let packageSwift = (workspace as NSString).appendingPathComponent("Package.swift")
        let xcodeproj = try? FileManager.default.contentsOfDirectory(atPath: workspace).first { $0.hasSuffix(".xcodeproj") || $0.hasSuffix(".xcworkspace") }

        if FileManager.default.fileExists(atPath: packageSwift) || xcodeproj != nil {
            // Swift: use `swift build --skip-link` for fast compile-only check, or swiftc -typecheck for single file
            toolUsed = "swift"
            if !rawPath.isEmpty {
                let filePath = (rawPath as NSString).isAbsolutePath ? rawPath : (workspace as NSString).appendingPathComponent(rawPath)
                let (out, err, _) = await shellExec(
                    args: ["/usr/bin/xcrun", "swiftc", "-typecheck", filePath],
                    cwd: workspace, timeout: 30_000
                )
                lintOutput = out
                if !err.isEmpty { lintErrors.append(err) }
            } else {
                let (out, err, _) = await shellExec(
                    args: ["/usr/bin/swift", "build", "--skip-link"],
                    cwd: workspace, timeout: 60_000
                )
                lintOutput = out + "\n" + err
            }
        }

        // Check for Node/TS project
        let packageJson = (workspace as NSString).appendingPathComponent("package.json")
        if FileManager.default.fileExists(atPath: packageJson) && toolUsed.isEmpty {
            // Try eslint first, then tsc --noEmit
            let eslintPath = (workspace as NSString).appendingPathComponent("node_modules/.bin/eslint")
            if FileManager.default.fileExists(atPath: eslintPath) {
                toolUsed = "eslint"
                var args = [eslintPath, "--format", "compact", "--no-color"]
                if !rawPath.isEmpty { args.append(rawPath) } else { args.append(".") }
                let (out, err, _) = await shellExec(args: args, cwd: workspace, timeout: 30_000)
                lintOutput = out
                if !err.isEmpty { lintErrors.append(err) }
            } else {
                // tsc --noEmit
                let tscPath = (workspace as NSString).appendingPathComponent("node_modules/.bin/tsc")
                if FileManager.default.fileExists(atPath: tscPath) {
                    toolUsed = "tsc"
                    let (out, err, _) = await shellExec(
                        args: [tscPath, "--noEmit", "--pretty", "false"],
                        cwd: workspace, timeout: 30_000
                    )
                    lintOutput = out
                    if !err.isEmpty { lintErrors.append(err) }
                }
            }
        }

        // Check for Cargo (Rust)
        let cargoToml = (workspace as NSString).appendingPathComponent("Cargo.toml")
        if FileManager.default.fileExists(atPath: cargoToml) && toolUsed.isEmpty {
            toolUsed = "cargo"
            let (out, err, _) = await shellExec(
                args: ["/usr/bin/env", "cargo", "check", "--message-format=short"],
                cwd: workspace, timeout: 60_000
            )
            lintOutput = out + "\n" + err
        }

        // Check for Go
        let goMod = (workspace as NSString).appendingPathComponent("go.mod")
        if FileManager.default.fileExists(atPath: goMod) && toolUsed.isEmpty {
            toolUsed = "go"
            let target = rawPath.isEmpty ? "./..." : rawPath
            let (out, err, _) = await shellExec(
                args: ["/usr/bin/env", "go", "vet", target],
                cwd: workspace, timeout: 30_000
            )
            lintOutput = out + "\n" + err
        }

        // Fallback: no recognized project type
        if toolUsed.isEmpty {
            return failure(
                "No recognized linter found. Supported: Swift (Package.swift/xcodeproj), Node (eslint/tsc), Cargo, Go.",
                errorCode: "validation", startDate: startDate
            )
        }

        // Parse and filter diagnostics
        let allLines = lintOutput.components(separatedBy: "\n").filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        let filtered: [String]
        switch severity {
        case "error":
            filtered = allLines.filter { line in
                let lower = line.lowercased()
                return lower.contains("error") || lower.contains("fatal")
            }
        case "warning":
            filtered = allLines.filter { line in
                let lower = line.lowercased()
                return lower.contains("warning") || lower.contains("warn")
            }
        default:
            filtered = allLines
        }

        let limited = Array(filtered.prefix(maxCount))
        let errorCount = limited.filter { $0.lowercased().contains("error") }.count
        let warningCount = limited.filter { $0.lowercased().contains("warning") }.count

        let summary = "\(errorCount) errors, \(warningCount) warnings (via \(toolUsed))"

        return success([
            "title": "read_lints",
            "linter": toolUsed,
            "error_count": "\(errorCount)",
            "warning_count": "\(warningCount)",
            "detail": summary,
            "output": truncate(limited.joined(separator: "\n"), maxBytes: context.policy.maxBashOutputBytes),
            "total_diagnostics": "\(filtered.count)"
        ], startDate: startDate)
    }

    // MARK: - debug_context: Gather full debug context (git, open files, lints, terminal state)
}
