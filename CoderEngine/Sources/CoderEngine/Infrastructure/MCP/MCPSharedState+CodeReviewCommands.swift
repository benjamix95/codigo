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
    public static var codeReviewCommandsFilePath: URL {
        codeReviewDirectoryPath.appendingPathComponent("commands.json")
    }

    public static func enqueueCodeReviewCommand(
        action: String,
        sessionId: String?,
        conversationId: UUID?,
        payload: [String: String]
    ) -> MCPSharedCodeReviewCommand {
        fileAccessQueue.sync {
            ensureDirectory()
            let normalizedPayload = payload.filter { !$0.key.isEmpty }
            let command = MCPSharedCodeReviewCommand(
                id: UUID().uuidString.lowercased(),
                action: action,
                sessionId: sessionId?.trimmingCharacters(in: .whitespacesAndNewlines),
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
        fileAccessQueue.sync {
            _readCodeReviewCommandsUnsafe().filter { $0.status == .pending }
        }
    }

    public static func markCodeReviewCommand(
        id: String,
        status: MCPSharedCodeReviewCommand.Status,
        resultMessage: String?
    ) {
        fileAccessQueue.sync {
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
}
