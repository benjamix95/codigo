import Foundation

struct RustMCPCommandQueueRequest: Encodable {
    let schemaVersion: Int
    let operation: String
    let queueKind: String
    let commands: [RustMCPCommandRecord]
    let commandId: String?
    let action: String?
    let sessionId: String?
    let runId: String?
    let conversationId: String?
    let status: String?
    let resultMessage: String?
    let nowReferenceSeconds: Double
    let payload: [String: String]
}

struct RustMCPCommandRecord: Codable {
    let id: String
    let action: String
    let sessionId: String?
    let runId: String?
    let conversationId: String?
    let payload: [String: String]
    let createdAtReferenceSeconds: Double
    let updatedAtReferenceSeconds: Double
    let status: String
    let resultMessage: String?
}

struct RustMCPCommandQueueResponse: Decodable {
    let isError: Bool
    let errorMessage: String?
    let commands: [RustMCPCommandRecord]
    let claimedCommands: [RustMCPCommandRecord]
    let command: RustMCPCommandRecord?
}

struct RustMCPIndexRequest: Encodable {
    let schemaVersion: Int
    let reviewSnapshots: [RustMCPSnapshotRecord]
}

struct RustMCPSnapshotRecord: Encodable {
    let sessionId: String
    let conversationId: String?
    let phase: String
    let stage: String
    let findingsCount: Int
    let openFindingsCount: Int
    let currentRound: Int
    let activeWorkerCount: Int
    let scopeType: String?
    let scopeRef: String?
    let startedAtReferenceSeconds: Double?
    let updatedAtReferenceSeconds: Double
    let isActive: Bool
    let findingIds: [String]
    let candidateIds: [String]
    let patches: [RustMCPPatchRecord]
}

struct RustMCPPatchRecord: Encodable {
    let id: String
    let findingId: String
    let verifyStatus: String
    let riskScore: Double
}

struct RustMCPIndexResponse: Decodable {
    let latestSessionId: String?
    let latestSessionIdByConversation: [String: String]
    let sessions: [RustMCPIndexSessionRecord]
}

struct RustMCPIndexSessionRecord: Decodable {
    let sessionId: String
    let conversationId: String?
    let phase: String
    let stage: String
    let findingsCount: Int
    let openFindingsCount: Int
    let currentRound: Int
    let activeWorkerCount: Int
    let scopeType: String?
    let scopeRef: String?
    let startedAtReferenceSeconds: Double?
    let updatedAtReferenceSeconds: Double
    let isActive: Bool
}
