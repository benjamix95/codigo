import Foundation

public struct MCPSharedCodeReviewCommand: Codable, Sendable {
    public enum Status: String, Codable, Sendable {
        case pending
        case processing
        case completed
        case failed
    }

    public let id: String
    public let action: String
    public let sessionId: String?
    public let conversationId: String?
    public let payload: [String: String]
    public let createdAt: Date
    public var updatedAt: Date
    public var status: Status
    public var resultMessage: String?
}

extension MCPSharedState {
    private static let staleCodeReviewCommandTimeout: TimeInterval = 120

    public static var codeReviewCommandsFilePath: URL {
        codeReviewDirectoryPath.appendingPathComponent("commands.json")
    }

    public static func enqueueCodeReviewCommand(
        action: String,
        sessionId: String?,
        conversationId: UUID?,
        payload: [String: String]
    ) -> MCPSharedCodeReviewCommand {
        withCodeReviewFileLock {
            let normalizedPayload = payload.filter { !$0.key.isEmpty }
            let command = MCPSharedCodeReviewCommand(
                id: UUID().uuidString.lowercased(),
                action: action,
                sessionId: sanitizedCodeReviewSessionId(sessionId),
                conversationId: conversationId?.uuidString.lowercased(),
                payload: normalizedPayload,
                createdAt: Date(),
                updatedAt: Date(),
                status: .pending,
                resultMessage: nil
            )
            var commands = _readCodeReviewCommandsUnsafe()
            commands.append(command)
            _writeCodeReviewCommandsUnsafe(commands)
            return command
        }
    }

    public static func readPendingCodeReviewCommands() -> [MCPSharedCodeReviewCommand] {
        withCodeReviewFileLock {
            _readCodeReviewCommandsUnsafe().filter { $0.status == .pending }
        }
    }

    public static func hasQueuedCodeReviewStart(
        sessionId: String,
        conversationId: UUID?
    ) -> Bool {
        let normalizedSessionId = sessionId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedSessionId.isEmpty else { return false }
        let normalizedConversationId = conversationId?.uuidString.lowercased()
        return withCodeReviewFileLock {
            _readCodeReviewCommandsUnsafe().contains { command in
                guard command.action == "start" else { return false }
                guard command.sessionId == normalizedSessionId else { return false }
                guard command.status == .pending || command.status == .processing else {
                    return false
                }
                return command.conversationId == normalizedConversationId
            }
        }
    }

    public static func claimPendingCodeReviewCommands() -> [MCPSharedCodeReviewCommand] {
        withCodeReviewFileLock {
            let now = Date()
            var commands = _readCodeReviewCommandsUnsafe()
            var claimed: [MCPSharedCodeReviewCommand] = []

            for index in commands.indices {
                let command = commands[index]
                let isPending = command.status == .pending
                let isStaleProcessing = command.status == .processing
                    && now.timeIntervalSince(command.updatedAt) >= staleCodeReviewCommandTimeout
                guard isPending || isStaleProcessing else { continue }
                commands[index].status = .processing
                commands[index].updatedAt = now
                commands[index].resultMessage = nil
                claimed.append(commands[index])
            }

            if !claimed.isEmpty {
                _writeCodeReviewCommandsUnsafe(commands)
            }

            return claimed.sorted(by: sortCodeReviewCommandsForProcessing)
        }
    }

    public static func markCodeReviewCommand(
        id: String,
        status: MCPSharedCodeReviewCommand.Status,
        resultMessage: String?
    ) {
        withCodeReviewFileLock {
            var commands = _readCodeReviewCommandsUnsafe()
            guard let index = commands.firstIndex(where: { $0.id == id }) else { return }
            commands[index].status = status
            commands[index].resultMessage = resultMessage
            commands[index].updatedAt = Date()
            _writeCodeReviewCommandsUnsafe(commands)
        }
    }

    private static func _readCodeReviewCommandsUnsafe() -> [MCPSharedCodeReviewCommand] {
        guard let data = try? Data(contentsOf: codeReviewCommandsFilePath) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([MCPSharedCodeReviewCommand].self, from: data)) ?? []
    }

    private static func _writeCodeReviewCommandsUnsafe(_ commands: [MCPSharedCodeReviewCommand]) {
        let directories = [codeReviewDirectoryPath]
        for directory in directories where !FileManager.default.fileExists(atPath: directory.path) {
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(commands) else {
            print("[MCPSharedState] ⚠️ Failed to encode code review commands")
            return
        }
        do {
            try data.write(to: codeReviewCommandsFilePath, options: .atomic)
        } catch {
            print("[MCPSharedState] ⚠️ Failed to write code review commands: \(error.localizedDescription)")
        }
    }

    private static func sortCodeReviewCommandsForProcessing(
        _ lhs: MCPSharedCodeReviewCommand,
        _ rhs: MCPSharedCodeReviewCommand
    ) -> Bool {
        if lhs.createdAt != rhs.createdAt {
            return lhs.createdAt < rhs.createdAt
        }
        return lhs.id < rhs.id
    }
}
