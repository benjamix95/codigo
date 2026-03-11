import Foundation

extension MCPSharedState {
    static func rustEnqueueBugHunterCommand(
        action: String,
        runId: String,
        conversationId: UUID?,
        payload: [String: String],
        commands: [MCPSharedBugHunterCommand]
    ) -> (commands: [MCPSharedBugHunterCommand], command: MCPSharedBugHunterCommand?)? {
        let request = RustMCPCommandQueueRequest(
            schemaVersion: 1,
            operation: "enqueue",
            queueKind: "bughunter",
            commands: commands.map(\.rustRecord),
            commandId: nil,
            action: action,
            sessionId: nil,
            runId: runId,
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
            response.commands.map(MCPSharedBugHunterCommand.init(rustRecord:)),
            response.command.map(MCPSharedBugHunterCommand.init(rustRecord:))
        )
    }

    static func rustClaimPendingBugHunterCommands(
        commands: [MCPSharedBugHunterCommand]
    ) -> (commands: [MCPSharedBugHunterCommand], claimed: [MCPSharedBugHunterCommand])? {
        let request = RustMCPCommandQueueRequest(
            schemaVersion: 1,
            operation: "claim",
            queueKind: "bughunter",
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
            response.commands.map(MCPSharedBugHunterCommand.init(rustRecord:)),
            response.claimedCommands.map(MCPSharedBugHunterCommand.init(rustRecord:))
        )
    }

    static func rustMarkBugHunterCommand(
        id: String,
        status: MCPSharedBugHunterCommand.Status,
        resultMessage: String?,
        commands: [MCPSharedBugHunterCommand]
    ) -> [MCPSharedBugHunterCommand]? {
        let request = RustMCPCommandQueueRequest(
            schemaVersion: 1,
            operation: "mark",
            queueKind: "bughunter",
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
        return response.commands.map(MCPSharedBugHunterCommand.init(rustRecord:))
    }

    static func rustRefreshBugHunterHeartbeat(
        id: String,
        commands: [MCPSharedBugHunterCommand]
    ) -> [MCPSharedBugHunterCommand]? {
        let request = RustMCPCommandQueueRequest(
            schemaVersion: 1,
            operation: "heartbeat",
            queueKind: "bughunter",
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
        return response.commands.map(MCPSharedBugHunterCommand.init(rustRecord:))
    }
}

private extension MCPSharedBugHunterCommand {
    var rustRecord: RustMCPCommandRecord {
        RustMCPCommandRecord(
            id: id,
            action: action,
            sessionId: nil,
            runId: runId,
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
            runId: rustRecord.runId ?? "",
            conversationId: rustRecord.conversationId,
            payload: rustRecord.payload,
            createdAt: Date(timeIntervalSinceReferenceDate: rustRecord.createdAtReferenceSeconds),
            updatedAt: Date(timeIntervalSinceReferenceDate: rustRecord.updatedAtReferenceSeconds),
            status: Status(rawValue: rustRecord.status) ?? .pending,
            resultMessage: rustRecord.resultMessage
        )
    }
}
