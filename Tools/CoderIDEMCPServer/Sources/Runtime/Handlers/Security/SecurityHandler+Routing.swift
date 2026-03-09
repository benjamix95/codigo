import CoderEngine
import Foundation
import MCP

extension CoderIDEMCPServerApp {
    static func handleSecurityStart(args: [String: String]) -> CallTool.Result {
        guard let gate = currentSecurityGate(args: args), gate.ready else {
            let summary = currentSecurityGate(args: args)?.summary
                ?? "security_gate=blocked, no verified bughunter baseline is available"
            return reviewError("Error: security gate not ready. \(summary)")
        }
        var reviewArgs = args
        reviewArgs["review_prompt_override"] = securityReviewPrompt(from: args)
        return handleReviewStart(args: reviewArgs)
    }

    static func handleSecurityStatus(args: [String: String]) -> CallTool.Result {
        let base = handleReviewStatus(args: args)
        let text = textContent(from: base)
        guard !text.contains("security_gate_ready:") else { return base }
        guard let gate = currentSecurityGate(args: args) else {
            if text.isEmpty || text == "No active review session." {
                return reviewOK(
                    """
                    No active review session.
                    security_gate_ready: false
                    security_gate_summary: security_gate=blocked, no verified bughunter baseline is available
                    """
                )
            }
            return reviewOK(
                """
                \(text)
                security_gate_ready: false
                security_gate_summary: security_gate=blocked, no verified bughunter baseline is available
                """
            )
        }
        if text.isEmpty || text == "No active review session." {
            return reviewOK(
                """
                No active review session.
                security_gate_ready: \(gate.ready ? "true" : "false")
                security_gate_summary: \(gate.summary)
                """
            )
        }
        return reviewOK(
            """
            \(text)
            security_gate_ready: \(gate.ready ? "true" : "false")
            security_gate_summary: \(gate.summary)
            """
        )
    }

    static func handleSecurityFindings(args: [String: String]) -> CallTool.Result {
        let sessionId = sanitizedReviewArg(
            args,
            key: args["session_id"] != nil ? "session_id" : "sessionId"
        )
        guard !sessionId.isEmpty else {
            return reviewError("Error: 'session_id' is required")
        }
        if let accessError = validateReviewSessionAccess(sessionId: sessionId, args: args) {
            return reviewError(accessError)
        }
        guard let snapshot = MCPSharedState.readCodeReviewSnapshot(sessionId: sessionId) else {
            return reviewError("Error: unable to load the requested review session")
        }
        let findings = SecurityWorkflowService.findings(
            snapshot: snapshot,
            kind: args["kind"],
            severity: args["severity"],
            status: args["status"],
            file: nil,
            limit: 50,
            includeSensitiveDetails: false,
            entryPoint: .mcp
        )
        guard !findings.isEmpty else {
            return reviewOK("No security findings match the query.")
        }
        let lines = findings.enumerated().map { index, finding in
            let message = finding["message"] ?? finding["message_summary"] ?? "n/a"
            let file = finding["file_path"] ?? finding["file_label"] ?? "redacted"
            let line = finding["line_number"].map { ":\($0)" } ?? ""
            let staleStatus = finding["stale_status"].map { ", stale: \($0)" } ?? ""
            return "[\(index + 1)] [\(finding["severity"] ?? "?")] \(file)\(line) — \(message) (domain: security, status: \(finding["status"] ?? "?")\(staleStatus), id: \(finding["id"] ?? "?"))"
        }
        return reviewOK(lines.joined(separator: "\n"))
    }

    static func handleSecurityPreparePatch(args: [String: String]) -> CallTool.Result {
        queueSecurityLifecycleCommand(action: "prepare_patch", args: args)
    }

    static func handleSecurityVerifyFinding(args: [String: String]) -> CallTool.Result {
        queueSecurityLifecycleCommand(action: "verify_finding", args: args)
    }

    static func handleSecurityPreviewPatch(args: [String: String]) -> CallTool.Result {
        handleReviewPreviewPatch(args: args)
    }

    static func handleSecurityApplyPatch(args: [String: String]) -> CallTool.Result {
        queueSecurityLifecycleCommand(action: "apply_patch", args: args)
    }

    static func handleSecurityVerifyPatch(args: [String: String]) -> CallTool.Result {
        queueSecurityLifecycleCommand(action: "verify_patch", args: args)
    }

