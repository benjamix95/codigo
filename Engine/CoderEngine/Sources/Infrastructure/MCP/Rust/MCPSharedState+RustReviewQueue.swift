import Foundation

extension MCPSharedState {
    static func rustEnqueueCodeReviewCommand(
        operation: String,
        action: String,
        sessionId: String?,
        conversationId: UUID?,
        payload: [String: String],
        commands: [MCPSharedCodeReviewCommand]
    ) -> (commands: [MCPSharedCodeReviewCommand], command: MCPSharedCodeReviewCommand?)? {
        let request = RustMCPCommandQueueRequest(
            schemaVersion: 1,
            operation: operation,
            queueKind: "review",
            commands: commands.map(\.rustRecord),
            commandId: nil,
            action: action,
            sessionId: sessionId,
            runId: nil,
            conversationId: conversationId?.uuidString.lowercased(),
            status: nil,
            resultMessage: nil,
            nowReferenceSeconds: Date().timeIntervalSinceReferenceDate,
            payload: payload
        )
        guard let response: RustMCPCommandQueueResponse = ReviewCoreBridge.call(
            functionName: "review_core_mcp_enqueue_command",
            request: request
        ), !response.isError else {
            return nil
        }
        return (
            response.commands.map(MCPSharedCodeReviewCommand.init(rustRecord:)),
            response.command.map(MCPSharedCodeReviewCommand.init(rustRecord:))
        )
    }

    static func rustClaimPendingCodeReviewCommands(
        commands: [MCPSharedCodeReviewCommand]
    ) -> (commands: [MCPSharedCodeReviewCommand], claimed: [MCPSharedCodeReviewCommand])? {
        let request = RustMCPCommandQueueRequest(
            schemaVersion: 1,
            operation: "claim",
            queueKind: "review",
            commands: commands.map(\.rustRecord),
            commandId: nil,
            action: nil,
            sessionId: nil,
            runId: nil,
            conversationId: nil,
            status: nil,
            resultMessage: nil,
            nowReferenceSeconds: Date().timeIntervalSinceReferenceDate,
            payload: [:]
        )
        guard let response: RustMCPCommandQueueResponse = ReviewCoreBridge.call(
            functionName: "review_core_mcp_claim_commands",
            request: request
        ), !response.isError else {
            return nil
        }
        return (
            response.commands.map(MCPSharedCodeReviewCommand.init(rustRecord:)),
            response.claimedCommands.map(MCPSharedCodeReviewCommand.init(rustRecord:))
        )
    }

    static func rustMarkCodeReviewCommand(
        id: String,
        status: MCPSharedCodeReviewCommand.Status,
        resultMessage: String?,
        commands: [MCPSharedCodeReviewCommand]
    ) -> [MCPSharedCodeReviewCommand]? {
        let request = RustMCPCommandQueueRequest(
            schemaVersion: 1,
            operation: "mark",
            queueKind: "review",
            commands: commands.map(\.rustRecord),
            commandId: id,
            action: nil,
            sessionId: nil,
            runId: nil,
            conversationId: nil,
            status: status.rawValue,
            resultMessage: resultMessage,
            nowReferenceSeconds: Date().timeIntervalSinceReferenceDate,
            payload: [:]
        )
        guard let response: RustMCPCommandQueueResponse = ReviewCoreBridge.call(
            functionName: "review_core_mcp_mark_command",
            request: request
        ), !response.isError else {
            return nil
        }
        return response.commands.map(MCPSharedCodeReviewCommand.init(rustRecord:))
    }

    static func rustRefreshCodeReviewHeartbeat(
        id: String,
        commands: [MCPSharedCodeReviewCommand]
    ) -> [MCPSharedCodeReviewCommand]? {
        let request = RustMCPCommandQueueRequest(
            schemaVersion: 1,
            operation: "heartbeat",
            queueKind: "review",
            commands: commands.map(\.rustRecord),
            commandId: id,
            action: nil,
            sessionId: nil,
            runId: nil,
            conversationId: nil,
            status: nil,
            resultMessage: nil,
            nowReferenceSeconds: Date().timeIntervalSinceReferenceDate,
            payload: [:]
        )
        guard let response: RustMCPCommandQueueResponse = ReviewCoreBridge.call(
            functionName: "review_core_mcp_command_heartbeat",
            request: request
        ), !response.isError else {
            return nil
        }
        return response.commands.map(MCPSharedCodeReviewCommand.init(rustRecord:))
    }
}

private extension MCPSharedCodeReviewCommand {
    var rustRecord: RustMCPCommandRecord {
        RustMCPCommandRecord(
            id: id,
            action: action,
            sessionId: sessionId,
            runId: nil,
            conversationId: conversationId,
            payload: payload,
            createdAtReferenceSeconds: createdAt.timeIntervalSinceReferenceDate,
            updatedAtReferenceSeconds: updatedAt.timeIntervalSinceReferenceDate,
            status: status.rawValue,
            resultMessage: resultMessage
        )
    }

    init(rustRecord: RustMCPCommandRecord) {
        self.init(
            id: rustRecord.id,
            action: rustRecord.action,
            sessionId: rustRecord.sessionId,
            conversationId: rustRecord.conversationId,
            payload: rustRecord.payload,
            createdAt: Date(timeIntervalSinceReferenceDate: rustRecord.createdAtReferenceSeconds),
            updatedAt: Date(timeIntervalSinceReferenceDate: rustRecord.updatedAtReferenceSeconds),
            status: Status(rawValue: rustRecord.status) ?? .pending,
            resultMessage: rustRecord.resultMessage
        )
    }
}
