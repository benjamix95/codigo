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
        "review_diff_summary", "review_comment", "review_list_sessions",
        "review_verify_finding", "review_prepare_patch", "review_preview_patch",
        "review_apply_patch", "review_verify_patch", "review_revalidate_finding", "review_rollback_patch", "review_close_finding", "review_open_pr",
        "review_merge_pr", "review_resolve_conflicts", "review_get_outcome",
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
        case "review_list_sessions":
            return handleReviewListSessions(args: args)
        case "review_verify_finding":
            return handleReviewVerifyFinding(args: args)
        case "review_prepare_patch":
            return handleReviewPreparePatch(args: args)
        case "review_preview_patch":
            return handleReviewPreviewPatch(args: args)
        case "review_apply_patch":
            return handleReviewApplyPatch(args: args)
        case "review_verify_patch":
            return handleReviewVerifyPatch(args: args)
        case "review_revalidate_finding":
            return handleReviewRevalidateFinding(args: args)
        case "review_rollback_patch":
            return handleReviewRollbackPatch(args: args)
        case "review_close_finding":
            return handleReviewCloseFinding(args: args)
        case "review_open_pr":
            return handleReviewOpenPR(args: args)
        case "review_merge_pr":
            return handleReviewMergePR(args: args)
        case "review_resolve_conflicts":
            return handleReviewResolveConflicts(args: args)
        case "review_get_outcome":
            return handleReviewGetOutcome(args: args)
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
