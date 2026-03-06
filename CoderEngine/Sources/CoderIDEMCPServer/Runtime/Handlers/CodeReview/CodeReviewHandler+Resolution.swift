import CoderEngine
import Foundation
import MCP

extension CoderIDEMCPServerApp {
    static let validReviewBackends: Set<String> = [
        "auto", "codex", "claude", "gemini",
        "codex-cli", "claude-cli", "gemini-cli",
        "openrouter", "minimax", "grok",
        "openai", "anthropic", "google",
    ]

    static func resolveReviewConversationId(_ args: [String: String]) -> UUID? {
        parseConversationId(args["conversation_id"] ?? args["conversationId"])
    }

    static func resolveReviewSessionId(
        args: [String: String],
        requireExplicitWhenAmbiguous: Bool,
        allowLatestFallback: Bool = true
    ) -> (sessionId: String?, error: String?) {
        let explicitSessionId = sanitizedReviewArg(
            args,
            key: args["session_id"] != nil ? "session_id" : "sessionId"
        )
        let conversationId = resolveReviewConversationId(args)
        let snapshots = MCPSharedState.readCodeReviewSnapshots(conversationId: conversationId)

        if !explicitSessionId.isEmpty {
            guard snapshots.contains(where: { $0.sessionId == explicitSessionId })
                || MCPSharedState.readCodeReviewSnapshot(sessionId: explicitSessionId) != nil
            else {
                return (nil, "Error: session_id '\(explicitSessionId)' was not found")
            }
            return (explicitSessionId, nil)
        }

        guard allowLatestFallback else {
            return (nil, "Error: 'session_id' is required")
        }
        guard !snapshots.isEmpty else {
            return (nil, "No active review session.")
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
}
