import Foundation

extension UnifiedToolRuntime {
    func executeGlob(call: ToolCall, context: ToolExecutionContext, startDate: Date) async -> ToolResult {
        let pattern = (call.args["pattern"] ?? call.args["query"] ?? "*")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let rawScope = (call.args["path"] ?? call.args["pathScope"] ?? ".")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let scopeParts = rawScope
            .components(separatedBy: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let allWorkspacePaths = context.workspaceContext.workspacePaths.map(\.path)
        let primaryWorkspace = context.workspaceContext.workspacePath.path
        let scopes: [String] = {
            if scopeParts.isEmpty || (scopeParts.count == 1 && scopeParts[0] == ".") {
                return allWorkspacePaths.isEmpty ? ["."] : allWorkspacePaths
            }
            var out: [String] = []
            var seen = Set<String>()
            for item in scopeParts where seen.insert(item).inserted {
                let isAbsolute = (item as NSString).isAbsolutePath
                if isAbsolute {
                    out.append(item)
                } else {
                    for root in allWorkspacePaths {
                        out.append((root as NSString).appendingPathComponent(item))
                    }
                }
            }
            return out
        }()
        let maxResultsRaw = call.args["maxResults"] ?? call.args["max_results"] ?? ""
        let maxResults = min(max(Int(maxResultsRaw) ?? 500, 1), 2000)

        if let indexTools, !pattern.contains("*") {
            let indexEvents = await indexTools.execute(
                toolName: "find_files",
                args: ["query": pattern],
                callId: call.id,
                workspacePaths: preferredWorkspacePaths(for: context),
                excludedPaths: excludedPaths
            )
            let indexResult = toolResultFromIndexEvents(indexEvents, startDate: startDate)
            if indexResult.ok,
               let output = indexResult.payload["output"],
               !output.isEmpty,
               !output.contains("No files found") {
                var payload = indexResult.payload
                payload["title"] = "Glob \(pattern) (index)"
                payload["pathScope"] = (rawScope.isEmpty || rawScope == ".") ? scopes.joined(separator: ",") : rawScope
                return ToolResult(ok: true, payload: payload, durationMs: indexResult.durationMs)
            }
        }

        let rgCwd = scopes.first ?? primaryWorkspace
        var rgArgs = ["/usr/bin/env", "rg", "--files", "-g", pattern]
        rgArgs.append(contentsOf: scopes)
        rgArgs.append(contentsOf: ["--glob", "!.build", "--glob", "!node_modules", "--glob", "!.git"])

        let (rgOut, rgErr, rgExit) = await shellExec(
            args: rgArgs,
            cwd: rgCwd,
            timeout: context.policy.timeoutMs
        )
        if rgExit != 0 && !rgErr.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return failure(
                "Glob search failed: \(truncate(rgErr, maxBytes: 1_500))",
                errorCode: "transport",
                startDate: startDate,
                payload: [
                    "title": "Glob \(pattern)",
                    "query": pattern,
                    "pathScope": (rawScope.isEmpty || rawScope == ".") ? scopes.joined(separator: ",") : rawScope,
                ]
            )
        }

        let files = rgOut
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let limited = Array(files.prefix(maxResults))
        let output = limited.joined(separator: "\n")
        let previewLines = limited.prefix(8).joined(separator: "\n")
        let durationMs = max(1, Int(Date().timeIntervalSince(startDate) * 1000))
        let pathScopeForPayload = (rawScope.isEmpty || rawScope == ".") ? scopes.joined(separator: ",") : rawScope

        if limited.isEmpty {
            return ToolResult(ok: true, payload: [
                "title": "Glob \(pattern)",
                "query": pattern,
                "detail": "No matches found",
                "output": "",
                "count": "0",
                "previewLines": "",
                "output_mode": "files_only",
                "pathScope": pathScopeForPayload,
            ], durationMs: durationMs)
        }

        return ToolResult(ok: true, payload: [
            "title": "Glob \(pattern)",
            "query": pattern,
            "detail": "\(limited.count) files matched",
            "output": truncate(output, maxBytes: context.policy.maxBashOutputBytes),
            "count": "\(limited.count)",
            "previewLines": previewLines,
            "output_mode": "files_only",
            "pathScope": pathScopeForPayload,
        ], durationMs: durationMs)
    }
}
