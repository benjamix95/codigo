import CoderEngine
import Foundation
import MCP
@testable import CoderIDEMCPServer

extension CoderIDEMCPServerApp {
    static func handleReviewStatus(args: [String: String]) -> CallTool.Result {
        let resolved = resolveReviewSessionId(
            args: args,
            requireExplicitWhenAmbiguous: true
        )
        if let error = resolved.error {
            return error == "No active review session." || error == "No review session found."
                ? reviewOK(error)
                : reviewError(error)
        }
        guard let sessionId = resolved.sessionId else {
            return reviewOK("No active review session.")
        }
        guard let bridged = rustReviewToolResult(name: "review_status", args: args) else {
            return reviewError("Error: Rust review core unavailable for review_status")
        }
        return bridged
    }

    static func handleReviewFindings(args: [String: String]) -> CallTool.Result {
        let severity = sanitizedReviewArg(args, key: "severity")
        if !severity.isEmpty {
            let validSeverities: Set<String> = ["critical", "warning", "suggestion", "info"]
            if !validSeverities.contains(severity.lowercased()) {
                return reviewError("Error: invalid severity '\(severity)'")
            }
        }
        let status = sanitizedReviewArg(args, key: "status")
        if !status.isEmpty {
            let validStatuses: Set<String> = [
                "open", "fix_applied", "patch_preparing", "patch_ready", "patch_applying",
                "patch_applied", "patch_failed", "pr_opened", "merged", "dismissed",
                "wont_fix", "closed", "blocked", "candidate", "verified",
                "rejected_false_positive", "inconclusive",
            ]
            if !validStatuses.contains(status.lowercased()) {
                return reviewError("Error: invalid status '\(status)'")
            }
        }
        let origin = sanitizedReviewArg(args, key: "origin")
        if !origin.isEmpty {
            let validOrigins: Set<String> = ["reviewer", "bugHunter", "securityAuditor", "audit_tool"]
            if !validOrigins.contains(origin) {
                return reviewError("Error: invalid origin '\(origin)'")
            }
        }
        let category = sanitizedReviewArg(args, key: "category")
        if !category.isEmpty {
            let validCategories: Set<String> = [
                "correctness", "regression", "concurrency", "security",
                "tests", "maintainability", "performance", "other",
            ]
            if !validCategories.contains(category.lowercased()) {
                return reviewError("Error: invalid category '\(category)'")
            }
        }
        let resolved = resolveReviewSessionId(
            args: args,
            requireExplicitWhenAmbiguous: true
        )
        if let error = resolved.error {
            return error == "No active review session." || error == "No review session found."
                ? reviewOK(error)
                : reviewError(error)
        }
        guard let sessionId = resolved.sessionId else {
            return reviewOK("No active review session.")
        }
        _ = sessionId
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
        if let error = resolved.error {
            return error == "No active review session." || error == "No review session found."
                ? reviewOK(error)
                : reviewError(error)
        }
        guard let sessionId = resolved.sessionId,
              let snapshot = MCPSharedState.readCodeReviewSnapshot(sessionId: sessionId) else {
            return reviewOK("No diff data available")
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
        if let rendered = ReviewDiffSummaryRustBridge.renderSummary(
            snapshot: snapshot,
            workspacePath: workspacePath,
            fileFilter: fileFilter.isEmpty ? nil : fileFilter,
            filteredFiles: filteredFiles
        ) {
            return reviewOK(rendered)
        }
        return reviewOK("No diff data available for session_id: \(sessionId)")
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

    private static func renderReviewStatusPayload(_ payload: [String: String]) -> String {
        payload.keys.sorted().compactMap { key in
            guard let value = payload[key], !value.isEmpty else { return nil }
            return "\(key): \(value)"
        }.joined(separator: "\n")
    }

    private static func renderReviewFindingsPayload(_ payload: [[String: String]]) -> String {
        let lines = payload.enumerated().map { index, finding in
            let severity = finding["severity"] ?? "?"
            let title = finding["message_summary"] ?? finding["message"] ?? "n/a"
            let file = finding["file_label"] ?? finding["file_path"] ?? "redacted"
            let line = finding["line_number"].map { ":\($0)" } ?? ""
            let origin = finding["origin"] ?? "unknown"
            let category = finding["category"] ?? "unknown"
            return "[\(index + 1)] [\(severity)] \(file)\(line) — \(title) (origin: \(origin), category: \(category))"
        }
        return "Findings\n" + lines.joined(separator: "\n")
    }

    private static func optionalReviewArg(
        _ args: [String: String],
        key: String
    ) -> String? {
        let value = sanitizedReviewArg(args, key: key)
        return value.isEmpty ? nil : value
    }
}
