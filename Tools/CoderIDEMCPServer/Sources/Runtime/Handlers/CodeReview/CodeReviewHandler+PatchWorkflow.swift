import CoderEngine
import Foundation
import MCP

extension CoderIDEMCPServerApp {
    static func handleReviewVerifyFinding(args: [String: String]) -> CallTool.Result {
        queueFindingScopedReviewCommand(action: "verify_finding", args: args)
    }

    static func handleReviewPreparePatch(args: [String: String]) -> CallTool.Result {
        queueFindingScopedReviewCommand(action: "prepare_patch", args: args)
    }

    static func handleReviewApplyPatch(args: [String: String]) -> CallTool.Result {
        let findingId = sanitizedReviewArg(args, key: "finding_id")
        let sessionId = sanitizedReviewArg(args, key: args["session_id"] != nil ? "session_id" : "sessionId")
        guard !findingId.isEmpty, !sessionId.isEmpty else {
            return reviewError("Error: 'finding_id' and 'session_id' are required")
        }
        do {
            let queued = try VerifiedFindingsLifecycleCommandService.queueApplyPatchCommand(
                sessionId: sessionId,
                findingId: findingId,
                conversationId: resolveReviewConversationId(args),
                payload: args
            )
            var parts = [
                "OK — review command queued",
                "action=apply_patch",
                "command_id=\(queued.commandId)",
                "session_id=\(queued.sessionId)",
            ]
            if let patchId = queued.patchId {
                parts.append("patch_id=\(patchId)")
            }
            if let verifyStatus = queued.patchVerifyStatus {
                parts.append("verify_status=\(verifyStatus)")
            }
            if let riskScore = queued.patchRiskScore {
                parts.append("risk_score=\(String(format: "%.2f", riskScore))")
            }
            if let severity = queued.findingSeverity {
                parts.append("severity=\(severity)")
            }
            if let category = queued.findingCategory {
                parts.append("category=\(category)")
            }
            if let message = queued.findingMessage {
                parts.append("message=\(message)")
            }
            return reviewOK(parts.joined(separator: ", "))
        } catch {
            return reviewError(reviewLifecycleErrorMessage(error))
        }
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
        if let bridged = rustReviewToolResult(name: "review_get_outcome", args: args) {
            return bridged
        }
        let sessionId = sanitizedReviewArg(args, key: args["session_id"] != nil ? "session_id" : "sessionId")
        guard !sessionId.isEmpty else {
            return reviewError("Error: 'session_id' parameter is required")
        }
        if let accessError = validateReviewSessionAccess(sessionId: sessionId, args: args) {
            return reviewError(accessError)
        }
        guard let snapshot = MCPSharedState.readCodeReviewSnapshot(sessionId: sessionId) else {
            return reviewError("Error: unable to load the requested review session")
        }
        let outcome = snapshot.outcome
        let lines = [
            "summary: \(outcome.summary)",
            "verified_findings: \(outcome.verifiedFindings)",
            "false_positives: \(outcome.falsePositives)",
            "patches_ready: \(outcome.patchesReady)",
            "patches_applied: \(outcome.patchesApplied)",
            "prs_opened: \(outcome.prsOpened)",
            "merged_patches: \(outcome.mergedPatches)",
            "conflicts_detected: \(outcome.conflictsDetected)",
            "manual_action_required: \(outcome.manualActionRequired ? "true" : "false")",
            "tests_status: \(outcome.testsStatus?.rawValue ?? "unknown")",
        ]
        return reviewOK(lines.joined(separator: "\n"))
    }

    private static func queueFindingScopedReviewCommand(
        action: String,
        args: [String: String]
    ) -> CallTool.Result {
        let findingId = sanitizedReviewArg(args, key: "finding_id")
        let sessionId = sanitizedReviewArg(args, key: args["session_id"] != nil ? "session_id" : "sessionId")
        guard !findingId.isEmpty, !sessionId.isEmpty else {
            return reviewError("Error: 'finding_id' and 'session_id' are required")
        }
        do {
            let queued = try VerifiedFindingsLifecycleCommandService.queueFindingCommand(
                action: action,
                sessionId: sessionId,
                findingId: findingId,
                conversationId: resolveReviewConversationId(args),
                payload: args
            )
            var parts = [
                "OK — review command queued",
                "action=\(action)",
                "command_id=\(queued.commandId)",
                "session_id=\(queued.sessionId)",
            ]
            if let severity = queued.findingSeverity {
                parts.append("severity=\(severity)")
            }
            if let category = queued.findingCategory {
                parts.append("category=\(category)")
            }
            return reviewOK(parts.joined(separator: ", "))
        } catch {
            return reviewError(reviewLifecycleErrorMessage(error))
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
        }
    }
}
