import Foundation
import MCP

extension CoderIDEMCPServerApp {
    static func handleSecurityStart(args: [String: String]) -> CallTool.Result {
        var reviewArgs = args
        reviewArgs["review_prompt_override"] = securityReviewPrompt(from: args)
        return handleReviewStart(args: reviewArgs)
    }

    static func handleSecurityStatus(args: [String: String]) -> CallTool.Result {
        handleReviewStatus(args: args)
    }

    static func handleSecurityFindings(args: [String: String]) -> CallTool.Result {
        var reviewArgs = args
        // Keep the MCP handler decoupled from CoderEngine enum types.
        reviewArgs["origin"] = "securityAuditor"
        reviewArgs["category"] = "security"
        return handleReviewFindings(args: reviewArgs)
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
}
