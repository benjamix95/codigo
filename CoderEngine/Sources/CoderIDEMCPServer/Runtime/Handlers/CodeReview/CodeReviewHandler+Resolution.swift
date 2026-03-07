import CoderEngine
import Foundation
import MCP

extension CoderIDEMCPServerApp {
    static let reviewSessionIdPattern = #"^[A-Za-z0-9][A-Za-z0-9_-]{0,127}$"#
    static let validReviewBackends: Set<String> = [
        "auto", "codex", "claude", "gemini",
        "codex-cli", "claude-cli", "gemini-cli",
        "openrouter", "openrouter-api",
        "minimax", "minimax-api",
        "grok", "grok-api",
        "openai", "openai-api",
        "anthropic", "anthropic-api",
        "google", "google-api",
    ]

    static func resolveReviewConversationId(_ args: [String: String]) -> UUID? {
        parseConversationId(args["conversation_id"] ?? args["conversationId"])
    }

    static func resolveReviewSessionId(
        args: [String: String],
        requireExplicitWhenAmbiguous: Bool,
        allowLatestFallback: Bool = true,
        activeOnly: Bool = true
    ) -> (sessionId: String?, error: String?) {
        let explicitSessionId = sanitizedReviewArg(
            args,
            key: args["session_id"] != nil ? "session_id" : "sessionId"
        )
        let conversationId = resolveReviewConversationId(args)
        let snapshots = reviewScopedSnapshots(
            conversationId: conversationId,
            activeOnly: activeOnly
        )

        if !explicitSessionId.isEmpty {
            if let formatError = validateReviewSessionIdFormat(explicitSessionId) {
                return (nil, formatError)
            }
            guard let snapshot = MCPSharedState.readCodeReviewSnapshot(sessionId: explicitSessionId) else {
                return (nil, "Error: session_id '\(explicitSessionId)' was not found")
            }
            if let snapshotConversationId = snapshot.conversationId {
                guard let conversationId else {
                    return (
                        nil,
                        "Error: 'conversation_id' is required for session_id '\(explicitSessionId)'"
                    )
                }
                guard snapshotConversationId == conversationId else {
                    return (
                        nil,
                        "Error: session_id '\(explicitSessionId)' does not belong to the requested conversation"
                    )
                }
            }
            return (explicitSessionId, nil)
        }

        guard allowLatestFallback else {
            return (nil, "Error: 'session_id' is required")
        }
        guard !snapshots.isEmpty else {
            return (nil, activeOnly ? "No active review session." : "No review session found.")
        }
        if requireExplicitWhenAmbiguous && snapshots.count > 1 {
            let ids = snapshots.map(\.sessionId).joined(separator: ", ")
            return (nil, "Error: multiple review sessions are available. Pass session_id explicitly. Available: \(ids)")
        }
        return (snapshots[0].sessionId, nil)
    }

    static func reviewCommandQueued(
        action: String,
        sessionId: String?,
        args: [String: String]
    ) -> CallTool.Result {
        let command = MCPSharedState.enqueueCodeReviewCommand(
            action: action,
            sessionId: sessionId,
            conversationId: resolveReviewConversationId(args),
            payload: args
        )
        var parts = ["OK — review command queued", "action=\(action)", "command_id=\(command.id)"]
        if let sessionId, !sessionId.isEmpty {
            parts.append("session_id=\(sessionId)")
        }
        return reviewOK(parts.joined(separator: ", "))
    }

    static func validateReviewBackend(_ backend: String) -> Bool {
        validReviewBackends.contains(backend.lowercased())
    }

    static func validateReviewSessionIdFormat(_ sessionId: String) -> String? {
        let trimmed = sessionId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return "Error: 'session_id' must not be empty"
        }
        guard trimmed.range(
            of: reviewSessionIdPattern,
            options: .regularExpression
        ) != nil else {
            return "Error: 'session_id' may contain only letters, digits, '_' or '-' and must not start with punctuation"
        }
        return nil
    }

    static func validateReviewSessionAccess(
        sessionId: String,
        args: [String: String]
    ) -> String? {
        if let formatError = validateReviewSessionIdFormat(sessionId) {
            return formatError
        }
        guard let snapshot = MCPSharedState.readCodeReviewSnapshot(sessionId: sessionId) else {
            return "Error: session_id '\(sessionId)' was not found"
        }
        if let snapshotConversationId = snapshot.conversationId {
            guard let conversationId = resolveReviewConversationId(args) else {
                return "Error: 'conversation_id' is required for session_id '\(sessionId)'"
            }
            guard snapshotConversationId == conversationId else {
                return "Error: session_id '\(sessionId)' does not belong to the requested conversation"
            }
        }
        return nil
    }

    static func validateFindingOwnership(
        sessionId: String,
        findingId: String,
        args: [String: String]
    ) -> String? {
        if let accessError = validateReviewSessionAccess(sessionId: sessionId, args: args) {
            return accessError
        }
        guard let snapshot = MCPSharedState.readCodeReviewSnapshot(sessionId: sessionId) else {
            return "Error: session_id '\(sessionId)' was not found"
        }
        guard snapshot.findings.contains(where: { $0.id == findingId }) else {
            return "Error: finding_id '\(findingId)' does not belong to session_id '\(sessionId)'"
        }
        return nil
    }

    private static func reviewScopedSnapshots(
        conversationId: UUID?,
        activeOnly: Bool
    ) -> [CodeReviewSessionSnapshot] {
        let snapshots = MCPSharedState.readCodeReviewSnapshots(
            conversationId: conversationId
        ).filter { snapshot in
            (!activeOnly || snapshot.isActive)
                && (conversationId != nil || snapshot.conversationId == nil)
        }
        return snapshots
    }
}
