import Foundation

public struct VerifiedFindingsQueuedCommandContext: Sendable, Equatable {
    public let commandId: String
    public let sessionId: String
    public let findingId: String
    public let patchId: String?
    public let patchVerifyStatus: String?
    public let patchRiskScore: Double?
    public let findingSeverity: String?
    public let findingCategory: String?
    public let findingMessage: String?
}

public enum VerifiedFindingsCommandError: Error, Equatable {
    case versionUnavailable(entityId: String)
    case versionConflict(expected: Int, actual: Int)
}

public enum VerifiedFindingsCommandOutcome: Sendable, Equatable {
    case executed(summary: String)
    case deduplicated(summary: String)
}

public enum VerifiedFindingsLifecycleCommandError: Error, Equatable {
    case missingIdentifiers
    case sessionNotFound(String)
    case conversationRequired(String)
    case conversationMismatch(String)
    case findingNotOwned(String, String)
    case missingPreparedPatch
    case patchNotVerified
    case findingNotClosable
    case rustPatchQueueContextUnavailable(String)
    case rustReviewQueueUnavailable(String)
}

public enum VerifiedFindingsLifecycleCommandService {
    public static func queueCommand(
        action: String,
        sessionId: String,
        findingId: String,
        conversationId: UUID?,
        payload: [String: String]
    ) throws -> VerifiedFindingsQueuedCommandContext {
        switch action {
        case "apply_patch":
            return try queueApplyPatchCommand(
                sessionId: sessionId,
                findingId: findingId,
                conversationId: conversationId,
                payload: payload
            )
        default:
            return try queueFindingCommand(
                action: action,
                sessionId: sessionId,
                findingId: findingId,
                conversationId: conversationId,
                payload: payload
            )
        }
    }

    public static func queueFindingCommand(
        action: String,
        sessionId: String,
        findingId: String,
        conversationId: UUID?,
        payload: [String: String]
    ) throws -> VerifiedFindingsQueuedCommandContext {
        let snapshot = try validatedSnapshot(
            sessionId: sessionId,
            findingId: findingId,
            conversationId: conversationId
        )
        return try queueFindingCommandWithRust(
            action: action,
            sessionId: sessionId,
            findingId: findingId,
            conversationId: conversationId,
            snapshot: snapshot,
            payload: payload
        )
    }

    public static func queueApplyPatchCommand(
        sessionId: String,
        findingId: String,
        conversationId: UUID?,
        payload: [String: String]
    ) throws -> VerifiedFindingsQueuedCommandContext {
        let snapshot = try validatedSnapshot(
            sessionId: sessionId,
            findingId: findingId,
            conversationId: conversationId,
        )
        return try queueFindingCommandWithRust(
            action: "apply_patch",
            sessionId: sessionId,
            findingId: findingId,
            conversationId: conversationId,
            snapshot: snapshot,
            payload: payload
        )
    }

    public static func validatedSnapshot(
        sessionId: String,
        findingId: String,
        conversationId: UUID?
    ) throws -> CodeReviewSessionSnapshot {
        guard !sessionId.isEmpty, !findingId.isEmpty else {
            throw VerifiedFindingsLifecycleCommandError.missingIdentifiers
        }
        guard let snapshot = MCPSharedState.readCodeReviewSnapshot(sessionId: sessionId) else {
            throw VerifiedFindingsLifecycleCommandError.sessionNotFound(sessionId)
        }
        if let snapshotConversationId = snapshot.conversationId {
            guard let conversationId else {
                throw VerifiedFindingsLifecycleCommandError.conversationRequired(sessionId)
            }
            guard snapshotConversationId == conversationId else {
                throw VerifiedFindingsLifecycleCommandError.conversationMismatch(sessionId)
            }
        }
        guard snapshot.findings.contains(where: { $0.id == findingId })
            || snapshot.candidates.contains(where: { $0.id == findingId }) else {
            throw VerifiedFindingsLifecycleCommandError.findingNotOwned(findingId, sessionId)
        }
        return snapshot
    }

