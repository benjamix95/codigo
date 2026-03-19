import CoderEngine
import Foundation
import MCP
@testable import CoderIDEMCPServer

extension CoderIDEMCPServerApp {
    static func handleReviewStatus(args: [String: String]) -> CallTool.Result {
        guard let bridged = rustReviewToolResult(name: "review_status", args: args) else {
            return reviewError("Error: Rust review core unavailable for review_status")
        }
        return bridged
    }

    static func handleReviewFindings(args: [String: String]) -> CallTool.Result {
        guard let bridged = rustReviewToolResult(name: "review_findings", args: args) else {
            return reviewError("Error: Rust review core unavailable for review_findings")
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
        guard let rendered = ReviewDiffSummaryRustBridge.renderSummary(
            snapshot: snapshot,
            workspacePath: workspacePath,
            fileFilter: fileFilter.isEmpty ? nil : fileFilter,
            filteredFiles: filteredFiles
        ) else {
            return reviewError("Error: Rust review core unavailable for review_diff_summary")
        }
        return reviewOK(rendered)
    }

    static func handleReviewListSessions(args: [String: String]) -> CallTool.Result {
        guard let bridged = rustReviewToolResult(name: "review_list_sessions", args: args) else {
            return reviewError("Error: Rust review core unavailable for review_list_sessions")
        }
        return bridged
    }

    static func handleReviewGetOutcome(args: [String: String]) -> CallTool.Result {
        guard let bridged = rustReviewToolResult(name: "review_get_outcome", args: args) else {
            return reviewError("Error: Rust review core unavailable for review_get_outcome")
        }
        return bridged
    }
}
