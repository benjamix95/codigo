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
    public enum CodeReviewStartEnqueueError: Error, Sendable, Equatable {
        case sessionAlreadyQueued
    }

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
            var commands = _readCodeReviewCommandsUnsafe()
            if let result = rustEnqueueCodeReviewCommand(
                operation: "enqueue",
                action: action,
                sessionId: sessionId,
                conversationId: conversationId,
                payload: payload,
                commands: commands
            ), let command = result.command {
                _writeCodeReviewCommandsUnsafe(result.commands)
                return command
            }
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
            commands.append(command)
            _writeCodeReviewCommandsUnsafe(commands)
            return command
        }
    }

    public static func enqueueCodeReviewCommandRustOnly(
        action: String,
        sessionId: String?,
        conversationId: UUID?,
        payload: [String: String]
    ) -> MCPSharedCodeReviewCommand? {
        withCodeReviewFileLock {
            let commands = _readCodeReviewCommandsUnsafe()
            guard let result = rustEnqueueCodeReviewCommand(
                operation: "enqueue",
                action: action,
                sessionId: sessionId,
                conversationId: conversationId,
                payload: payload,
                commands: commands
            ), let command = result.command else {
                return nil
            }
            _writeCodeReviewCommandsUnsafe(result.commands)
            return command
        }
    }

    public static func enqueueUniqueCodeReviewStartCommand(
        sessionId: String,
        conversationId: UUID?,
        payload: [String: String]
    ) throws -> MCPSharedCodeReviewCommand {
        let normalizedSessionId = sessionId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedSessionId.isEmpty else {
            return enqueueCodeReviewCommand(
                action: "start",
                sessionId: nil,
                conversationId: conversationId,
                payload: payload
            )
        }

        let result: Result<MCPSharedCodeReviewCommand, CodeReviewStartEnqueueError> =
            withCodeReviewFileLock {
                var commands = _readCodeReviewCommandsUnsafe()
                if let rust = rustEnqueueCodeReviewCommand(
                    operation: "enqueue_unique_review_start",
                    action: "start",
                    sessionId: normalizedSessionId,
                    conversationId: conversationId,
                    payload: payload,
                    commands: commands
                ) {
                    if let command = rust.command {
                        _writeCodeReviewCommandsUnsafe(rust.commands)
                        return .success(command)
                    }
                }
                let hasQueuedStart = commands.contains { command in
                    guard command.action == "start" else { return false }
                    guard command.sessionId == normalizedSessionId else { return false }
                    guard command.status == .pending || command.status == .processing else {
                        return false
                    }
                    return true
                }
                guard !hasQueuedStart else {
                    return .failure(.sessionAlreadyQueued)
                }

                let normalizedPayload = payload.filter { !$0.key.isEmpty }
                let newCommand = MCPSharedCodeReviewCommand(
                    id: UUID().uuidString.lowercased(),
                    action: "start",
                    sessionId: normalizedSessionId,
                    conversationId: conversationId?.uuidString.lowercased(),
                    payload: normalizedPayload,
                    createdAt: Date(),
                    updatedAt: Date(),
                    status: .pending,
                    resultMessage: nil
                )
                commands.append(newCommand)
                _writeCodeReviewCommandsUnsafe(commands)
                return .success(newCommand)
            }

        return try result.get()
    }

    public static func enqueueUniqueCodeReviewStartCommandRustOnly(
        sessionId: String,
        conversationId: UUID?,
        payload: [String: String]
    ) throws -> MCPSharedCodeReviewCommand {
        let normalizedSessionId = sessionId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedSessionId.isEmpty else {
            throw CodeReviewStartEnqueueError.sessionAlreadyQueued
        }

        let result: Result<MCPSharedCodeReviewCommand, CodeReviewStartEnqueueError> =
            withCodeReviewFileLock {
                let commands = _readCodeReviewCommandsUnsafe()
                guard let rust = rustEnqueueCodeReviewCommand(
                    operation: "enqueue_unique_review_start",
                    action: "start",
                    sessionId: normalizedSessionId,
                    conversationId: conversationId,
                    payload: payload,
                    commands: commands
                ) else {
                    return .failure(.sessionAlreadyQueued)
                }
                guard let command = rust.command else {
                    return .failure(.sessionAlreadyQueued)
                }
                _writeCodeReviewCommandsUnsafe(rust.commands)
                return .success(command)
            }

        return try result.get()
    }

    public static func readPendingCodeReviewCommands() -> [MCPSharedCodeReviewCommand] {
        withCodeReviewFileLock {
            _readCodeReviewCommandsUnsafe().filter { $0.status == .pending }
        }
    }

    public static func hasQueuedCodeReviewStart(
        sessionId: String,
        conversationId _: UUID?
    ) -> Bool {
        let normalizedSessionId = sessionId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedSessionId.isEmpty else { return false }
        return withCodeReviewFileLock {
            _readCodeReviewCommandsUnsafe().contains { command in
                guard command.action == "start" else { return false }
                guard command.sessionId == normalizedSessionId else { return false }
                guard command.status == .pending || command.status == .processing else {
                    return false
                }
                return true
            }
        }
    }

    public static func claimPendingCodeReviewCommands() -> [MCPSharedCodeReviewCommand] {
        withCodeReviewFileLock {
            var commands = _readCodeReviewCommandsUnsafe()
            if let rust = rustClaimPendingCodeReviewCommands(commands: commands) {
                _writeCodeReviewCommandsUnsafe(rust.commands)
                return rust.claimed
            }
            let now = Date()
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
            if let rustCommands = rustMarkCodeReviewCommand(
                id: id,
                status: status,
                resultMessage: resultMessage,
                commands: commands
            ) {
                _writeCodeReviewCommandsUnsafe(rustCommands)
                return
            }
            guard let index = commands.firstIndex(where: { $0.id == id }) else { return }
            commands[index].status = status
            commands[index].resultMessage = resultMessage
            commands[index].updatedAt = Date()
            _writeCodeReviewCommandsUnsafe(commands)
        }
    }

    public static func refreshCodeReviewCommandHeartbeat(id: String) {
        withCodeReviewFileLock {
            var commands = _readCodeReviewCommandsUnsafe()
            if let rustCommands = rustRefreshCodeReviewHeartbeat(id: id, commands: commands) {
                _writeCodeReviewCommandsUnsafe(rustCommands)
                return
            }
            guard let index = commands.firstIndex(where: { $0.id == id }) else { return }
            guard commands[index].status == .processing else { return }
            commands[index].updatedAt = Date()
            _writeCodeReviewCommandsUnsafe(commands)
        }
    }

    private static func _readCodeReviewCommandsUnsafe() -> [MCPSharedCodeReviewCommand] {
        guard let data = try? Data(contentsOf: codeReviewCommandsFilePath) else { return [] }
        if let decoded = ReviewPersistenceRustAdapter.decodeReviewCommands(from: data) {
            return decoded
        }
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
        guard let data = ReviewPersistenceRustAdapter.encodeReviewCommands(commands)
            ?? (try? encoder.encode(commands)) else {
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
