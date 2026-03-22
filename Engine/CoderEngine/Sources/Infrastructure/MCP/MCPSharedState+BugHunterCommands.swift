import Foundation
import OSLog

private let bugHunterCommandsLogger = Logger(subsystem: "com.codigo.CoderEngine", category: "BugHunterCommandsIO")

extension MCPSharedState {
    private static let staleBugHunterCommandTimeout: TimeInterval = 3605

    public static func enqueueBugHunterCommand(
        action: String,
        runId: String,
        conversationId: UUID?,
        payload: [String: String]
    ) -> MCPSharedBugHunterCommand {
        withBugHunterFileLock {
            ensureBugHunterDirectories()
            var commands = readBugHunterCommandsUnsafe()
            if let rust = rustEnqueueBugHunterCommand(
                action: action,
                runId: runId,
                conversationId: conversationId,
                payload: payload,
                commands: commands
            ), let command = rust.command {
                writeBugHunterCommandsUnsafe(rust.commands)
                return command
            }
            let command = MCPSharedBugHunterCommand(
                id: UUID().uuidString.lowercased(),
                action: action,
                runId: runId,
                conversationId: conversationId?.uuidString.lowercased(),
                payload: payload,
                createdAt: Date(),
                updatedAt: Date(),
                status: .pending,
                resultMessage: nil
            )
            commands.append(command)
            writeBugHunterCommandsUnsafe(commands)
            return command
        }
    }

    public static func enqueueBugHunterCommandRustOnly(
        action: String,
        runId: String,
        conversationId: UUID?,
        payload: [String: String]
    ) -> MCPSharedBugHunterCommand? {
        withBugHunterFileLock {
            ensureBugHunterDirectories()
            let commands = readBugHunterCommandsUnsafe()
            guard let rust = rustEnqueueBugHunterCommand(
                action: action,
                runId: runId,
                conversationId: conversationId,
                payload: payload,
                commands: commands
            ), let command = rust.command else {
                return nil
            }
            writeBugHunterCommandsUnsafe(rust.commands)
            return command
        }
    }

    public static func claimPendingBugHunterCommands() -> [MCPSharedBugHunterCommand] {
        withBugHunterFileLock {
            var commands = readBugHunterCommandsUnsafe()
            if let rust = rustClaimPendingBugHunterCommands(commands: commands) {
                writeBugHunterCommandsUnsafe(rust.commands)
                return rust.claimed
            }
            let now = Date()
            var claimed: [MCPSharedBugHunterCommand] = []

            for index in commands.indices {
                let command = commands[index]
                let isPending = command.status == .pending
                let isStaleProcessing = command.status == .processing
                    && now.timeIntervalSince(command.updatedAt) >= staleBugHunterCommandTimeout
                guard isPending || isStaleProcessing else { continue }
                commands[index].status = .processing
                commands[index].updatedAt = now
                claimed.append(commands[index])
            }

            if !claimed.isEmpty {
                writeBugHunterCommandsUnsafe(commands)
            }

            return claimed.sorted {
                if $0.createdAt != $1.createdAt { return $0.createdAt < $1.createdAt }
                return $0.id < $1.id
            }
        }
    }

    public static func markBugHunterCommand(
        id: String,
        status: MCPSharedBugHunterCommand.Status,
        resultMessage: String?
    ) {
        withBugHunterFileLock {
            var commands = readBugHunterCommandsUnsafe()
            if let rustCommands = rustMarkBugHunterCommand(
                id: id,
                status: status,
                resultMessage: resultMessage,
                commands: commands
            ) {
                writeBugHunterCommandsUnsafe(rustCommands)
                return
            }
            guard let index = commands.firstIndex(where: { $0.id == id }) else { return }
            commands[index].status = status
            commands[index].resultMessage = resultMessage
            commands[index].updatedAt = Date()
            writeBugHunterCommandsUnsafe(commands)
        }
    }

    public static func refreshBugHunterCommandHeartbeat(id: String) {
        withBugHunterFileLock {
            var commands = readBugHunterCommandsUnsafe()
            if let rustCommands = rustRefreshBugHunterHeartbeat(id: id, commands: commands) {
                writeBugHunterCommandsUnsafe(rustCommands)
                return
            }
            guard let index = commands.firstIndex(where: { $0.id == id }) else { return }
            guard commands[index].status == .processing else { return }
            commands[index].updatedAt = Date()
            writeBugHunterCommandsUnsafe(commands)
        }
    }

    private static var hasLoggedDecodeError = false

    private static func readBugHunterCommandsUnsafe() -> [MCPSharedBugHunterCommand] {
        let data: Data
        do {
            data = try Data(contentsOf: bugHunterCommandsFilePath)
        } catch {
            if !FileManager.default.fileExists(atPath: bugHunterCommandsFilePath.path) {
                return []
            }
            if !hasLoggedDecodeError {
                bugHunterCommandsLogger.error("Failed to read BugHunter commands file: \(error.localizedDescription)")
                hasLoggedDecodeError = true
            }
            return []
        }
        if data.isEmpty { return [] }
        if let decoded = ReviewPersistenceRustAdapter.decodeBugHunterCommands(from: data) {
            hasLoggedDecodeError = false
            return decoded
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let decoded = try? decoder.decode([MCPSharedBugHunterCommand].self, from: data) {
            hasLoggedDecodeError = false
            return decoded
        }
        if let decoded = BugHunterRustFormatDecoder.decode(from: data) {
            hasLoggedDecodeError = false
            return decoded
        }
        if !hasLoggedDecodeError {
            bugHunterCommandsLogger.error("Failed to decode BugHunter commands (logged once)")
            hasLoggedDecodeError = true
        }
        return []
    }

    private static func writeBugHunterCommandsUnsafe(_ commands: [MCPSharedBugHunterCommand]) {
        ensureBugHunterDirectories()
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = ReviewPersistenceRustAdapter.encodeBugHunterCommands(commands)
            ?? (try? encoder.encode(commands)) else {
            bugHunterCommandsLogger.error("Failed to encode BugHunter commands")
            return
        }
        do {
            try data.write(to: bugHunterCommandsFilePath, options: .atomic)
        } catch {
            bugHunterCommandsLogger.error("Failed to write BugHunter commands: \(error.localizedDescription)")
        }
    }
}
