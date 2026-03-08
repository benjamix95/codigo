import Foundation

extension UnifiedToolRuntime {
    func executeGitDiff(call: ToolCall, context: ToolExecutionContext, startDate: Date) async -> ToolResult {
        let scope = call.args["path"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let cmd = scope.isEmpty ? "git diff -- ." : "git diff -- '\(shellEscaped(scope))'"
        return await runBash(
            command: cmd,
            cwd: context.workspaceContext.workspacePath,
            startDate: startDate,
            title: "Git diff",
            timeoutMs: context.policy.timeoutMs,
            maxOutputBytes: context.policy.maxBashOutputBytes,
            policy: context.policy
        )
    }

    func executeDiffFiles(call: ToolCall, context: ToolExecutionContext, startDate: Date) async -> ToolResult {
        let file1 = (call.args["file1"] ?? call.args["path1"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let file2 = (call.args["file2"] ?? call.args["path2"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)

        guard !file1.isEmpty && !file2.isEmpty else {
            return failure("file1 and file2 are required", errorCode: "validation", startDate: startDate)
        }

        let abs1: String
        let abs2: String
        do {
            abs1 = try resolveRequiredPath(file1, context: context)
            abs2 = try resolveRequiredPath(file2, context: context)
        } catch {
            return failure("Path is not allowed by sandbox policy", errorCode: "sandbox", startDate: startDate)
        }

        let contextLines = min(Int(call.args["context"] ?? "3") ?? 3, 10)
        let result = await runShellCommand(
            "diff -u --label '\(shellEscaped((file1 as NSString).lastPathComponent))' --label '\(shellEscaped((file2 as NSString).lastPathComponent))' -U \(contextLines) '\(shellEscaped(abs1))' '\(shellEscaped(abs2))' 2>&1",
            timeout: 10_000
        )

        let trimmed = result.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return success([
                "title": "diff_files",
                "detail": "Files are identical",
                "output": "Files are identical: \(file1) and \(file2)"
            ], startDate: startDate)
        }

        return success([
            "title": "diff_files \((file1 as NSString).lastPathComponent) vs \((file2 as NSString).lastPathComponent)",
            "detail": "Files differ",
            "output": truncate(trimmed, maxBytes: context.policy.maxBashOutputBytes)
        ], startDate: startDate)
    }

    // MARK: - git_status

    func executeGitStatus(call: ToolCall, context: ToolExecutionContext, startDate: Date) async -> ToolResult {
        let workspace = context.workspaceContext.workspacePaths.first?.path ?? "."

        let branchResult = await runShellCommand(
            "cd '\(shellEscaped(workspace))' && git branch --show-current 2>/dev/null",
            timeout: 5_000
        )
        let branch = branchResult.trimmingCharacters(in: .whitespacesAndNewlines)

        let statusResult = await runShellCommand(
            "cd '\(shellEscaped(workspace))' && git status --porcelain=v1 2>/dev/null",
            timeout: 5_000
        )

        let aheadBehind = await runShellCommand(
            "cd '\(shellEscaped(workspace))' && git rev-list --left-right --count HEAD...@{upstream} 2>/dev/null",
            timeout: 5_000
        )

        let lastCommit = await runShellCommand(
            "cd '\(shellEscaped(workspace))' && git log -1 --format='%h %s' 2>/dev/null",
            timeout: 5_000
        )

        var staged: [String] = []
        var unstaged: [String] = []
        var untracked: [String] = []
        var conflicts: [String] = []

        for line in statusResult.components(separatedBy: "\n") where line.count >= 3 {
            let x = line[line.startIndex]
            let y = line[line.index(after: line.startIndex)]
            let file = String(line.dropFirst(3))

            if x == "U" || y == "U" || (x == "A" && y == "A") || (x == "D" && y == "D") {
                conflicts.append("!! \(file)")
            } else {
                if x != " " && x != "?" {
                    staged.append("\(x)  \(file)")
                }
                if y != " " && y != "?" {
                    unstaged.append(" \(y) \(file)")
                }
                if x == "?" && y == "?" {
                    untracked.append("?? \(file)")
                }
            }
        }

        var output = "## Branch: \(branch.isEmpty ? "(detached HEAD)" : branch)\n"

        let abParts = aheadBehind.trimmingCharacters(in: .whitespacesAndNewlines).components(separatedBy: "\t")
        if abParts.count == 2, let ahead = Int(abParts[0]), let behind = Int(abParts[1]) {
            if ahead > 0 || behind > 0 {
                var trackingInfo: [String] = []
                if ahead > 0 { trackingInfo.append("\(ahead) ahead") }
                if behind > 0 { trackingInfo.append("\(behind) behind") }
                output += "Tracking: \(trackingInfo.joined(separator: ", "))\n"
            }
        }

        let commit = lastCommit.trimmingCharacters(in: .whitespacesAndNewlines)
        if !commit.isEmpty {
            output += "Last commit: \(commit)\n"
        }

        if !conflicts.isEmpty {
            output += "\n## Conflicts (\(conflicts.count))\n\(conflicts.joined(separator: "\n"))\n"
        }
        if !staged.isEmpty {
            output += "\n## Staged (\(staged.count))\n\(staged.joined(separator: "\n"))\n"
        }
        if !unstaged.isEmpty {
            output += "\n## Unstaged (\(unstaged.count))\n\(unstaged.joined(separator: "\n"))\n"
        }
        if !untracked.isEmpty {
            output += "\n## Untracked (\(untracked.count))\n\(untracked.prefix(30).joined(separator: "\n"))\n"
            if untracked.count > 30 {
                output += "...(\(untracked.count - 30) more)\n"
            }
        }

        if staged.isEmpty && unstaged.isEmpty && untracked.isEmpty && conflicts.isEmpty {
            output += "\nClean working tree.\n"
        }

        let totalChanges = staged.count + unstaged.count + untracked.count + conflicts.count
        return success([
            "title": "git_status [\(branch.isEmpty ? "HEAD" : branch)]",
            "detail": "\(totalChanges) changes",
            "output": output.trimmingCharacters(in: .whitespacesAndNewlines)
        ], startDate: startDate)
    }

    // MARK: - git_show

    func executeGitShow(call: ToolCall, context: ToolExecutionContext, startDate: Date) async -> ToolResult {
        let ref = (call.args["commit"] ?? call.args["ref"] ?? "HEAD").trimmingCharacters(in: .whitespacesAndNewlines)
        let workspace = context.workspaceContext.workspacePaths.first?.path ?? "."
        let statOnly = (call.args["stat_only"] ?? "").lowercased() == "true"

        let format = statOnly ? "--stat" : "--stat -p"
        let result = await runShellCommand(
            "cd '\(shellEscaped(workspace))' && git show \(format) --format='commit %H%nAuthor: %an <%ae>%nDate: %ad%n%n%s%n%b' '\(shellEscaped(ref))' 2>&1",
            timeout: 15_000
        )

        let trimmed = result.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed.contains("fatal:") {
            return failure("Commit not found: \(ref)", errorCode: "validation", startDate: startDate)
        }

        return success([
            "title": "git_show \(ref)",
            "detail": statOnly ? "stats only" : "full diff",
            "output": truncate(trimmed, maxBytes: context.policy.maxBashOutputBytes)
        ], startDate: startDate)
    }

    // MARK: - code_context

    func executeCodeContext(call: ToolCall, context: ToolExecutionContext, startDate: Date) async -> ToolResult {
        let symbol = (call.args["symbol"] ?? call.args["query"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !symbol.isEmpty else {
            return failure("symbol is required", errorCode: "validation", startDate: startDate)
        }

        let maxRefs = min(Int(call.args["max_refs"] ?? "15") ?? 15, 30)
        var output = ""

        if let index = codebaseIndex {
            let definitions = await index.findSymbols(query: symbol, kind: nil, limit: 5)
            if !definitions.isEmpty {
                output += "## Definition\n"
                for def in definitions.prefix(3) {
                    output += "\(def.kind.rawValue) \(def.name)"
                    if !def.signature.isEmpty { output += " — \(def.signature)" }
                    output += "\n  \(def.filePath):\(def.line)\n"
                    if let doc = def.documentation, !doc.isEmpty {
                        output += "  Doc: \(doc.prefix(200))\n"
                    }

                    let absPath: String
                    if (def.filePath as NSString).isAbsolutePath {
                        absPath = def.filePath
                    } else {
                        let ws = context.workspaceContext.workspacePaths.first?.path ?? "."
                        absPath = (ws as NSString).appendingPathComponent(def.filePath)
                    }
                    if let fh = FileHandle(forReadingAtPath: absPath) {
                        defer { try? fh.close() }
                        if let data = try? fh.read(upToCount: context.policy.maxReadBytesPerFile) {
                            let fc = String(data: data, encoding: .utf8) ?? ""
                            let allLines = fc.components(separatedBy: "\n")
                            let si = max(0, def.line - 1)
                            let ei = def.endLine > 0 ? min(allLines.count, def.endLine) : min(allLines.count, si + 20)
                            if si < allLines.count {
                                let codeSlice = allLines[si..<ei]
                                output += "  ```\n"
                                for (ci, cl) in codeSlice.enumerated() {
                                    output += "  \(si + ci + 1)|\(cl)\n"
                                }
                                output += "  ```\n"
                            }
                        }
                    }
                    output += "\n"
                }
            }

            let refs = await index.findReferences(symbolName: symbol, limit: maxRefs)
            if !refs.isEmpty {
                output += "## References (\(refs.count))\n"
                for r in refs.prefix(maxRefs) {
                    let ctx = r.contextLine.trimmingCharacters(in: .whitespaces)
                    let trimCtx = ctx.count > 100 ? String(ctx.prefix(100)) + "..." : ctx
                    output += "  \(r.filePath):\(r.line) — \(trimCtx)\n"
                }
                output += "\n"
            }

            if let firstDef = definitions.first {
                let deps = await index.fileDependencies(firstDef.filePath)
                if !deps.imports.isEmpty {
                    output += "## File imports\n"
                    for imp in deps.imports.prefix(10) {
                        output += "  \(imp)\n"
                    }
                    output += "\n"
                }
            }
        } else {
            let workspace = context.workspaceContext.workspacePaths.first?.path ?? "."
            let (grepOut, _, _) = await shellExec(
                args: ["/bin/bash", "-c", "cd '\(shellEscaped(workspace))' && rg -n --no-heading -m 20 '\\b\(shellEscaped(symbol))\\b' --glob '!.build' --glob '!node_modules' --glob '!.git' 2>/dev/null | head -30"],
                cwd: workspace,
                timeout: 10_000
            )
            let trimmedGrep = grepOut.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmedGrep.isEmpty {
                output = "## References (grep fallback)\n\(trimmedGrep)\n"
            }
        }

        if output.isEmpty {
            return success([
                "title": "code_context \(symbol)",
                "detail": "No results",
                "output": "Symbol not found: \(symbol)"
            ], startDate: startDate)
        }

        return success([
            "title": "code_context \(symbol)",
            "detail": "Definition + references",
            "output": truncate(output, maxBytes: context.policy.maxBashOutputBytes)
        ], startDate: startDate)
    }
}
