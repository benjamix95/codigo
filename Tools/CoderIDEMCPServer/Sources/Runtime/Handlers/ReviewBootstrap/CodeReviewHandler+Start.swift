import CoderEngine
import Foundation
import MCP

extension CoderIDEMCPServerApp {
    static let reviewSessionIdPattern = #"^[A-Za-z0-9][A-Za-z0-9_-]{0,127}$"#
    static let validReviewBackends: Set<String> = [
        "auto", "codex", "claude", "gemini",
        "codex-cli", "claude-cli", "gemini-cli",
        "openrouter", "openrouter-api",
        "minimax", "minimax-api",
        "grok", "grok-api",
        "openai", "openai-api",
        "anthropic", "anthropic-api",
        "google", "google-api",
    ]

    static let codeReviewTools: Set<String> = [
        "review_start", "review_status", "review_findings",
        "review_apply_fix", "review_dismiss", "review_configure",
        "review_diff_summary", "review_comment", "review_list_sessions",
        "review_verify_finding", "review_prepare_patch", "review_preview_patch",
        "review_apply_patch", "review_verify_patch", "review_revalidate_finding",
        "review_rollback_patch", "review_close_finding", "review_open_pr",
        "review_merge_pr", "review_resolve_conflicts", "review_get_outcome",
    ]

    static func handleCodeReviewTool(
        name: String,
        args: [String: String]
    ) -> CallTool.Result? {
        guard codeReviewTools.contains(name) else { return nil }

        switch name {
        case "review_start": return handleReviewStart(args: args)
        case "review_status": return handleReviewStatus(args: args)
        case "review_findings": return handleReviewFindings(args: args)
        case "review_apply_fix": return handleReviewApplyFix(args: args)
        case "review_dismiss": return handleReviewDismiss(args: args)
        case "review_configure": return handleReviewConfigure(args: args)
        case "review_diff_summary": return handleReviewDiffSummary(args: args)
        case "review_comment": return handleReviewComment(args: args)
        case "review_list_sessions": return handleReviewListSessions(args: args)
        case "review_verify_finding": return handleReviewVerifyFinding(args: args)
        case "review_prepare_patch": return handleReviewPreparePatch(args: args)
        case "review_preview_patch": return handleReviewPreviewPatch(args: args)
        case "review_apply_patch": return handleReviewApplyPatch(args: args)
        case "review_verify_patch": return handleReviewVerifyPatch(args: args)
        case "review_revalidate_finding": return handleReviewRevalidateFinding(args: args)
        case "review_rollback_patch": return handleReviewRollbackPatch(args: args)
        case "review_close_finding": return handleReviewCloseFinding(args: args)
        case "review_open_pr": return handleReviewOpenPR(args: args)
        case "review_merge_pr": return handleReviewMergePR(args: args)
        case "review_resolve_conflicts": return handleReviewResolveConflicts(args: args)
        case "review_get_outcome": return handleReviewGetOutcome(args: args)
        default: return reviewError("Unknown code review tool: \(name)")
        }
    }

    static func reviewOK(_ message: String) -> CallTool.Result {
        CallTool.Result(content: [.text(message)], isError: nil)
    }

    static func reviewError(_ message: String) -> CallTool.Result {
        CallTool.Result(content: [.text(message)], isError: true)
    }

    static func validateReviewBackend(_ backend: String) -> Bool {
        validReviewBackends.contains(backend.lowercased())
    }

