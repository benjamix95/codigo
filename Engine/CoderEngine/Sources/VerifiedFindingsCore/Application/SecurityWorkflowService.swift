import Foundation

public enum SecurityWorkflowService {
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
}
