import CoderEngine
import Foundation
import MCP

extension CoderIDEMCPServerApp {
    static func fallbackReviewFindingsText(
        activeReviewSnapshot: CodeReviewSessionSnapshot?,
        findingsPayload: [[String: String]]
    ) -> String {
        guard activeReviewSnapshot != nil else { return "No active review session." }
        guard !findingsPayload.isEmpty else { return "No findings match the query." }
        let lines = findingsPayload.enumerated().map { index, finding in
            let message = finding["message"] ?? finding["message_summary"] ?? "Redacted finding details"
            let file = finding["file_path"] ?? finding["file_label"] ?? "redacted-file"
            let lineSuffix = finding["line_number"].map { ":\($0)" } ?? ""
            let kind = finding["kind"] ?? "verified"
            let severity = finding["severity"] ?? "?"
            let domain = finding["domain"] ?? "bug"
            let origin = finding["origin"] ?? "reviewer"
            let category = finding["category"] ?? "unknown"
            let status = finding["status"] ?? "open"
            let duplicate = finding["possible_duplicate_of"].map { ", duplicate_of: \($0)" } ?? ""
            let stale = finding["stale_status"].map { ", stale: \($0)" } ?? ""
            let identifier = finding["id"] ?? "?"
            return "[\(index + 1)] [\(kind)] [\(severity)] \(file)\(lineSuffix) — \(message) (domain: \(domain), origin: \(origin), category: \(category), status: \(status)\(duplicate)\(stale), id: \(identifier))"
        }
        return "Findings (\(findingsPayload.count)):\n" + lines.joined(separator: "\n")
    }

    static func fallbackValidateReviewFilters(args: [String: String]) -> String? {
        let severity = sanitizedReviewArg(args, key: "severity").lowercased()
        if !severity.isEmpty,
           !["critical", "warning", "suggestion", "info"].contains(severity) {
            return "Error: invalid severity '\(severity)'. Use: critical, warning, suggestion, info"
        }
        let status = sanitizedReviewArg(args, key: "status").lowercased()
        if !status.isEmpty,
           ![
               "open", "fix_applied", "patch_preparing", "patch_ready", "patch_applying",
               "patch_applied", "patch_failed", "pr_opened", "merged", "blocked",
               "dismissed", "wont_fix", "new", "verifying", "verified",
               "rejected_false_positive", "inconclusive",
           ].contains(status) {
            return "Error: invalid status '\(status)' for code review items"
        }
        let origin = sanitizedReviewArg(args, key: "origin")
        if !origin.isEmpty,
           !["reviewer", "bugHunter", "securityAuditor", "audit_tool"].contains(origin) {
            return "Error: invalid origin '\(origin)'. Use: reviewer, bugHunter, securityAuditor, audit_tool"
        }
        let category = sanitizedReviewArg(args, key: "category").lowercased()
        if !category.isEmpty,
           ![
               "correctness", "regression", "concurrency", "security", "tests",
               "maintainability", "performance", "other",
           ].contains(category) {
            return "Error: invalid category '\(category)'. Use: correctness, regression, concurrency, security, tests, maintainability, performance, other"
        }
        return nil
    }

    static func handleReviewFindings(args: [String: String]) -> CallTool.Result {
        guard let bridged = rustReviewToolResult(name: "review_findings", args: args) else {
            return reviewError("Error: Rust review core unavailable for review_findings")
        }
        return bridged
    }

    static func handleReviewApplyFix(args: [String: String]) -> CallTool.Result {
        let findingId = sanitizedReviewArg(args, key: "finding_id")
        if findingId.isEmpty {
            return reviewError("Error: 'finding_id' parameter is required")
        }
        let sessionId = sanitizedReviewArg(
            args,
            key: args["session_id"] != nil ? "session_id" : "sessionId"
        )
        guard !sessionId.isEmpty else {
            return reviewError("Error: 'session_id' parameter is required")
        }
        if let ownershipError = validateFindingOwnership(
            sessionId: sessionId,
            findingId: findingId,
            args: args
        ) {
            return reviewError(ownershipError)
        }
        return reviewCommandQueued(action: "apply_fix", sessionId: sessionId, args: args)
    }

