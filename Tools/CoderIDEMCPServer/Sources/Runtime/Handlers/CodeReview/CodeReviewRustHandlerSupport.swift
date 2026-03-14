import CoderEngine
import Foundation
import MCP

extension CoderIDEMCPServerApp {
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
                    return (nil, "Error: 'conversation_id' is required for session_id '\(explicitSessionId)'")
                }
                guard snapshotConversationId == conversationId else {
                    return (nil, "Error: session_id '\(explicitSessionId)' does not belong to the requested conversation")
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

    static func rustReviewToolResult(
        name: String,
        args: [String: String]
    ) -> CallTool.Result? {
        let conversationId = resolveReviewConversationId(args)
        let snapshots = MCPSharedState.readCodeReviewSnapshots(conversationId: conversationId)
        let resolved = resolveReviewSessionId(
            args: args,
            requireExplicitWhenAmbiguous: true,
            allowLatestFallback: true,
            activeOnly: name != "review_list_sessions"
        )
        if let error = resolved.error,
           shouldReturnResolutionErrorImmediately(error, for: name) {
            return CallTool.Result(
                content: [.text(error)],
                isError: (error == "No active review session." || error == "No review session found.") ? nil : true
            )
        }
        let activeSnapshot = resolved.sessionId.flatMap { MCPSharedState.readCodeReviewSnapshot(sessionId: $0) }
        let findingsPayload: [[String: String]]
        if let activeSnapshot, name == "review_findings" {
            let kind = sanitizedReviewArg(args, key: "kind").lowercased()
            findingsPayload = MCPSharedState.readCodeReviewFindings(
                sessionId: activeSnapshot.sessionId,
                kind: kind.isEmpty ? "verified" : kind,
                severity: sanitizedReviewArg(args, key: "severity").nilIfEmpty,
                status: sanitizedReviewArg(args, key: "status").nilIfEmpty,
                origin: sanitizedReviewArg(args, key: "origin").nilIfEmpty,
                category: sanitizedReviewArg(args, key: "category").nilIfEmpty,
                file: sanitizedReviewArg(args, key: "file").nilIfEmpty,
                limit: Int(args["limit"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "") ?? 50,
                includeSensitiveDetails: false
            )
        } else {
            findingsPayload = []
        }
        let statusPayload = activeSnapshot.map { MCPSharedState.readCodeReviewStatus(sessionId: $0.sessionId) }.flatMap { $0 }
        let outcomePayload = activeSnapshot.map { snapshot in
            [
                "summary": snapshot.outcome.summary,
                "verified_findings": String(snapshot.outcome.verifiedFindings),
                "false_positives": String(snapshot.outcome.falsePositives),
                "patches_ready": String(snapshot.outcome.patchesReady),
                "patches_applied": String(snapshot.outcome.patchesApplied),
                "prs_opened": String(snapshot.outcome.prsOpened),
                "merged_patches": String(snapshot.outcome.mergedPatches),
                "conflicts_detected": String(snapshot.outcome.conflictsDetected),
                "manual_action_required": snapshot.outcome.manualActionRequired ? "true" : "false",
                "tests_status": snapshot.outcome.testsStatus?.rawValue ?? "unknown",
            ]
        }
        guard let result = ReviewMCPRustBridge.handleReviewTool(
            toolName: name,
            args: args,
            reviewSnapshots: name == "review_list_sessions" ? snapshots : activeSnapshot.map { [$0] } ?? snapshots,
            activeReviewSnapshot: activeSnapshot,
            reviewFindingsPayload: findingsPayload,
            reviewStatusPayload: statusPayload,
            reviewOutcomePayload: outcomePayload
        ) else {
            return fallbackReviewToolResult(
                name: name,
                args: args,
                reviewSnapshots: snapshots,
                activeReviewSnapshot: activeSnapshot,
                reviewFindingsPayload: findingsPayload,
                reviewStatusPayload: statusPayload,
                reviewOutcomePayload: outcomePayload
            )
        }
        return CallTool.Result(content: [.text(result.message)], isError: result.isError ? true : nil)
    }

    static func rustSecurityToolResult(
        name: String,
        args: [String: String]
    ) -> CallTool.Result? {
        if name == "security_findings" {
            let sessionId = sanitizedReviewArg(
                args,
                key: args["session_id"] != nil ? "session_id" : "sessionId"
            )
            if sessionId.isEmpty {
                return nil
            }
        }
        let conversationId = resolveReviewConversationId(args)
        let snapshots = MCPSharedState.readCodeReviewSnapshots(conversationId: conversationId)
        let activeSnapshot = snapshots.first
        let securityFindings = activeSnapshot.map { snapshot in
            SecurityWorkflowService.findings(
                snapshot: snapshot,
                kind: args["kind"],
                severity: args["severity"],
                status: args["status"],
                file: nil,
                limit: 50,
                includeSensitiveDetails: false,
                entryPoint: .mcp
            )
        } ?? []
        let gatePayload = currentSecurityGatePayload(args: args)
        let result = ReviewMCPRustBridge.handleSecurityTool(
            toolName: name,
            args: args,
            reviewSnapshots: snapshots,
            activeReviewSnapshot: activeSnapshot,
            securityFindingsPayload: securityFindings,
            reviewStatusPayload: activeSnapshot.map { MCPSharedState.readCodeReviewStatus(sessionId: $0.sessionId) }.flatMap { $0 },
            securityGatePayload: gatePayload
        )
        guard let result else { return nil }
        return CallTool.Result(content: [.text(result.message)], isError: result.isError ? true : nil)
    }

    static func rustBugHunterToolResult(
        name: String,
        args: [String: String]
    ) -> CallTool.Result? {
        let conversationId = parseConversationId(args["conversation_id"])
        let snapshots = MCPSharedState.readBugHunterSnapshots(conversationId: conversationId)
        let runId = (args["run_id"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let activeSnapshot = runId.isEmpty
            ? snapshots.first
            : MCPSharedState.readBugHunterSnapshot(runId: runId)
        let findingsPayload: [[String: String]]
        let clusterPayload: [String: String]?
        if let activeSnapshot,
           let reviewSessionId = activeSnapshot.reviewSessionId,
           let reviewSnapshot = MCPSharedState.readCodeReviewSnapshot(sessionId: reviewSessionId) {
            findingsPayload = BugHunterWorkflowService.findings(
                snapshot: reviewSnapshot,
                kind: args["kind"],
                severity: args["severity"],
                status: args["status"],
                limit: 50,
                includeSensitiveDetails: false,
                entryPoint: .mcp
            )
            clusterPayload = BugHunterWorkflowService.explainCluster(
                snapshot: reviewSnapshot,
                entryPoint: .mcp
            ).map {
                [
                    "cluster_title": $0.title,
                    "cluster_size": String($0.size),
                    "files": $0.files.joined(separator: ", "),
                    "avg_confidence": String(format: "%.2f", $0.averageConfidence),
                    "primary_risk": $0.primaryRisk,
                ]
            }
        } else {
            findingsPayload = []
            clusterPayload = nil
        }
        guard let result = ReviewMCPRustBridge.handleBugHunterTool(
            toolName: name,
            args: args,
            bughunterSnapshots: snapshots,
            activeBughunterSnapshot: activeSnapshot,
            bughunterFindingsPayload: findingsPayload,
            bughunterClusterPayload: clusterPayload
        ) else {
            return nil
        }
        return CallTool.Result(content: [.text(result.message)], isError: result.isError ? true : nil)
    }

    private static func currentSecurityGatePayload(
        args: [String: String]
    ) -> [String: String]? {
        let conversationId = resolveReviewConversationId(args)
        let scopedSnapshots = MCPSharedState.readCodeReviewSnapshots(conversationId: conversationId)
        let snapshots = scopedSnapshots.isEmpty ? MCPSharedState.readCodeReviewSnapshots() : scopedSnapshots
        guard let snapshot = snapshots.first else { return nil }
        let gate = SecurityWorkflowService.gate(snapshot: snapshot, entryPoint: .mcp)
        return [
            "ready": gate.ready ? "true" : "false",
            "summary": gate.summary,
        ]
    }

    private static func shouldReturnResolutionErrorImmediately(
        _ error: String,
        for toolName: String
    ) -> Bool {
        if toolName == "review_findings" {
            return error.contains("conversation_id")
                || error.contains("session_id")
                || error.contains("multiple review sessions")
        }
        return true
    }

    private static func reviewScopedSnapshots(
        conversationId: UUID?,
        activeOnly: Bool
    ) -> [CodeReviewSessionSnapshot] {
        MCPSharedState.readCodeReviewSnapshots(
            conversationId: conversationId
        ).filter { snapshot in
            !activeOnly || snapshot.isActive
        }
    }
}

private extension String {
    var nilIfEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
