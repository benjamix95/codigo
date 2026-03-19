import CoderEngine
import Foundation
import MCP
@testable import CoderIDEMCPServer

extension CoderIDEMCPServerApp {
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
        let validReviewBackends: Set<String> = [
            "auto", "codex", "claude", "gemini",
            "codex-cli", "claude-cli", "gemini-cli",
            "openrouter", "openrouter-api",
            "minimax", "minimax-api",
            "grok", "grok-api",
            "openai", "openai-api",
            "anthropic", "anthropic-api",
            "google", "google-api",
        ]
        return validReviewBackends.contains(backend.lowercased())
    }

    static func validateReviewSessionIdFormat(_ sessionId: String) -> String? {
        let trimmed = sessionId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return "Error: 'session_id' must not be empty"
        }
        let pattern = #"^[A-Za-z0-9][A-Za-z0-9_-]{0,127}$"#
        guard trimmed.range(of: pattern, options: .regularExpression) != nil else {
            return "Error: 'session_id' may contain only letters, digits, '_' or '-' and must not start with punctuation"
        }
        return nil
    }

    static func sanitizedReviewArg(_ args: [String: String], key: String) -> String {
        (args[key] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
