import CoderEngine
import Foundation
import MCP
@testable import CoderIDEMCPServer

extension CoderIDEMCPServerApp {
    static func handleReviewStart(args: [String: String]) -> CallTool.Result {
        do {
            let request = try VerifiedFindingsStartCommandService.makeRequest(
                args: args,
                conversationId: resolveReviewConversationId(args)
            )
            let snapshots = MCPSharedState.readCodeReviewSnapshots(
                conversationId: request.conversationId
            )
            guard let bridged = ReviewMCPRustBridge.handleReviewTool(
                toolName: "review_start",
                args: request.payload,
                reviewSnapshots: snapshots,
                activeReviewSnapshot: nil
            ) else {
                return reviewError("Error: Rust review core unavailable for review_start")
            }
            if bridged.isError {
                return reviewError(bridged.message)
            }
            if MCPSharedState.hasQueuedCodeReviewStart(
                sessionId: request.sessionId,
                conversationId: request.conversationId
            ) {
                return reviewError("Error: session_id '\(request.sessionId)' already has a queued start command")
            }
            do {
                _ = try MCPSharedState.enqueueUniqueCodeReviewStartCommandRustOnly(
                    sessionId: request.sessionId,
                    conversationId: request.conversationId,
                    payload: request.payload
                )
            } catch {
                return reviewError("Error: Rust review queue unavailable for review_start")
            }
            return reviewOK(
                "OK — code review start queued (session_id=\(request.sessionId), scope=\(request.scope))"
            )
        } catch let error as VerifiedFindingsStartCommandError {
            switch error {
            case .invalidScope(let scope):
                return reviewError("Error: invalid scope '\(scope)'. Use: uncommitted, staged, against_ref")
            case .missingRef:
                return reviewError("Error: 'ref' parameter is required when scope=against_ref")
            case .invalidRef(let ref):
                return reviewError("Error: invalid ref '\(ref)'")
            case .invalidMaxWorkers:
                return reviewError("Error: max_workers must be 1-12")
            case .invalidMaxRounds:
                return reviewError("Error: max_rounds must be 1-10")
            case .invalidAnalysisOnly:
                return reviewError("Error: analysis_only must be a boolean value")
            case .invalidBackend(let field, let value):
                return reviewError("Error: invalid \(field) '\(value)'")
            case .invalidSessionId:
                return reviewError("Error: invalid session_id. Use only letters, numbers, hyphen, or underscore")
            case .sessionAlreadyExists(let sessionId):
                return reviewError("Error: session_id '\(sessionId)' already exists")
            case .sessionAlreadyQueued(let sessionId):
                return reviewError("Error: session_id '\(sessionId)' already has a queued start command")
            }
        } catch {
            return reviewError("Error: failed to queue code review start command")
        }
    }

    static func handleReviewApplyFix(args: [String: String]) -> CallTool.Result {
        let findingId = sanitizedReviewArg(args, key: "finding_id")
        if findingId.isEmpty {
            return reviewError("Error: 'finding_id' parameter is required")
        }
        let sessionId = sanitizedReviewArg(
            args,
            key: args["session_id"] != nil ? "session_id" : "sessionId"
        )
        guard !sessionId.isEmpty else {
            return reviewError("Error: 'session_id' parameter is required")
        }
        if let ownershipError = validateFindingOwnership(
            sessionId: sessionId,
            findingId: findingId,
            args: args
        ) {
            return reviewError(ownershipError)
        }
        return reviewCommandQueued(action: "apply_fix", sessionId: sessionId, args: args)
    }