    static func handleSecurityRevalidateFinding(args: [String: String]) -> CallTool.Result {
        queueSecurityLifecycleCommand(action: "revalidate_finding", args: args)
    }

    static func handleSecurityRollbackPatch(args: [String: String]) -> CallTool.Result {
        queueSecurityLifecycleCommand(action: "rollback_patch", args: args)
    }

    static func handleSecurityCloseFinding(args: [String: String]) -> CallTool.Result {
        queueSecurityLifecycleCommand(action: "close_finding", args: args)
    }

    private static func securityReviewPrompt(from args: [String: String]) -> String {
        let scope = (args["scope"] ?? "uncommitted").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch scope {
        case "staged":
            return """
            [REVIEW_SCOPE:staged] [MODE:security-audit]
            Run a security-focused review on staged changes only.
            Prioritize exploitability, auth/authz gaps, secrets, injection, unsafe config, dangerous deserialization, and sensitive logging.
            """
        case "against_ref":
            let ref = args["ref"] ?? "HEAD~1"
            return """
            [AGAINST:\(ref)] [MODE:security-audit]
            Run a security-focused review against ref \(ref).
            Prioritize exploitability, auth/authz gaps, secrets, injection, unsafe config, dangerous deserialization, and sensitive logging.
            """
        default:
            return """
            [REVIEW_SCOPE:uncommitted] [MODE:security-audit]
            Run a security-focused review on uncommitted changes.
            Prioritize exploitability, auth/authz gaps, secrets, injection, unsafe config, dangerous deserialization, and sensitive logging.
            """
        }
    }

    private static func currentSecurityGate(
        args: [String: String]
    ) -> VerifiedFindingsSecurityGateReport? {
        let conversationId = resolveReviewConversationId(args)
        let scopedSnapshots = MCPSharedState.readCodeReviewSnapshots(conversationId: conversationId)
        let snapshots = scopedSnapshots.isEmpty
            ? MCPSharedState.readCodeReviewSnapshots()
            : scopedSnapshots
        guard let snapshot = snapshots.first else { return nil }
        return SecurityWorkflowService.gate(snapshot: snapshot, entryPoint: .mcp)
    }

    private static func textContent(from result: CallTool.Result) -> String {
        guard let first = result.content.first else { return "" }
        if case .text(let text) = first {
            return text
        }
        return ""
    }

    private static func queueSecurityLifecycleCommand(
        action: String,
        args: [String: String]
    ) -> CallTool.Result {
        let findingId = sanitizedReviewArg(args, key: "finding_id")
        let sessionId = sanitizedReviewArg(args, key: args["session_id"] != nil ? "session_id" : "sessionId")
        guard !findingId.isEmpty, !sessionId.isEmpty else {
            return reviewError("Error: 'finding_id' and 'session_id' are required")
        }
        do {
            let queued = try SecurityWorkflowService.queueLifecycleCommand(
                action: action,
                sessionId: sessionId,
                findingId: findingId,
                conversationId: resolveReviewConversationId(args),
                payload: args
            )
            var parts = [
                "OK — security command queued",
                "action=\(action)",
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
            return reviewOK(parts.joined(separator: ", "))
        } catch let lifecycleError as VerifiedFindingsLifecycleCommandError {
            switch lifecycleError {
            case .missingIdentifiers:
                return reviewError("Error: 'finding_id' and 'session_id' are required")
            case .sessionNotFound(let sessionId):
                return reviewError("Error: session_id '\(sessionId)' was not found")
            case .conversationRequired(let sessionId):
                return reviewError("Error: 'conversation_id' is required for session_id '\(sessionId)'")
            case .conversationMismatch(let sessionId):
                return reviewError("Error: session_id '\(sessionId)' does not belong to the requested conversation")
            case .findingNotOwned(let findingId, let sessionId):
                return reviewError("Error: finding_id '\(findingId)' does not belong to session_id '\(sessionId)'")
            case .missingPreparedPatch:
                return reviewError("Error: no prepared patch artifact found. Run security_prepare_patch first.")
            case .patchNotVerified:
                return reviewError("Error: patch artifact is not verified. Run security_prepare_patch or security_verify_patch first.")
            }
        } catch {
            return reviewError(error.localizedDescription)
        }
    }
}
