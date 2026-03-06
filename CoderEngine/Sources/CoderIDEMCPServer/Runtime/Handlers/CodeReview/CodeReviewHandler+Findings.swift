import CoderEngine
import Foundation
import MCP

extension CoderIDEMCPServerApp {
    static func handleReviewFindings(args: [String: String]) -> CallTool.Result {
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
            let validStatuses: Set<String> = ["open", "fix_applied", "dismissed", "wont_fix"]
            if !validStatuses.contains(status) {
                return reviewError(
                    "Error: invalid status '\(status)'. Use: open, fix_applied, dismissed, wont_fix"
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

        let resolved = resolveReviewSessionId(args: args, requireExplicitWhenAmbiguous: true)
        if let message = resolved.error {
            return reviewError(message)
        }
        guard let sessionId = resolved.sessionId else {
            return reviewError("No active review session.")
        }

        let limitVal = Int(args["limit"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "") ?? 50
        let findings = MCPSharedState.readCodeReviewFindings(
            sessionId: sessionId,
            severity: severity.isEmpty ? nil : severity,
            status: status.isEmpty ? nil : status,
            file: args["file"]?.trimmingCharacters(in: .whitespacesAndNewlines),
            limit: limitVal
        )
        if findings.isEmpty {
            return reviewOK("No findings match the query.")
        }
        let lines = findings.enumerated().map { idx, f in
            let id = f["id"] ?? "?"
            let sev = f["severity"] ?? "?"
            let file = f["file_path"] ?? "?"
            let msg = f["message"] ?? ""
            let st = f["status"] ?? "open"
            return "[\(idx + 1)] [\(sev)] \(file) — \(msg) (status: \(st), id: \(id))"
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

        return reviewCommandQueued(action: "comment", sessionId: sessionId, args: args)
    }
}
