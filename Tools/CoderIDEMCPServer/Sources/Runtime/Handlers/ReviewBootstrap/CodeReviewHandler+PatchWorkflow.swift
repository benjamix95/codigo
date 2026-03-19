import CoderEngine
import Foundation
import MCP

extension CoderIDEMCPServerApp {
    static func reviewCommandQueued(
        action: String,
        sessionId: String?,
        args: [String: String]
    ) -> CallTool.Result {
        guard let command = MCPSharedState.enqueueCodeReviewCommandRustOnly(
            action: action,
            sessionId: sessionId,
            conversationId: resolveReviewConversationId(args),
            payload: args
        ) else {
            return reviewError("Error: Rust review queue unavailable for review_\(action)")
        }
        var parts = ["OK — review command queued", "action=\(action)", "command_id=\(command.id)"]
        if let sessionId, !sessionId.isEmpty {
            parts.append("session_id=\(sessionId)")
        }
        return reviewOK(parts.joined(separator: ", "))
    }

    static func validateReviewSessionAccess(
        sessionId: String,
        args: [String: String]
    ) -> String? {
        if let formatError = validateReviewSessionIdFormat(sessionId) {
            return formatError
        }
        guard let snapshot = MCPSharedState.readCodeReviewSnapshot(sessionId: sessionId) else {
            return "Error: session_id '\(sessionId)' was not found"
        }
        if let snapshotConversationId = snapshot.conversationId {
            guard let conversationId = resolveReviewConversationId(args) else {
                return "Error: 'conversation_id' is required for session_id '\(sessionId)'"
            }
            guard snapshotConversationId == conversationId else {
                return "Error: session_id '\(sessionId)' does not belong to the requested conversation"
            }
        }
        return nil
    }

    static func validateFindingOwnership(
        sessionId: String,
        findingId: String,
        args: [String: String]
    ) -> String? {
        if let accessError = validateReviewSessionAccess(sessionId: sessionId, args: args) {
            return accessError
        }
        guard let snapshot = MCPSharedState.readCodeReviewSnapshot(sessionId: sessionId) else {
            return "Error: session_id '\(sessionId)' was not found"
        }
        guard snapshot.findings.contains(where: { $0.id == findingId })
            || snapshot.candidates.contains(where: { $0.id == findingId })
        else {
            return "Error: finding_id '\(findingId)' does not belong to session_id '\(sessionId)'"
        }
        return nil
    }

    static func handleReviewVerifyFinding(args: [String: String]) -> CallTool.Result {
        queueFindingScopedReviewCommand(action: "verify_finding", args: args)
    }

    static func handleReviewPreparePatch(args: [String: String]) -> CallTool.Result {
        queueFindingScopedReviewCommand(action: "prepare_patch", args: args)
    }

    static func handleReviewApplyPatch(args: [String: String]) -> CallTool.Result {
        if let bridged = rustReviewToolResult(name: "review_apply_patch", args: args) {
            if bridged.isError == true {
                return bridged
            }
            let findingId = sanitizedReviewArg(args, key: "finding_id")
            let sessionId = sanitizedReviewArg(args, key: args["session_id"] != nil ? "session_id" : "sessionId")
            guard !findingId.isEmpty, !sessionId.isEmpty else {
                return reviewError("Error: 'finding_id' and 'session_id' are required")
            }
            guard MCPSharedState.enqueueCodeReviewCommandRustOnly(
                action: "apply_patch",
                sessionId: sessionId,
                conversationId: resolveReviewConversationId(args),
                payload: args
            ) != nil else {
                return reviewError("Error: Rust review queue unavailable for review_apply_patch")
            }
            return bridged
        }
        return reviewError("Error: Rust review core unavailable for review_apply_patch")
    }

    static func handleReviewVerifyPatch(args: [String: String]) -> CallTool.Result {
        queueFindingScopedReviewCommand(action: "verify_patch", args: args)
    }

    static func handleReviewRevalidateFinding(args: [String: String]) -> CallTool.Result {
        queueFindingScopedReviewCommand(action: "revalidate_finding", args: args)
    }

    static func handleReviewRollbackPatch(args: [String: String]) -> CallTool.Result {
        queueFindingScopedReviewCommand(action: "rollback_patch", args: args)
    }

    static func handleReviewCloseFinding(args: [String: String]) -> CallTool.Result {
        queueFindingScopedReviewCommand(action: "close_finding", args: args)
    }

    static func handleReviewOpenPR(args: [String: String]) -> CallTool.Result {
        queueFindingScopedReviewCommand(action: "open_pr", args: args)
    }

    static func handleReviewMergePR(args: [String: String]) -> CallTool.Result {
        queueFindingScopedReviewCommand(action: "merge_pr", args: args)
    }

    static func handleReviewResolveConflicts(args: [String: String]) -> CallTool.Result {
        queueFindingScopedReviewCommand(action: "resolve_conflicts", args: args)
    }