    static func handleReviewDismiss(args: [String: String]) -> CallTool.Result {
        let findingId = sanitizedReviewArg(args, key: "finding_id")
        if findingId.isEmpty {
            return reviewError("Error: 'finding_id' parameter is required")
        }

        let reason = sanitizedReviewArg(args, key: "reason")
        let validReasons: Set<String> = [
            "false_positive", "wont_fix", "by_design", "duplicate", "",
        ]
        if !validReasons.contains(reason.lowercased()) {
            return reviewError(
                "Error: invalid reason '\(reason)'. Use: false_positive, wont_fix, by_design, duplicate"
            )
        }

        let effectiveReason = reason.isEmpty ? "dismissed" : reason
        let sessionId = sanitizedReviewArg(
            args,
            key: args["session_id"] != nil ? "session_id" : "sessionId"
        )
        guard !sessionId.isEmpty else {
            return reviewError("Error: 'session_id' parameter is required")
        }
        var payload = args
        payload["reason"] = effectiveReason
        if let ownershipError = validateFindingOwnership(
            sessionId: sessionId,
            findingId: findingId,
            args: payload
        ) {
            return reviewError(ownershipError)
        }
        return reviewCommandQueued(action: "dismiss", sessionId: sessionId, args: payload)
    }

    static func handleReviewConfigure(args: [String: String]) -> CallTool.Result {
        var updates: [String] = []

        if let maxWorkersStr = args["max_workers"],
           !maxWorkersStr.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            guard let val = Int(maxWorkersStr.trimmingCharacters(in: .whitespacesAndNewlines)),
                  (1...12).contains(val) else {
                return reviewError("Error: max_workers must be 1-12")
            }
            updates.append("max_workers=\(val)")
        }

        if let maxRoundsStr = args["max_rounds"],
           !maxRoundsStr.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            guard let val = Int(maxRoundsStr.trimmingCharacters(in: .whitespacesAndNewlines)),
                  (1...10).contains(val) else {
                return reviewError("Error: max_rounds must be 1-10")
            }
            updates.append("max_rounds=\(val)")
        }

        if let backend = args["analysis_backend"],
           !backend.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            guard validateReviewBackend(backend.trimmingCharacters(in: .whitespacesAndNewlines)) else {
                return reviewError("Error: invalid analysis_backend '\(backend)'")
            }
            updates.append("analysis_backend=\(backend.trimmingCharacters(in: .whitespacesAndNewlines))")
        }

        if let backend = args["execution_backend"],
           !backend.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            guard validateReviewBackend(backend.trimmingCharacters(in: .whitespacesAndNewlines)) else {
                return reviewError("Error: invalid execution_backend '\(backend)'")
            }
            updates.append("execution_backend=\(backend.trimmingCharacters(in: .whitespacesAndNewlines))")
        }

        if let analysisOnly = args["analysis_only"],
           !analysisOnly.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let normalized = analysisOnly.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let validValues = ["1", "0", "true", "false", "yes", "no", "y", "n"]
            guard validValues.contains(normalized) else {
                return reviewError("Error: analysis_only must be a boolean value")
            }
            updates.append("analysis_only=\(normalized)")
        }

        if updates.isEmpty {
            return reviewError("Error: at least one configuration parameter is required")
        }

        let sessionId = sanitizedReviewArg(
            args,
            key: args["session_id"] != nil ? "session_id" : "sessionId"
        )
        guard !sessionId.isEmpty else {
            return reviewError("Error: 'session_id' parameter is required")
        }
        if let accessError = validateReviewSessionAccess(sessionId: sessionId, args: args) {
            return reviewError(accessError)
        }

        return reviewCommandQueued(action: "configure", sessionId: sessionId, args: args)
    }

    static func handleReviewComment(args: [String: String]) -> CallTool.Result {
        let findingId = sanitizedReviewArg(args, key: "finding_id")
        if findingId.isEmpty {
            return reviewError("Error: 'finding_id' parameter is required")
        }

        let content = sanitizedReviewArg(args, key: "content")
        if content.isEmpty {
            return reviewError("Error: 'content' parameter is required")
        }

        let sessionId = sanitizedReviewArg(
            args,
            key: args["session_id"] != nil ? "session_id" : "sessionId"
        )
        guard !sessionId.isEmpty else {
            return reviewError("Error: 'session_id' parameter is required")
        }
        if let ownershipError = validateFindingOwnership(
            sessionId: sessionId,
            findingId: findingId,
            args: args
        ) {
            return reviewError(ownershipError)
        }

        return reviewCommandQueued(action: "comment", sessionId: sessionId, args: args)
    }
}
