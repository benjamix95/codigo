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
        let findings = VerifiedFindingsQueryService.listPayloads(
            snapshot: snapshot,
            query: VerifiedFindingsQuery(
                kind: (args["kind"] ?? "verified").lowercased() == "candidate" ? .candidate : .verified,
                domain: .security,
                severity: args["severity"],
                status: args["status"],
                sourceOrigin: "securityAuditor",
                category: "security",
                file: nil,
                limit: 50,
                includeSensitiveDetails: false
            ),
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
        handleReviewPreparePatch(args: args)
    }

    static func handleSecurityVerifyFinding(args: [String: String]) -> CallTool.Result {
        handleReviewVerifyFinding(args: args)
    }

    static func handleSecurityPreviewPatch(args: [String: String]) -> CallTool.Result {
        handleReviewPreviewPatch(args: args)
    }

    static func handleSecurityApplyPatch(args: [String: String]) -> CallTool.Result {
        handleReviewApplyPatch(args: args)
    }

    static func handleSecurityVerifyPatch(args: [String: String]) -> CallTool.Result {
        handleReviewVerifyPatch(args: args)
    }

    static func handleSecurityRevalidateFinding(args: [String: String]) -> CallTool.Result {
        handleReviewRevalidateFinding(args: args)
    }

    static func handleSecurityRollbackPatch(args: [String: String]) -> CallTool.Result {
        handleReviewRollbackPatch(args: args)
    }

    static func handleSecurityCloseFinding(args: [String: String]) -> CallTool.Result {
        handleReviewCloseFinding(args: args)
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
        return VerifiedFindingsService.resolve(snapshot: snapshot, entryPoint: .mcp).securityGate
    }

    private static func textContent(from result: CallTool.Result) -> String {
        guard let first = result.content.first else { return "" }
        if case .text(let text) = first {
            return text
        }
        return ""
    }
}
