import CoderEngine
import Foundation
import MCP

extension CoderIDEMCPServerApp {
    static func handleSecurityStart(args: [String: String]) -> CallTool.Result {
        guard let bridged = rustSecurityToolResult(name: "security_start", args: args) else {
            return reviewError("Error: Rust review core unavailable for security_start")
        }
        if bridged.isError == true {
            return bridged
        }
        guard let gate = currentSecurityGate(args: args), gate.ready else {
            let summary = currentSecurityGate(args: args)?.summary
                ?? "security_gate=blocked, no verified bughunter baseline is available"
            return reviewError("Error: security gate not ready. \(summary)")
        }
        do {
            let request = try SecurityWorkflowService.makeStartRequest(
                args: args,
                conversationId: resolveReviewConversationId(args)
            )
            _ = try VerifiedFindingsStartCommandService.enqueueReviewStart(request: request)
            return reviewOK(
                "OK — code review start queued (session_id=\(request.sessionId), scope=\(request.scope))"
            )
        } catch let error as VerifiedFindingsStartCommandError {
            switch error {
            case .invalidScope(let scope):
                return reviewError("Error: invalid scope '\(scope)'. Use: uncommitted, staged, against_ref")
            case .missingRef:
                return reviewError("Error: 'ref' parameter is required when scope=against_ref")
            case .invalidRef(let ref):
                return reviewError("Error: invalid ref '\(ref)'")
            case .invalidMaxWorkers:
                return reviewError("Error: max_workers must be 1-12")
            case .invalidMaxRounds:
                return reviewError("Error: max_rounds must be 1-10")
            case .invalidAnalysisOnly:
                return reviewError("Error: analysis_only must be a boolean value")
            case .invalidBackend(let field, let value):
                return reviewError("Error: invalid \(field) '\(value)'")
            case .invalidSessionId:
                return reviewError("Error: invalid session_id. Use only letters, numbers, hyphen, or underscore")
            case .sessionAlreadyExists(let sessionId):
                return reviewError("Error: session_id '\(sessionId)' already exists")
            case .sessionAlreadyQueued(let sessionId):
                return reviewError("Error: session_id '\(sessionId)' already has a queued start command")
            }
        } catch {
            return reviewError("Error: failed to queue code review start command")
        }
    }

    static func handleSecurityStatus(args: [String: String]) -> CallTool.Result {
        if let bridged = rustSecurityToolResult(name: "security_status", args: args) {
            return bridged
        }
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
        if let bridged = rustSecurityToolResult(name: "security_findings", args: args) {
            return bridged
        }
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
        let toolName = "security_\(action)"
        if let bridged = rustSecurityToolResult(name: toolName, args: args) {
            if bridged.isError == true {
                return bridged
            }
            let findingId = sanitizedReviewArg(args, key: "finding_id")
            let sessionId = sanitizedReviewArg(args, key: args["session_id"] != nil ? "session_id" : "sessionId")
            guard !findingId.isEmpty, !sessionId.isEmpty else {
                return reviewError("Error: 'finding_id' and 'session_id' are required")
            }
            _ = MCPSharedState.enqueueCodeReviewCommand(
                action: action,
                sessionId: sessionId,
                conversationId: resolveReviewConversationId(args),
                payload: args
            )
            return bridged
        }
        return reviewError("Error: Rust review core unavailable for \(toolName)")
    }
}
