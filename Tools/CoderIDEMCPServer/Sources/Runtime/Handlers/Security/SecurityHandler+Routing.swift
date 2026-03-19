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
            guard (try? MCPSharedState.enqueueUniqueCodeReviewStartCommandRustOnly(
                sessionId: request.sessionId,
                conversationId: request.conversationId,
                payload: request.payload
            )) != nil else {
                return reviewError("Error: Rust review queue unavailable for security_start")
            }
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
        guard let bridged = rustSecurityToolResult(name: "security_status", args: args) else {
            return reviewError("Error: Rust review core unavailable for security_status")
        }
        return bridged
    }

    static func handleSecurityFindings(args: [String: String]) -> CallTool.Result {
        guard let bridged = rustSecurityToolResult(name: "security_findings", args: args) else {
            return reviewError("Error: Rust review core unavailable for security_findings")
        }
        return bridged
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
}
