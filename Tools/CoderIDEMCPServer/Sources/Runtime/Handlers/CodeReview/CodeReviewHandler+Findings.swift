import CoderEngine
import Foundation
import MCP

extension CoderIDEMCPServerApp {
    static func handleReviewFindings(args: [String: String]) -> CallTool.Result {
        if let bridged = rustReviewToolResult(name: "review_findings", args: args) {
            return bridged
        }
        if hasInvalidConversationIdArgument(args["conversation_id"] ?? args["conversationId"]) {
            return reviewError("Error: 'conversation_id' must be a valid UUID")
        }
        // Validate optional filters
        let severity = sanitizedReviewArg(args, key: "severity").lowercased()
        if !severity.isEmpty {
            let validSeverities: Set<String> = ["critical", "warning", "suggestion", "info"]
            if !validSeverities.contains(severity) {
                return reviewError(
                    "Error: invalid severity '\(severity)'. Use: critical, warning, suggestion, info"
                )
            }
        }

        let status = sanitizedReviewArg(args, key: "status").lowercased()
        if !status.isEmpty {
            let validStatuses: Set<String> = [
                "open", "fix_applied", "patch_preparing", "patch_ready", "patch_applying",
                "patch_applied", "patch_failed", "pr_opened", "merged", "blocked",
                "dismissed", "wont_fix", "new", "verifying", "verified",
                "rejected_false_positive", "inconclusive",
            ]
            if !validStatuses.contains(status) {
                return reviewError(
                    "Error: invalid status '\(status)' for code review items"
                )
            }
        }

        let kind = sanitizedReviewArg(args, key: "kind").lowercased()
        if !kind.isEmpty && !["verified", "candidate", "candidates", "all"].contains(kind) {
            return reviewError("Error: invalid kind '\(kind)'. Use: verified, candidate, all")
        }

        let origin = sanitizedReviewArg(args, key: "origin")
        if !origin.isEmpty {
            let validOrigins: Set<String> = ["reviewer", "bugHunter", "securityAuditor", "audit_tool"]
            if !validOrigins.contains(origin) {
                return reviewError(
                    "Error: invalid origin '\(origin)'. Use: reviewer, bugHunter, securityAuditor, audit_tool"
                )
            }
        }

        let category = sanitizedReviewArg(args, key: "category")
        if !category.isEmpty {
            let validCategories: Set<String> = [
                "correctness", "regression", "concurrency", "security",
                "tests", "maintainability", "performance", "other",
            ]
            let normalizedCategory = category.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if !validCategories.contains(normalizedCategory) {
                return reviewError(
                    "Error: invalid category '\(category)'. Use: correctness, regression, concurrency, security, tests, maintainability, performance, other"
                )
            }
        }

        if let limitStr = args["limit"],
           !limitStr.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            guard let val = Int(limitStr.trimmingCharacters(in: .whitespacesAndNewlines)),
                  val > 0 else {
                return reviewError("Error: limit must be a positive integer")
            }
        }

        let resolved = resolveReviewSessionId(
            args: args,
            requireExplicitWhenAmbiguous: true,
            activeOnly: true
        )
        if let message = resolved.error {
            return message == "No review session found." || message == "No active review session."
                ? reviewOK(message)
                : reviewError(message)
        }
        guard let sessionId = resolved.sessionId else {
            return reviewOK("No active review session.")
        }

        let limitVal = Int(args["limit"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "") ?? 50
        let findings = MCPSharedState.readCodeReviewFindings(
            sessionId: sessionId,
            kind: kind.isEmpty ? "verified" : kind,
            severity: severity.isEmpty ? nil : severity,
            status: status.isEmpty ? nil : status,
            origin: origin.isEmpty ? nil : origin,
            category: category.isEmpty ? nil : category,
            file: args["file"]?.trimmingCharacters(in: .whitespacesAndNewlines),
            limit: limitVal,
            includeSensitiveDetails: false
        )
        if findings.isEmpty {
            return reviewOK("No findings match the query.")
        }
        let lines = findings.enumerated().map { idx, f in
            let id = f["id"] ?? "?"
            let sev = f["severity"] ?? "?"
            let category = f["category"] ?? "unknown"
            let origin = f["origin"] ?? "reviewer"
            let st = f["status"] ?? "open"
            let kind = f["kind"] ?? "verified"
            let domain = f["domain"] ?? "bug"
            let staleStatus = f["stale_status"].map { ", stale: \($0)" } ?? ""
            let duplicateOf = f["possible_duplicate_of"].map { ", duplicate_of: \($0)" } ?? ""
            let mergedInto = f["merged_into_finding_id"].map { ", merged_into: \($0)" } ?? ""
            let file = f["file_path"] ?? f["file_label"] ?? "redacted-file"
            let line = f["line_number"].map { ":\($0)" } ?? ""
            let message = f["message"] ?? f["message_summary"] ?? "Redacted finding details"
            let blocking = f["blocking"] == "true" ? ", blocking: true" : ""
            let confidence = f["confidence"].map { ", confidence: \($0)" } ?? ""
            return "[\(idx + 1)] [\(kind)] [\(sev)] \(file)\(line) — \(message) (domain: \(domain), origin: \(origin), category: \(category), status: \(st)\(blocking)\(confidence)\(staleStatus)\(duplicateOf)\(mergedInto), id: \(id))"
        }
        return reviewOK("Findings (\(findings.count)):\n" + lines.joined(separator: "\n"))
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
