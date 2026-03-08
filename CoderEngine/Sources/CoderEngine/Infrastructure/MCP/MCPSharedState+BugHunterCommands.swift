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

    public static func claimPendingBugHunterCommands() -> [MCPSharedBugHunterCommand] {
        withBugHunterFileLock {
            let now = Date()
            var commands = readBugHunterCommandsUnsafe()
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
            guard let index = commands.firstIndex(where: { $0.id == id }) else { return }
            guard commands[index].status == .processing else { return }
            commands[index].updatedAt = Date()
            writeBugHunterCommandsUnsafe(commands)
        }
    }

    private static func readBugHunterCommandsUnsafe() -> [MCPSharedBugHunterCommand] {
        let data: Data
        do {
            data = try Data(contentsOf: bugHunterCommandsFilePath)
        } catch {
            if !FileManager.default.fileExists(atPath: bugHunterCommandsFilePath.path) {
                return []
            }
            bugHunterCommandsLogger.error("Failed to read BugHunter commands file: \(error.localizedDescription)")
            return []
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        do {
            return try decoder.decode([MCPSharedBugHunterCommand].self, from: data)
        } catch {
            bugHunterCommandsLogger.error("Failed to decode BugHunter commands: \(error.localizedDescription)")
            return []
        }
    }

    private static func writeBugHunterCommandsUnsafe(_ commands: [MCPSharedBugHunterCommand]) {
        ensureBugHunterDirectories()
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data: Data
        do {
            data = try encoder.encode(commands)
        } catch {
            bugHunterCommandsLogger.error("Failed to encode BugHunter commands: \(error.localizedDescription)")
            return
        }
        do {
            try data.write(to: bugHunterCommandsFilePath, options: .atomic)
        } catch {
            bugHunterCommandsLogger.error("Failed to write BugHunter commands: \(error.localizedDescription)")
        }
    }
}
