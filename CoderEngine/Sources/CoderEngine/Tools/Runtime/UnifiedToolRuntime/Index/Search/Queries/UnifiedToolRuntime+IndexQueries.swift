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
}
