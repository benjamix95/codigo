import Foundation

extension UnifiedToolRuntime {
    func executeRenameSymbol(call: ToolCall, context: ToolExecutionContext, startDate: Date) async -> ToolResult {
        let query = (call.args["query"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let newName = (call.args["new_name"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty, !newName.isEmpty else {
            return ToolResult(ok: false, payload: ["detail": "Both query and new_name are required"], durationMs: 0)
        }
        let allWorkspacePaths = context.workspaceContext.workspacePaths.map(\.path)
        let primaryWorkspace = allWorkspacePaths.first ?? context.workspaceContext.workspacePath.path

        if let languagePlan = await collectLanguageRenamePlan(
            query: query,
            newName: newName,
            workspacePaths: allWorkspacePaths,
            primaryWorkspace: primaryWorkspace
        ) {
            let applied = applyRename(
                query: query,
                newName: newName,
                files: languagePlan.files
            )
            let detail = "Renamed '\(query)' → '\(newName)' in \(applied.replaced) files (\(languagePlan.referenceCount) references) [\(languagePlan.source.rawValue)]"
            let ms = Int(Date().timeIntervalSince(startDate) * 1000)
            return ToolResult(ok: applied.errors.isEmpty, payload: [
                "title": "rename_symbol",
                "detail": applied.errors.isEmpty ? detail : "\(detail); errors: \(applied.errors.joined(separator: "; "))",
                "output": detail
            ], durationMs: ms)
        }

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

        let applied = applyRename(query: query, newName: newName, files: files)

        let detail = "Renamed '\(query)' → '\(newName)' in \(applied.replaced) files (\(files.count) references)"
        let ms = Int(Date().timeIntervalSince(startDate) * 1000)
        return ToolResult(ok: applied.errors.isEmpty, payload: [
            "title": "rename_symbol",
            "detail": applied.errors.isEmpty ? detail : "\(detail); errors: \(applied.errors.joined(separator: "; "))",
            "output": detail
        ], durationMs: ms)
    }

    private func collectLanguageRenamePlan(
        query: String,
        newName: String,
        workspacePaths: [String],
        primaryWorkspace: String
    ) async -> (files: [(path: String, line: Int, content: String)], referenceCount: Int, source: RuntimeLanguageSource)? {
        guard let languageService else { return nil }
        do {
            let renamePlan = try await languageService.rename(oldName: query, newName: newName)
            guard !renamePlan.references.isEmpty else { return nil }
            let files = renamePlan.references.map { reference in
                let path = resolveLanguageLocationPath(
                    reference.filePath,
                    workspacePaths: workspacePaths,
                    primaryWorkspace: primaryWorkspace
                )
                let content = "\(path):\(reference.line): \(reference.symbolName)"
                return (path: path, line: reference.line, content: content)
            }
            return (files: files, referenceCount: renamePlan.references.count, source: renamePlan.source)
        } catch {
            return nil
        }
    }

    private func applyRename(
        query: String,
        newName: String,
        files: [(path: String, line: Int, content: String)]
    ) -> (replaced: Int, errors: [String]) {
        let uniquePaths = Set(files.map { $0.path })
        var replaced = 0
        var errors: [String] = []

        for filePath in uniquePaths {
            guard FileManager.default.fileExists(atPath: filePath) else { continue }
            do {
                var content = try String(contentsOfFile: filePath, encoding: .utf8)
                let originalContent = content
                let escapedQuery = NSRegularExpression.escapedPattern(for: query)
                let wordBoundaryPattern = "\\b\(escapedQuery)\\b"
                if let regex = try? NSRegularExpression(pattern: wordBoundaryPattern) {
                    content = regex.stringByReplacingMatches(
                        in: content,
                        range: NSRange(content.startIndex..., in: content),
                        withTemplate: NSRegularExpression.escapedTemplate(for: newName)
                    )
                }
                if content != originalContent {
                    try content.write(toFile: filePath, atomically: true, encoding: .utf8)
                    replaced += 1
                }
            } catch {
                errors.append("\(filePath): \(error.localizedDescription)")
            }
        }

        return (replaced: replaced, errors: errors)
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
}
