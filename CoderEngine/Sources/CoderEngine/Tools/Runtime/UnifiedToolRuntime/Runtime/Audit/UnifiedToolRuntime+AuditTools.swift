import Foundation

extension UnifiedToolRuntime {
    func executeAuditTool(
        name: String,
        call: ToolCall,
        context: ToolExecutionContext,
        startDate: Date
    ) async -> ToolResult {
        let scopeFiles = resolveAuditScopeFiles(call: call, context: context)
        let result = CodeReviewAuditService.runTool(
            named: name,
            scopeFiles: scopeFiles,
            workspacePath: context.workspaceContext.workspacePath
        )

        let payloadData: Data
        do {
            payloadData = try JSONEncoder().encode(result.payload)
        } catch {
            return failure(
                "Unable to encode audit result payload.",
                errorCode: "encoding",
                startDate: startDate
            )
        }

        let output = String(data: payloadData, encoding: .utf8) ?? "{\"findings\":[]}"
        return success([
            "title": name,
            "detail": result.summary,
            "output": output,
            "findings_count": String(result.findings.count),
            "blocking_findings": String(result.blockingFindingsCount),
            "coverage_available": result.coverageAvailable ? "true" : "false",
        ], startDate: startDate)
    }

    private func resolveAuditScopeFiles(
        call: ToolCall,
        context: ToolExecutionContext
    ) -> [String] {
        if let explicitScope = call.args["scope_files"],
           let parsed = parseScopeFiles(explicitScope),
           !parsed.isEmpty {
            return parsed
        }

        if let path = call.args["path"]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !path.isEmpty {
            let resolved = resolvePath(
                path,
                workspacePaths: preferredWorkspacePaths(for: context).map(\.path),
                preferredRoot: context.workspaceContext.activeRootPath,
                sandboxMode: context.policy.sandboxMode
            )
            if let resolved {
                var isDirectory: ObjCBool = false
                if FileManager.default.fileExists(atPath: resolved, isDirectory: &isDirectory) {
                    let workspaceRoot = context.workspaceContext.workspacePath.path + "/"
                    if isDirectory.boolValue,
                       let enumerator = FileManager.default.enumerator(
                        at: URL(fileURLWithPath: resolved),
                        includingPropertiesForKeys: nil,
                        options: [.skipsHiddenFiles]
                       ) {
                        var files: [String] = []
                        while let item = enumerator.nextObject() as? URL {
                            guard !item.hasDirectoryPath else { continue }
                            files.append(item.path.replacingOccurrences(of: workspaceRoot, with: ""))
                        }
                        return files
                    }
                    return [resolved.replacingOccurrences(of: workspaceRoot, with: "")]
                }
            }
        }

        if let includedPaths = context.workspaceContext.includedPaths,
           !includedPaths.isEmpty {
            return includedPaths
        }
        if let active = context.workspaceContext.activeFilePath, !active.isEmpty {
            return [active]
        }
        if !context.workspaceContext.openFiles.isEmpty {
            return context.workspaceContext.openFiles.map(\.path)
        }
        return gitChangedFiles(in: context.workspaceContext.workspacePath)
    }

    private func parseScopeFiles(_ raw: String) -> [String]? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let data = trimmed.data(using: .utf8),
           let decoded = try? JSONDecoder().decode([String].self, from: data) {
            return decoded
        }
        return trimmed
            .split(whereSeparator: { $0 == "," || $0 == "\n" })
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private func gitChangedFiles(in workspacePath: URL) -> [String] {
        guard let result = CodeReviewAuditService.commandOutput(
            executable: "/usr/bin/git",
            arguments: ["status", "--porcelain"],
            currentDirectoryURL: workspacePath
        ), result.status == 0 else {
            return []
        }

        return result.output
            .components(separatedBy: .newlines)
            .compactMap { line -> String? in
                guard line.count > 3 else { return nil }
                return CodeReviewAuditService.normalizedRelativePath(String(line.dropFirst(3)))
            }
            .filter { !$0.isEmpty }
    }
}
