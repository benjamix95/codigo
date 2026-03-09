import Foundation
import MCP

extension CoderIDEMCPServerApp {
    static let securityTools: Set<String> = [
        "security_start",
        "security_status",
        "security_findings",
        "security_verify_finding",
        "security_prepare_patch",
        "security_preview_patch",
        "security_apply_patch",
        "security_verify_patch",
        "security_revalidate_finding",
        "security_rollback_patch",
        "security_close_finding",
    ]

    static func handleSecurityTool(
        name: String,
        args: [String: String]
    ) -> CallTool.Result? {
        guard securityTools.contains(name) else { return nil }
        switch name {
        case "security_start":
            return handleSecurityStart(args: args)
        case "security_status":
            return handleSecurityStatus(args: args)
        case "security_findings":
            return handleSecurityFindings(args: args)
        case "security_verify_finding":
            return handleSecurityVerifyFinding(args: args)
        case "security_prepare_patch":
            return handleSecurityPreparePatch(args: args)
        case "security_preview_patch":
            return handleSecurityPreviewPatch(args: args)
        case "security_apply_patch":
            return handleSecurityApplyPatch(args: args)
        case "security_verify_patch":
            return handleSecurityVerifyPatch(args: args)
        case "security_revalidate_finding":
            return handleSecurityRevalidateFinding(args: args)
        case "security_rollback_patch":
            return handleSecurityRollbackPatch(args: args)
        case "security_close_finding":
            return handleSecurityCloseFinding(args: args)
        default:
            return reviewError("Unknown security tool: \(name)")
        }
    }
}
