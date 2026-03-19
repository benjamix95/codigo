import CoderEngine
import Foundation
import MCP
@testable import CoderIDEMCPServer

extension CoderIDEMCPServerApp {
    static func handleSecurityTool(
        name: String,
        args: [String: String]
    ) -> CallTool.Result? {
        let securityTools: Set<String> = [
            "security_start", "security_status", "security_findings", "security_verify_finding",
            "security_prepare_patch", "security_preview_patch", "security_apply_patch",
            "security_verify_patch", "security_revalidate_finding", "security_rollback_patch",
            "security_close_finding",
        ]
        guard securityTools.contains(name) else { return nil }
        switch name {
        case "security_start": return handleSecurityStart(args: args)
        case "security_status": return handleSecurityStatus(args: args)
        case "security_findings": return handleSecurityFindings(args: args)
        case "security_verify_finding": return handleSecurityVerifyFinding(args: args)
        case "security_prepare_patch": return handleSecurityPreparePatch(args: args)
        case "security_preview_patch": return handleSecurityPreviewPatch(args: args)
        case "security_apply_patch": return handleSecurityApplyPatch(args: args)
        case "security_verify_patch": return handleSecurityVerifyPatch(args: args)
        case "security_revalidate_finding": return handleSecurityRevalidateFinding(args: args)
        case "security_rollback_patch": return handleSecurityRollbackPatch(args: args)
        case "security_close_finding": return handleSecurityCloseFinding(args: args)
        default: return reviewError("Unknown security tool: \(name)")
        }
    }

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

    static func handleSecurityPreparePatch(args: [String: String]) -> CallTool.Result { queueSecurityLifecycleCommand(action: "prepare_patch", args: args) }
    static func handleSecurityVerifyFinding(args: [String: String]) -> CallTool.Result { queueSecurityLifecycleCommand(action: "verify_finding", args: args) }
    static func handleSecurityPreviewPatch(args: [String: String]) -> CallTool.Result { handleReviewPreviewPatch(args: args) }
    static func handleSecurityApplyPatch(args: [String: String]) -> CallTool.Result { queueSecurityLifecycleCommand(action: "apply_patch", args: args) }
    static func handleSecurityVerifyPatch(args: [String: String]) -> CallTool.Result { queueSecurityLifecycleCommand(action: "verify_patch", args: args) }
    static func handleSecurityRevalidateFinding(args: [String: String]) -> CallTool.Result { queueSecurityLifecycleCommand(action: "revalidate_finding", args: args) }
    static func handleSecurityRollbackPatch(args: [String: String]) -> CallTool.Result { queueSecurityLifecycleCommand(action: "rollback_patch", args: args) }
    static func handleSecurityCloseFinding(args: [String: String]) -> CallTool.Result { queueSecurityLifecycleCommand(action: "close_finding", args: args) }

    private static func currentSecurityGate(
        args: [String: String]
    ) -> VerifiedFindingsSecurityGateReport? {
        let conversationId = resolveReviewConversationId(args)
        let scopedSnapshots = MCPSharedState.readCodeReviewSnapshots(conversationId: conversationId)
        let snapshots = scopedSnapshots.isEmpty ? MCPSharedState.readCodeReviewSnapshots() : scopedSnapshots
        guard let snapshot = snapshots.first else { return nil }
        return SecurityWorkflowService.gate(snapshot: snapshot, entryPoint: .mcp)
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
