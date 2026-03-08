import Foundation

extension UnifiedToolRuntime {
    func executeAuditTool(
        name: String,
        call: ToolCall,
        context: ToolExecutionContext,
        startDate: Date
    ) async -> ToolResult {
        if let metaResult = executeMetaAuditToolIfNeeded(
            name: name,
            call: call,
            context: context,
            startDate: startDate
        ) {
            return metaResult
        }

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
            "adapters_used": result.adaptersUsed.joined(separator: ","),
            "clusters_count": String(result.clusters.count),
        ], startDate: startDate)
    }

    private func executeMetaAuditToolIfNeeded(
        name: String,
        call: ToolCall,
        context: ToolExecutionContext,
        startDate: Date
    ) -> ToolResult? {
        switch name {
        case ReviewAuditToolName.runProfile:
            let profile = ReviewAuditProfile(rawValue: (call.args["profile"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()) ?? .quick
            let scopeFiles = resolveAuditScopeFiles(call: call, context: context)
            let results = CodeReviewAuditService.runProfile(named: profile, scopeFiles: scopeFiles, workspacePath: context.workspaceContext.workspacePath)
            return encodedAuditResult(
                CodeReviewAuditService.correlateResults(results, summaryPrefix: "audit_run_profile.\(profile.rawValue)"),
                startDate: startDate
            )
        case ReviewAuditToolName.correlateFindings:
            let scopeFiles = resolveAuditScopeFiles(call: call, context: context)
            let results = CodeReviewAuditService.runProfile(named: .securityDeep, scopeFiles: scopeFiles, workspacePath: context.workspaceContext.workspacePath)
                + CodeReviewAuditService.runProfile(named: .bugHuntDeep, scopeFiles: scopeFiles, workspacePath: context.workspaceContext.workspacePath)
            return encodedAuditResult(
                CodeReviewAuditService.correlateResults(results, summaryPrefix: "audit_correlate_findings"),
                startDate: startDate
            )
        case ReviewAuditToolName.verifyBundle:
            let scopeFiles = resolveAuditScopeFiles(call: call, context: context)
            let correlated = CodeReviewAuditService.correlateResults(
                CodeReviewAuditService.runProfile(named: .securityDeep, scopeFiles: scopeFiles, workspacePath: context.workspaceContext.workspacePath)
                    + CodeReviewAuditService.runProfile(named: .bugHuntDeep, scopeFiles: scopeFiles, workspacePath: context.workspaceContext.workspacePath),
                summaryPrefix: "audit_verify_bundle"
            )
            let strict = ReviewAuditToolResult(
                toolName: ReviewAuditToolName.verifyBundle,
                findings: correlated.findings.filter { ($0.confidence ?? 0) >= 0.75 || $0.blocking },
                durationMs: correlated.durationMs,
                coverageAvailable: correlated.coverageAvailable,
                summary: correlated.summary,
                adaptersUsed: correlated.adaptersUsed,
                verificationHints: correlated.verificationHints,
                metadata: correlated.metadata,
                clusters: correlated.clusters
            )
            return encodedAuditResult(strict, startDate: startDate)
        case ReviewAuditToolName.explainFinding:
            let file = (call.args["file"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let message = (call.args["message"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !file.isEmpty, !message.isEmpty else {
                return failure("file and message are required", errorCode: "validation", startDate: startDate)
            }
            let evidence = (call.args["evidence"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let line = (call.args["line"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let summary = """
            file: \(file)
            line: \(line.isEmpty ? "n/a" : line)
            message: \(message)
            evidence: \(evidence.isEmpty ? "n/a" : evidence)
            gate: strict_verified
            """
            let result = ReviewAuditToolResult(
                toolName: ReviewAuditToolName.explainFinding,
                findings: [],
                durationMs: 1,
                coverageAvailable: true,
                summary: summary,
                metadata: ["signal_type": "manual", "verification_hint": "explanation_only", "promotion_gate": "none"]
            )
            return encodedAuditResult(result, startDate: startDate)
        default:
            return nil
        }
    }

    private func encodedAuditResult(
        _ result: ReviewAuditToolResult,
        startDate: Date
    ) -> ToolResult {
        let payloadData = (try? JSONEncoder().encode(result.payload)) ?? Data("{}".utf8)
        let output = String(data: payloadData, encoding: .utf8) ?? "{}"
        return success([
            "title": result.toolName,
            "detail": result.summary,
            "output": output,
            "findings_count": String(result.findings.count),
            "blocking_findings": String(result.blockingFindingsCount),
            "coverage_available": result.coverageAvailable ? "true" : "false",
            "adapters_used": result.adaptersUsed.joined(separator: ","),
            "clusters_count": String(result.clusters.count),
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