    private static func queueFindingCommandWithRust(
        action: String,
        sessionId: String,
        findingId: String,
        conversationId: UUID?,
        snapshot: CodeReviewSessionSnapshot,
        payload: [String: String]
    ) throws -> VerifiedFindingsQueuedCommandContext {
        let response = try queuePatchContextWithRust(
            action: action,
            sessionId: sessionId,
            findingId: findingId,
            conversationId: conversationId,
            snapshot: snapshot
        )
        guard let command = MCPSharedState.enqueueCodeReviewCommandRustOnly(
            action: action,
            sessionId: sessionId,
            conversationId: conversationId,
            payload: payload
        ) else {
            throw VerifiedFindingsLifecycleCommandError.rustReviewQueueUnavailable(
                "Rust review queue unavailable for \(action)"
            )
        }
        return VerifiedFindingsQueuedCommandContext(
            commandId: command.id,
            sessionId: sessionId,
            findingId: findingId,
            patchId: response.patchId,
            patchVerifyStatus: response.patchVerifyStatus,
            patchRiskScore: response.patchRiskScore,
            findingSeverity: response.findingSeverity,
            findingCategory: response.findingCategory,
            findingMessage: response.findingMessage
        )
    }

    private static func queuePatchContextWithRust(
        action: String,
        sessionId: String,
        findingId: String,
        conversationId: UUID?,
        snapshot: CodeReviewSessionSnapshot
    ) throws -> ReviewPatchRustResponse {
        guard let response: ReviewPatchRustResponse = ReviewCoreBridge.call(
            functionName: "review_core_patch_workflow",
            request: ReviewPatchRustRequest(
                schemaVersion: 1,
                operation: "queue_context",
                action: action,
                sessionId: sessionId,
                findingId: findingId,
                conversationId: conversationId?.uuidString.lowercased(),
                snapshot: ReviewPatchRustSnapshot(snapshot: snapshot)
            )
        ) else {
            throw VerifiedFindingsLifecycleCommandError.rustPatchQueueContextUnavailable(
                "Rust patch queue context runtime required but unavailable"
            )
        }
        guard !response.isError else {
            switch response.errorCode {
            case "missing_identifiers":
                throw VerifiedFindingsLifecycleCommandError.missingIdentifiers
            case "session_not_found":
                throw VerifiedFindingsLifecycleCommandError.sessionNotFound(sessionId)
            case "conversation_required":
                throw VerifiedFindingsLifecycleCommandError.conversationRequired(sessionId)
            case "conversation_mismatch":
                throw VerifiedFindingsLifecycleCommandError.conversationMismatch(sessionId)
            case "finding_not_owned":
                throw VerifiedFindingsLifecycleCommandError.findingNotOwned(findingId, sessionId)
            case "missing_prepared_patch":
                throw VerifiedFindingsLifecycleCommandError.missingPreparedPatch
            case "patch_not_verified":
                throw VerifiedFindingsLifecycleCommandError.patchNotVerified
            case "finding_not_closable":
                throw VerifiedFindingsLifecycleCommandError.findingNotClosable
            default:
                throw VerifiedFindingsLifecycleCommandError.rustPatchQueueContextUnavailable(
                    response.errorMessage ?? "Rust patch queue context failed for \(action)"
                )
            }
        }
        return response
    }
}

public extension BugHunterWorkflowService {
    static func queueLifecycleCommand(
        action: String,
        sessionId: String,
        findingId: String,
        conversationId: UUID?,
        payload: [String: String]
    ) throws -> VerifiedFindingsQueuedCommandContext {
        try VerifiedFindingsLifecycleCommandService.queueCommand(
            action: action,
            sessionId: sessionId,
            findingId: findingId,
            conversationId: conversationId,
            payload: payload
        )
    }
}
