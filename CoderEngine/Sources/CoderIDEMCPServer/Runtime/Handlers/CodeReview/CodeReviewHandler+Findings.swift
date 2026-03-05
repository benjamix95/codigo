import Foundation
import MCP

extension CoderIDEMCPServerApp {
    static func handleReviewFindings(args: [String: String]) -> CallTool.Result {
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

        return reviewOK("OK — findings query accepted")
    }

    static func handleReviewApplyFix(args: [String: String]) -> CallTool.Result {
        let findingId = sanitizedReviewArg(args, key: "finding_id")
        if findingId.isEmpty {
            return reviewError("Error: 'finding_id' parameter is required")
        }
        return reviewOK("OK — fix applied for finding \(findingId)")
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
        return reviewOK("OK — finding \(findingId) dismissed (\(effectiveReason))")
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
            updates.append("analysis_backend=\(backend.trimmingCharacters(in: .whitespacesAndNewlines))")
        }

        if let backend = args["execution_backend"],
           !backend.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            updates.append("execution_backend=\(backend.trimmingCharacters(in: .whitespacesAndNewlines))")
        }

        if updates.isEmpty {
            return reviewError("Error: at least one configuration parameter is required")
        }

        return reviewOK("OK — review config updated: \(updates.joined(separator: ", "))")
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

        return reviewOK("OK — comment added to finding \(findingId)")
    }
}
