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

public enum VerifiedFindingsLifecycleCommandError: Error, Equatable {
    case missingIdentifiers
    case sessionNotFound(String)
    case conversationRequired(String)
    case conversationMismatch(String)
    case findingNotOwned(String, String)
    case missingPreparedPatch
    case patchNotVerified
}

public enum VerifiedFindingsLifecycleCommandService {
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
        let command = MCPSharedState.enqueueCodeReviewCommand(
            action: action,
            sessionId: sessionId,
            conversationId: conversationId,
            payload: payload
        )
        let finding = snapshot.findings.first(where: { $0.id == findingId })
        return VerifiedFindingsQueuedCommandContext(
            commandId: command.id,
            sessionId: sessionId,
            findingId: findingId,
            patchId: nil,
            patchVerifyStatus: nil,
            patchRiskScore: nil,
            findingSeverity: finding?.severity.rawValue,
            findingCategory: finding?.category.rawValue,
            findingMessage: finding?.message
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
            conversationId: conversationId
        )
        guard let patch = snapshot.patches.first(where: { $0.findingId == findingId }) else {
            throw VerifiedFindingsLifecycleCommandError.missingPreparedPatch
        }
        guard patch.verifyStatus == .verified else {
            throw VerifiedFindingsLifecycleCommandError.patchNotVerified
        }
        let command = MCPSharedState.enqueueCodeReviewCommand(
            action: "apply_patch",
            sessionId: sessionId,
            conversationId: conversationId,
            payload: payload
        )
        let finding = snapshot.findings.first(where: { $0.id == findingId })
        return VerifiedFindingsQueuedCommandContext(
            commandId: command.id,
            sessionId: sessionId,
            findingId: findingId,
            patchId: patch.id,
            patchVerifyStatus: patch.verifyStatus.rawValue,
            patchRiskScore: patch.riskScore,
            findingSeverity: finding?.severity.rawValue,
            findingCategory: finding?.category.rawValue,
            findingMessage: finding?.message
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
}
