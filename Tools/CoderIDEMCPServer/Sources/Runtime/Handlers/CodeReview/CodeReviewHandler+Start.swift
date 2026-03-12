import CoderEngine
import Foundation
import MCP

extension CoderIDEMCPServerApp {
    static func handleReviewStart(args: [String: String]) -> CallTool.Result {
        guard let bridged = rustReviewToolResult(name: "review_start", args: args) else {
            return reviewError("Error: Rust review core unavailable for review_start")
        }
        if bridged.isError == true {
            return bridged
        }
        do {
            let request = try VerifiedFindingsStartCommandService.makeRequest(
                args: args,
                conversationId: resolveReviewConversationId(args)
            )
            _ = try VerifiedFindingsStartCommandService.enqueueReviewStart(request: request)
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
        let rendered = ReviewDiffSummaryService.renderSummary(
            snapshot: snapshot,
            workspacePath: workspacePath,
            fileFilter: fileFilter.isEmpty ? nil : fileFilter,
            filteredFiles: filteredFiles
        )
        return reviewOK(rendered)
    }

    static func handleReviewListSessions(args: [String: String]) -> CallTool.Result {
        guard let bridged = rustReviewToolResult(name: "review_list_sessions", args: args) else {
            return reviewError("Error: Rust review core unavailable for review_list_sessions")
        }
        return bridged
    }
}
