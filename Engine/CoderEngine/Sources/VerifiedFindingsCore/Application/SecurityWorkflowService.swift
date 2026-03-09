import Foundation

public enum SecurityWorkflowService {
    public static func makeStartRequest(
        args: [String: String],
        conversationId: UUID?
    ) throws -> VerifiedFindingsStartCommandRequest {
        var payload = args
        payload["review_prompt_override"] = securityReviewPrompt(from: args)
        return try VerifiedFindingsStartCommandService.makeRequest(
            args: payload,
            conversationId: conversationId
        )
    }

    public static func findings(
        snapshot: CodeReviewSessionSnapshot,
        kind: String? = nil,
        severity: String? = nil,
        status: String? = nil,
        file: String? = nil,
        limit: Int = 50,
        includeSensitiveDetails: Bool = false,
        entryPoint: VerifiedFindingOriginEntryPoint = .mcp
    ) -> [[String: String]] {
        VerifiedFindingsQueryService.listPayloads(
            snapshot: snapshot,
            query: VerifiedFindingsQuery(
                kind: (kind ?? "verified").lowercased() == "candidate" ? .candidate : .verified,
                domain: .security,
                severity: severity,
                status: status,
                sourceOrigin: "securityAuditor",
                category: "security",
                file: file,
                limit: limit,
                includeSensitiveDetails: includeSensitiveDetails
            ),
            entryPoint: entryPoint
        )
    }

    public static func gate(
        snapshot: CodeReviewSessionSnapshot,
        entryPoint: VerifiedFindingOriginEntryPoint = .mcp
    ) -> VerifiedFindingsSecurityGateReport {
        VerifiedFindingsService.resolve(snapshot: snapshot, entryPoint: entryPoint).securityGate
    }

    public static func currentGate(
        snapshots: [CodeReviewSessionSnapshot],
        entryPoint: VerifiedFindingOriginEntryPoint = .mcp
    ) -> VerifiedFindingsSecurityGateReport? {
        guard let snapshot = snapshots.first else { return nil }
        return gate(snapshot: snapshot, entryPoint: entryPoint)
    }

    public static func queueLifecycleCommand(
        action: String,
        sessionId: String,
        findingId: String,
        conversationId: UUID?,
        payload: [String: String]
    ) throws -> VerifiedFindingsQueuedCommandContext {
        switch action {
        case "apply_patch":
            return try VerifiedFindingsLifecycleCommandService.queueApplyPatchCommand(
                sessionId: sessionId,
                findingId: findingId,
                conversationId: conversationId,
                payload: payload
            )
        default:
            return try VerifiedFindingsLifecycleCommandService.queueFindingCommand(
                action: action,
                sessionId: sessionId,
                findingId: findingId,
                conversationId: conversationId,
                payload: payload
            )
        }
    }

    private static func securityReviewPrompt(from args: [String: String]) -> String {
        let scope = (args["scope"] ?? "uncommitted")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
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