    static func validateReviewSessionIdFormat(_ sessionId: String) -> String? {
        let trimmed = sessionId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return "Error: 'session_id' must not be empty"
        }
        guard trimmed.range(
            of: reviewSessionIdPattern,
            options: .regularExpression
        ) != nil else {
            return "Error: 'session_id' may contain only letters, digits, '_' or '-' and must not start with punctuation"
        }
        return nil
    }

    static func sanitizedReviewArg(_ args: [String: String], key: String) -> String {
        (args[key] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func fallbackReviewToolResult(
        name: String,
        args: [String: String],
        reviewSnapshots: [CodeReviewSessionSnapshot],
        activeReviewSnapshot: CodeReviewSessionSnapshot?,
        reviewFindingsPayload: [[String: String]],
        reviewStatusPayload: [String: String]?,
        reviewOutcomePayload: [String: String]?
    ) -> CallTool.Result? {
        switch name {
        case "review_status":
            return reviewOK(fallbackReviewStatusText(statusPayload: reviewStatusPayload))
        case "review_findings":
            if let validationError = fallbackValidateReviewFilters(args: args) {
                return reviewError(validationError)
            }
            return reviewOK(
                fallbackReviewFindingsText(
                    activeReviewSnapshot: activeReviewSnapshot,
                    findingsPayload: reviewFindingsPayload
                )
            )
        case "review_list_sessions":
            return reviewOK(fallbackReviewListSessionsText(reviewSnapshots: reviewSnapshots))
        case "review_get_outcome":
            guard let reviewOutcomePayload else {
                return reviewError("Error: unable to load the requested review session")
            }
            return reviewOK(
                fallbackPayloadLines(
                    reviewOutcomePayload,
                    keys: [
                        "summary", "verified_findings", "false_positives", "patches_ready",
                        "patches_applied", "prs_opened", "merged_patches", "conflicts_detected",
                        "manual_action_required", "tests_status",
                    ]
                )
            )
        default:
            return nil
        }
    }

    private static func fallbackReviewStatusText(statusPayload: [String: String]?) -> String {
        guard let statusPayload else { return "No active review session." }
        let rendered = fallbackPayloadLines(
            statusPayload,
            keys: [
                "session_id", "phase", "stage", "summary", "findings_total", "candidates_total",
                "verified_projection_findings", "verified_projection_candidates",
                "verified_projection_duplicates", "verified_projection_stale_candidates",
                "security_gate_ready", "security_gate_summary",
            ]
        )
        return rendered.isEmpty ? "No active review session." : rendered
    }

    private static func fallbackReviewListSessionsText(
        reviewSnapshots: [CodeReviewSessionSnapshot]
    ) -> String {
        guard !reviewSnapshots.isEmpty else { return "No review sessions found." }
        return reviewSnapshots.map { snapshot in
            let scope = snapshot.scope?.type.rawValue ?? "unknown"
            return "\(snapshot.sessionId) | phase=\(snapshot.phase.rawValue) | stage=\(snapshot.stage.rawValue) | scope=\(scope) | findings=\(snapshot.findings.count)"
        }.joined(separator: "\n")
    }

    private static func fallbackPayloadLines(
        _ payload: [String: String],
        keys: [String]
    ) -> String {
        keys.compactMap { key in
            guard let value = payload[key], !value.isEmpty else { return nil }
            return "\(key): \(value)"
        }.joined(separator: "\n")
    }

    static func handleReviewStart(args: [String: String]) -> CallTool.Result {
        do {
            let request = try VerifiedFindingsStartCommandService.makeRequest(
                args: args,
                conversationId: resolveReviewConversationId(args)
            )
            guard let bridged = rustReviewToolResult(
                name: "review_start",
                args: request.payload
            ) else {
                return reviewError("Error: Rust review core unavailable for review_start")
            }
            if bridged.isError == true {
                return bridged
            }
            guard (try? MCPSharedState.enqueueUniqueCodeReviewStartCommandRustOnly(
                sessionId: request.sessionId,
                conversationId: request.conversationId,
                payload: request.payload
            )) != nil else {
                return reviewError("Error: Rust review queue unavailable for review_start")
            }
            return reviewOK(
                "OK — code review start queued (session_id=\(request.sessionId), scope=\(request.scope))"
            )
        } catch let error as VerifiedFindingsStartCommandError {
            switch error {
            case .invalidScope(let scope):
                return reviewError(
                    "Error: invalid scope '\(scope)'. Use: uncommitted, staged, against_ref"
                )
            case .missingRef:
                return reviewError("Error: 'ref' parameter is required when scope=against_ref")
            case .invalidRef(let ref):
                return reviewError("Error: invalid ref '\(ref)'")
            case .invalidMaxWorkers:
                return reviewError("Error: max_workers must be 1-12")
            case .invalidMaxRounds:
                return reviewError("Error: max_rounds must be 1-10")
            case .invalidAnalysisOnly:
                return reviewError("Error: analysis_only must be a boolean value")
            case .invalidBackend(let field, let value):
                return reviewError("Error: invalid \(field) '\(value)'")
            case .invalidSessionId:
                return reviewError(
                    "Error: invalid session_id. Use only letters, numbers, hyphen, or underscore"
                )
            case .sessionAlreadyExists(let sessionId):
                return reviewError("Error: session_id '\(sessionId)' already exists")
            case .sessionAlreadyQueued(let sessionId):
                return reviewError("Error: session_id '\(sessionId)' already has a queued start command")
            }
        } catch {
            return reviewError("Error: failed to queue code review start command")
        }
    }

    static func handleReviewStatus(args: [String: String]) -> CallTool.Result {
        guard let bridged = rustReviewToolResult(name: "review_status", args: args) else {
            return reviewError("Error: Rust review core unavailable for review_status")
        }
        return bridged
    }

    static func handleReviewDiffSummary(args: [String: String]) -> CallTool.Result {
        let originFilter = sanitizedReviewArg(args, key: "origin")
        if !originFilter.isEmpty {
            let validOrigins: Set<String> = ["reviewer", "bugHunter", "securityAuditor", "audit_tool"]
            if !validOrigins.contains(originFilter) {
                return reviewError(
                    "Error: invalid origin '\(originFilter)'. Use: reviewer, bugHunter, securityAuditor, audit_tool"
                )
            }
        }
        let categoryFilter = sanitizedReviewArg(args, key: "category")
        if !categoryFilter.isEmpty {
            let validCategories: Set<String> = [
                "correctness", "regression", "concurrency", "security",
                "tests", "maintainability", "performance", "other",
            ]
            if !validCategories.contains(categoryFilter.lowercased()) {
                return reviewError(
                    "Error: invalid category '\(categoryFilter)'. Use: correctness, regression, concurrency, security, tests, maintainability, performance, other"
                )
            }
        }
        let explicitSessionId = sanitizedReviewArg(
            args,
            key: args["session_id"] != nil ? "session_id" : "sessionId"
        )
        if !explicitSessionId.isEmpty,
           let formatError = validateReviewSessionIdFormat(explicitSessionId) {
            return reviewError(formatError)
        }
        let resolved = resolveReviewSessionId(
            args: args,
            requireExplicitWhenAmbiguous: true
        )
        if let message = resolved.error {
            return reviewError(message)
        }
        guard let sessionId = resolved.sessionId,
              let snapshot = MCPSharedState.readCodeReviewSnapshot(sessionId: sessionId) else {
            return reviewError("Error: unable to load the requested review session")
        }
        let fileFilter = sanitizedReviewArg(args, key: "file")
        let filteredFiles: [String]?
        if originFilter.isEmpty && categoryFilter.isEmpty {
            filteredFiles = nil
        } else {
            filteredFiles = Array(
                Set(
                    snapshot.findings
                        .filter { finding in
                            (originFilter.isEmpty || finding.origin.rawValue == originFilter)
                                && (categoryFilter.isEmpty || finding.category.rawValue == FindingCategory.fromStoredValue(categoryFilter).rawValue)
                        }
                        .map(\.filePath)
                )
            ).sorted()
        }
        let workspacePath = URL(fileURLWithPath: snapshot.workspacePath ?? FileManager.default.currentDirectoryPath)
        let rendered = ReviewDiffSummaryRustBridge.renderSummary(
            snapshot: snapshot,
            workspacePath: workspacePath,
            fileFilter: fileFilter.isEmpty ? nil : fileFilter,
            filteredFiles: filteredFiles
        )
        return reviewOK(rendered ?? "No diff data available for the selected review scope.")
    }

    static func handleReviewListSessions(args: [String: String]) -> CallTool.Result {
        guard let bridged = rustReviewToolResult(name: "review_list_sessions", args: args) else {
            return reviewError("Error: Rust review core unavailable for review_list_sessions")
        }
        return bridged
    }
}