    static func handleReviewDismiss(args: [String: String]) -> CallTool.Result {
        let findingId = sanitizedReviewArg(args, key: "finding_id")
        if findingId.isEmpty {
            return reviewError("Error: 'finding_id' parameter is required")
        }

        let reason = sanitizedReviewArg(args, key: "reason")
        let validReasons: Set<String> = [
            "false_positive", "wont_fix", "by_design", "duplicate", "",
        ]
        if !validReasons.contains(reason.lowercased()) {
            return reviewError(
                "Error: invalid reason '\(reason)'. Use: false_positive, wont_fix, by_design, duplicate"
            )
        }

        let effectiveReason = reason.isEmpty ? "dismissed" : reason
        let sessionId = sanitizedReviewArg(
            args,
            key: args["session_id"] != nil ? "session_id" : "sessionId"
        )
        guard !sessionId.isEmpty else {
            return reviewError("Error: 'session_id' parameter is required")
        }
        var payload = args
        payload["reason"] = effectiveReason
        if let ownershipError = validateFindingOwnership(
            sessionId: sessionId,
            findingId: findingId,
            args: payload
        ) {
            return reviewError(ownershipError)
        }
        return reviewCommandQueued(action: "dismiss", sessionId: sessionId, args: payload)
    }

    static func handleReviewConfigure(args: [String: String]) -> CallTool.Result {
        var updates: [String] = []

        if let maxWorkersStr = args["max_workers"],
           !maxWorkersStr.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            guard let val = Int(maxWorkersStr.trimmingCharacters(in: .whitespacesAndNewlines)),
                  (1...12).contains(val) else {
                return reviewError("Error: max_workers must be 1-12")
            }
            updates.append("max_workers=\(val)")
        }

        if let maxRoundsStr = args["max_rounds"],
           !maxRoundsStr.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            guard let val = Int(maxRoundsStr.trimmingCharacters(in: .whitespacesAndNewlines)),
                  (1...10).contains(val) else {
                return reviewError("Error: max_rounds must be 1-10")
            }
            updates.append("max_rounds=\(val)")
        }

        if let backend = args["analysis_backend"],
           !backend.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            guard validateReviewBackend(backend.trimmingCharacters(in: .whitespacesAndNewlines)) else {
                return reviewError("Error: invalid analysis_backend '\(backend)'")
            }
            updates.append("analysis_backend=\(backend.trimmingCharacters(in: .whitespacesAndNewlines))")
        }

        if let backend = args["execution_backend"],
           !backend.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            guard validateReviewBackend(backend.trimmingCharacters(in: .whitespacesAndNewlines)) else {
                return reviewError("Error: invalid execution_backend '\(backend)'")
            }
            updates.append("execution_backend=\(backend.trimmingCharacters(in: .whitespacesAndNewlines))")
        }

        if let analysisOnly = args["analysis_only"],
           !analysisOnly.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let normalized = analysisOnly.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let validValues = ["1", "0", "true", "false", "yes", "no", "y", "n"]
            guard validValues.contains(normalized) else {
                return reviewError("Error: analysis_only must be a boolean value")
            }
            updates.append("analysis_only=\(normalized)")
        }

        if updates.isEmpty {
            return reviewError("Error: at least one configuration parameter is required")
        }

        let sessionId = sanitizedReviewArg(
            args,
            key: args["session_id"] != nil ? "session_id" : "sessionId"
        )
        guard !sessionId.isEmpty else {
            return reviewError("Error: 'session_id' parameter is required")
        }
        if let accessError = validateReviewSessionAccess(sessionId: sessionId, args: args) {
            return reviewError(accessError)
        }

        return reviewCommandQueued(action: "configure", sessionId: sessionId, args: args)
    }

    static func handleReviewComment(args: [String: String]) -> CallTool.Result {
        let findingId = sanitizedReviewArg(args, key: "finding_id")
        if findingId.isEmpty {
            return reviewError("Error: 'finding_id' parameter is required")
        }

        let content = sanitizedReviewArg(args, key: "content")
        if content.isEmpty {
            return reviewError("Error: 'content' parameter is required")
        }

        let sessionId = sanitizedReviewArg(
            args,
            key: args["session_id"] != nil ? "session_id" : "sessionId"
        )
        guard !sessionId.isEmpty else {
            return reviewError("Error: 'session_id' parameter is required")
        }
        if let ownershipError = validateFindingOwnership(
            sessionId: sessionId,
            findingId: findingId,
            args: args
        ) {
            return reviewError(ownershipError)
        }

        return reviewCommandQueued(action: "comment", sessionId: sessionId, args: args)
    }
}
