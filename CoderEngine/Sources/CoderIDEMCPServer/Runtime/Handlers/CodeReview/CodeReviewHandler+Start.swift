import CoderEngine
import Foundation
import MCP

extension CoderIDEMCPServerApp {
    static func handleReviewStart(args: [String: String]) -> CallTool.Result {
        if hasInvalidConversationIdArgument(args["conversation_id"] ?? args["conversationId"]) {
            return reviewError("Error: 'conversation_id' must be a valid UUID")
        }
        let scope = sanitizedReviewArg(args, key: "scope").lowercased()
        let validScopes: Set<String> = ["uncommitted", "staged", "against_ref"]

        let effectiveScope = scope.isEmpty ? "uncommitted" : scope
        if !validScopes.contains(effectiveScope) {
            return reviewError(
                "Error: invalid scope '\(scope)'. Use: uncommitted, staged, against_ref"
            )
        }

        if effectiveScope == "against_ref" {
            let ref = sanitizedReviewArg(args, key: "ref")
            if ref.isEmpty {
                return reviewError(
                    "Error: 'ref' parameter is required when scope=against_ref"
                )
            }
        }

        // Validate optional numeric parameters
        if let maxWorkersStr = args["max_workers"],
           !maxWorkersStr.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            guard let val = Int(maxWorkersStr.trimmingCharacters(in: .whitespacesAndNewlines)),
                  (1...12).contains(val) else {
                return reviewError("Error: max_workers must be 1-12")
            }
        }

        if let maxRoundsStr = args["max_rounds"],
           !maxRoundsStr.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            guard let val = Int(maxRoundsStr.trimmingCharacters(in: .whitespacesAndNewlines)),
                  (1...10).contains(val) else {
                return reviewError("Error: max_rounds must be 1-10")
            }
        }

        if let backend = args["analysis_backend"],
           !backend.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           !validateReviewBackend(backend.trimmingCharacters(in: .whitespacesAndNewlines)) {
            return reviewError("Error: invalid analysis_backend '\(backend)'")
        }

        if let backend = args["execution_backend"],
           !backend.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           !validateReviewBackend(backend.trimmingCharacters(in: .whitespacesAndNewlines)) {
            return reviewError("Error: invalid execution_backend '\(backend)'")
        }

        let requestedSessionId = sanitizedReviewArg(
            args,
            key: args["session_id"] != nil ? "session_id" : "sessionId"
        )
        let sessionId: String
        if requestedSessionId.isEmpty {
            sessionId = UUID().uuidString.lowercased()
        } else if let sanitizedSessionId = MCPSharedState.sanitizedCodeReviewSessionId(requestedSessionId) {
            sessionId = sanitizedSessionId
        } else {
            return reviewError("Error: invalid session_id. Use only letters, numbers, hyphen, or underscore")
        }
        var commandPayload = args
        commandPayload["scope"] = effectiveScope
        commandPayload["session_id"] = sessionId
        if commandPayload["conversation_id"] == nil,
           let conversationId = resolveReviewConversationId(args) {
            commandPayload["conversation_id"] = conversationId.uuidString.lowercased()
        }
        _ = MCPSharedState.enqueueCodeReviewCommand(
            action: "start",
            sessionId: sessionId,
            conversationId: resolveReviewConversationId(args),
            payload: commandPayload
        )
        return reviewOK("OK — code review start queued (session_id=\(sessionId), scope=\(effectiveScope))")
    }

    static func handleReviewStatus(args: [String: String]) -> CallTool.Result {
        let resolved = resolveReviewSessionId(
            args: args,
            requireExplicitWhenAmbiguous: true
        )
        if let message = resolved.error {
            return message == "No active review session."
                ? reviewOK(message)
                : reviewError(message)
        }
        guard let sessionId = resolved.sessionId,
              let status = MCPSharedState.readCodeReviewStatus(sessionId: sessionId) else {
            return reviewOK("No active review session.")
        }
        let lines = status.sorted(by: { $0.key < $1.key }).map { "\($0.key): \($0.value)" }
        return reviewOK(lines.joined(separator: "\n"))
    }

    static func handleReviewDiffSummary(args: [String: String]) -> CallTool.Result {
        let resolved = resolveReviewSessionId(
            args: args,
            requireExplicitWhenAmbiguous: true
        )
        if let message = resolved.error {
            return reviewError(message)
        }
        guard let sessionId = resolved.sessionId,
              let snapshot = MCPSharedState.readCodeReviewSnapshot(sessionId: sessionId) else {
            return reviewError("Error: unable to load the requested review session")
        }
        let fileFilter = sanitizedReviewArg(args, key: "file")
        let workspacePath = URL(fileURLWithPath: snapshot.workspacePath ?? FileManager.default.currentDirectoryPath)
        let rendered = ReviewDiffSummaryService.renderSummary(
            snapshot: snapshot,
            workspacePath: workspacePath,
            fileFilter: fileFilter.isEmpty ? nil : fileFilter
        )
        return reviewOK(rendered)
    }

    static func handleReviewListSessions(args: [String: String]) -> CallTool.Result {
        if hasInvalidConversationIdArgument(args["conversation_id"] ?? args["conversationId"]) {
            return reviewError("Error: 'conversation_id' must be a valid UUID")
        }
        let snapshots = MCPSharedState.readCodeReviewSnapshots(
            conversationId: resolveReviewConversationId(args)
        )
        let filteredSnapshots = resolveReviewConversationId(args) == nil
            ? snapshots.filter { $0.conversationId == nil }
            : snapshots
        guard !filteredSnapshots.isEmpty else {
            return reviewOK("No review sessions found.")
        }
        let lines = filteredSnapshots.map { snapshot in
            let scope = snapshot.scope?.type.rawValue ?? "unknown"
            return "\(snapshot.sessionId) | phase=\(snapshot.phase.rawValue) | stage=\(snapshot.stage.rawValue) | scope=\(scope) | findings=\(snapshot.findings.count)"
        }
        return reviewOK(lines.joined(separator: "\n"))
    }
}
