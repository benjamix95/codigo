import Foundation

enum BugHunterRustFormatDecoder {
    static func decode(from data: Data) -> [MCPSharedBugHunterCommand]? {
        guard !data.isEmpty else { return [] }
        guard let rustCommands = try? JSONDecoder().decode(
            [RustFormatCommand].self, from: data
        ) else {
            return nil
        }
        return rustCommands.compactMap { $0.toSwiftCommand() }
    }
}

private struct RustFormatCommand: Decodable {
    let id: String
    let action: String
    let sessionId: String?
    let runId: String?
    let conversationId: String?
    let payload: [String: String]?
    let createdAtReferenceSeconds: Double?
    let updatedAtReferenceSeconds: Double?
    let status: String
    let resultMessage: String?

    enum CodingKeys: String, CodingKey {
        case id, action, sessionId, runId, conversationId, payload
        case createdAtReferenceSeconds, updatedAtReferenceSeconds
        case status, resultMessage
        case createdAt, updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        action = try container.decode(String.self, forKey: .action)
        sessionId = try container.decodeIfPresent(String.self, forKey: .sessionId)
        runId = try container.decodeIfPresent(String.self, forKey: .runId)
        conversationId = try container.decodeIfPresent(String.self, forKey: .conversationId)
        payload = try container.decodeIfPresent([String: String].self, forKey: .payload)
        status = try container.decode(String.self, forKey: .status)
        resultMessage = try container.decodeIfPresent(String.self, forKey: .resultMessage)

        createdAtReferenceSeconds = try container.decodeIfPresent(Double.self, forKey: .createdAtReferenceSeconds)
        updatedAtReferenceSeconds = try container.decodeIfPresent(Double.self, forKey: .updatedAtReferenceSeconds)
    }

    func toSwiftCommand() -> MCPSharedBugHunterCommand? {
        let resolvedRunId = runId ?? sessionId ?? id
        let created: Date
        if let secs = createdAtReferenceSeconds {
            created = Date(timeIntervalSinceReferenceDate: secs)
        } else {
            created = Date()
        }
        let updated: Date
        if let secs = updatedAtReferenceSeconds {
            updated = Date(timeIntervalSinceReferenceDate: secs)
        } else {
            updated = created
        }
        guard let parsedStatus = MCPSharedBugHunterCommand.Status(rawValue: status) else {
            return nil
        }
        return MCPSharedBugHunterCommand(
            id: id,
            action: action,
            runId: resolvedRunId,
            conversationId: conversationId,
            payload: payload ?? [:],
            createdAt: created,
            updatedAt: updated,
            status: parsedStatus,
            resultMessage: resultMessage
        )
    }
}
