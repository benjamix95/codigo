import Foundation
import MCP

/// Routes code review MCP tool calls to specific handlers.
/// Follows the IDE state tool pattern — pass-through validation with
/// actual state management on the UI side via stream event pipeline.
extension CoderIDEMCPServerApp {
    /// Runtime-stripped tool names for routing (without `coderide_` prefix).
    /// Tool definitions with full MCP schemas are in CoderIDETools+CodeReview.swift.
    static let codeReviewTools: Set<String> = [
        "review_start", "review_status", "review_findings",
        "review_apply_fix", "review_dismiss", "review_configure",
        "review_diff_summary", "review_comment",
    ]

    static func handleCodeReviewTool(
        name: String,
        args: [String: String]
    ) -> CallTool.Result? {
        guard codeReviewTools.contains(name) else { return nil }

        switch name {
        case "review_start":
            return handleReviewStart(args: args)
        case "review_status":
            return handleReviewStatus(args: args)
        case "review_findings":
            return handleReviewFindings(args: args)
        case "review_apply_fix":
            return handleReviewApplyFix(args: args)
        case "review_dismiss":
            return handleReviewDismiss(args: args)
        case "review_configure":
            return handleReviewConfigure(args: args)
        case "review_diff_summary":
            return handleReviewDiffSummary(args: args)
        case "review_comment":
            return handleReviewComment(args: args)
        default:
            return reviewError("Unknown code review tool: \(name)")
        }
    }

    // MARK: - Helpers

    static func reviewOK(_ message: String) -> CallTool.Result {
        CallTool.Result(content: [.text(message)], isError: nil)
    }

    static func reviewError(_ message: String) -> CallTool.Result {
        CallTool.Result(content: [.text(message)], isError: true)
    }

    static func sanitizedReviewArg(_ args: [String: String], key: String) -> String {
        (args[key] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