    static func handleReviewPreviewPatch(args: [String: String]) -> CallTool.Result {
        let findingId = sanitizedReviewArg(args, key: "finding_id")
        let sessionId = sanitizedReviewArg(args, key: args["session_id"] != nil ? "session_id" : "sessionId")
        guard !findingId.isEmpty, !sessionId.isEmpty else {
            return reviewError("Error: 'finding_id' e 'session_id' sono obbligatori")
        }
        if let ownershipError = validateFindingOwnership(sessionId: sessionId, findingId: findingId, args: args) {
            return reviewError(ownershipError)
        }
        guard let snapshot = MCPSharedState.readCodeReviewSnapshot(sessionId: sessionId),
              let patch = snapshot.patches.first(where: { $0.findingId == findingId }) else {
            return reviewOK("No patch artifact available for the requested finding.")
        }
        let finding = snapshot.findings.first(where: { $0.id == findingId })
        let details = [
            "finding_id: \(findingId)",
            "severity: \(finding?.severity.rawValue ?? "unknown")",
            "category: \(finding?.category.rawValue ?? "unknown")",
            "message: \(finding?.message ?? "n/a")",
            "verification_report: \(finding?.verificationReport ?? patch.verificationReport ?? "n/a")",
            "patch_id: \(patch.id)",
            "status: \(patch.status.rawValue)",
            "verify_status: \(patch.verifyStatus.rawValue)",
            "validation_status: \(patch.validationStatus.rawValue)",
            "validation_run_id: \(patch.validationRunId ?? "n/a")",
            "validation_summary: \(patch.validationSummary ?? "n/a")",
            "files: \(patch.touchedFiles.joined(separator: ", "))",
            "risk_score: \(String(format: "%.2f", patch.riskScore))",
            "diff_preview:",
            patch.diffPreview,
        ]
        return reviewOK(details.joined(separator: "\n"))
    }

    static func handleReviewGetOutcome(args: [String: String]) -> CallTool.Result {
        guard let bridged = rustReviewToolResult(name: "review_get_outcome", args: args) else {
            return reviewError("Error: Rust review core unavailable for review_get_outcome")
        }
        return bridged
    }

    private static func queueFindingScopedReviewCommand(
        action: String,
        args: [String: String]
    ) -> CallTool.Result {
        let toolName = reviewToolName(for: action)
        if let bridged = rustReviewToolResult(name: toolName, args: args) {
            if bridged.isError == true {
                return bridged
            }
            let findingId = sanitizedReviewArg(args, key: "finding_id")
            let sessionId = sanitizedReviewArg(args, key: args["session_id"] != nil ? "session_id" : "sessionId")
            guard !findingId.isEmpty, !sessionId.isEmpty else {
                return reviewError("Error: 'finding_id' and 'session_id' are required")
            }
            guard MCPSharedState.enqueueCodeReviewCommandRustOnly(
                action: action,
                sessionId: sessionId,
                conversationId: resolveReviewConversationId(args),
                payload: args
            ) != nil else {
                return reviewError("Error: Rust review queue unavailable for \(toolName)")
            }
            return bridged
        }
        return reviewError("Error: Rust review core unavailable for \(toolName)")
    }

    private static func reviewToolName(for action: String) -> String {
        switch action {
        case "verify_finding": return "review_verify_finding"
        case "prepare_patch": return "review_prepare_patch"
        case "verify_patch": return "review_verify_patch"
        case "revalidate_finding": return "review_revalidate_finding"
        case "rollback_patch": return "review_rollback_patch"
        case "close_finding": return "review_close_finding"
        case "open_pr": return "review_open_pr"
        case "merge_pr": return "review_merge_pr"
        case "resolve_conflicts": return "review_resolve_conflicts"
        default: return "review_\(action)"
    }
    }

    private static func reviewLifecycleErrorMessage(_ error: Error) -> String {
        guard let lifecycleError = error as? VerifiedFindingsLifecycleCommandError else {
            return error.localizedDescription
        }
        switch lifecycleError {
        case .missingIdentifiers:
            return "Error: 'finding_id' and 'session_id' are required"
        case .sessionNotFound(let sessionId):
            return "Error: session_id '\(sessionId)' was not found"
        case .conversationRequired(let sessionId):
            return "Error: 'conversation_id' is required for session_id '\(sessionId)'"
        case .conversationMismatch(let sessionId):
            return "Error: session_id '\(sessionId)' does not belong to the requested conversation"
        case .findingNotOwned(let findingId, let sessionId):
            return "Error: finding_id '\(findingId)' does not belong to session_id '\(sessionId)'"
        case .missingPreparedPatch:
            return "Error: no prepared patch artifact found. Run review_prepare_patch first."
        case .patchNotVerified:
            return "Error: patch artifact is not verified. Run review_prepare_patch or review_verify_patch first."
        case .findingNotClosable:
            return "Error: finding cannot be closed until it is merged, dismissed, or validated after apply."
        case .rustPatchQueueContextUnavailable(let message):
            return "Error: \(message)"
        case .rustReviewQueueUnavailable(let message):
            return "Error: \(message)"
        }
    }
}
