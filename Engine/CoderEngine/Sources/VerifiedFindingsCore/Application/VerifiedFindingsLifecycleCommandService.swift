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
    case findingNotClosable
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
        if let bridged = queueFindingCommandWithRust(
            action: action,
            sessionId: sessionId,
            findingId: findingId,
            conversationId: conversationId,
            payload: payload
        ) {
            return bridged
        }
        let snapshot = try validatedSnapshot(
            sessionId: sessionId,
            findingId: findingId,
            conversationId: conversationId
        )
        try validateFallbackCommandReadiness(
            action: action,
            snapshot: snapshot,
            findingId: findingId
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
        if let bridged = queueApplyPatchCommandWithRust(
            sessionId: sessionId,
            findingId: findingId,
            conversationId: conversationId,
            payload: payload
        ) {
            return bridged
        }
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

    private static func queueFindingCommandWithRust(
        action: String,
        sessionId: String,
        findingId: String,
        conversationId: UUID?,
        payload: [String: String]
    ) -> VerifiedFindingsQueuedCommandContext? {
        guard let snapshot = MCPSharedState.readCodeReviewSnapshot(sessionId: sessionId) else {
            return nil
        }
        guard let response = queuePatchContextWithRust(
            action: action,
            sessionId: sessionId,
            findingId: findingId,
            conversationId: conversationId,
            snapshot: snapshot
        ) else {
            return nil
        }
        if response.isError {
            return nil
        }
        let command = MCPSharedState.enqueueCodeReviewCommand(
            action: action,
            sessionId: sessionId,
            conversationId: conversationId,
            payload: payload
        )
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

    private static func queueApplyPatchCommandWithRust(
        sessionId: String,
        findingId: String,
        conversationId: UUID?,
        payload: [String: String]
    ) -> VerifiedFindingsQueuedCommandContext? {
        queueFindingCommandWithRust(
            action: "apply_patch",
            sessionId: sessionId,
            findingId: findingId,
            conversationId: conversationId,
            payload: payload
        )
    }

    private static func queuePatchContextWithRust(
        action: String,
        sessionId: String,
        findingId: String,
        conversationId: UUID?,
        snapshot: CodeReviewSessionSnapshot
    ) -> ReviewPatchRustResponse? {
        ReviewCoreBridge.call(
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
        )
    }

    private static func validateFallbackCommandReadiness(
        action: String,
        snapshot: CodeReviewSessionSnapshot,
        findingId: String
    ) throws {
        guard action == "close_finding" else { return }
        guard let finding = snapshot.findings.first(where: { $0.id == findingId }) else {
            throw VerifiedFindingsLifecycleCommandError.findingNotOwned(findingId, snapshot.sessionId)
        }
        let patch = finding.patchArtifactId.flatMap { patchId in
            snapshot.patches.first(where: { $0.id == patchId })
        } ?? snapshot.patches.first(where: { $0.findingId == findingId })

        let canClose: Bool
        switch finding.status {
        case .merged, .dismissed, .wontFix, .closed:
            canClose = true
        case .patchApplied, .fixApplied:
            canClose = patch?.validationStatus == .passed
        default:
            canClose = false
        }
        guard canClose else {
            throw VerifiedFindingsLifecycleCommandError.findingNotClosable
        }
    }
}
