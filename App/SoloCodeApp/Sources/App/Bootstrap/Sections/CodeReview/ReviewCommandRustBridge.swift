import CoderEngine
import Foundation

struct ReviewCommandRustBridge {
    static func plan(
        command: MCPSharedCodeReviewCommand,
        defaultConfig: SessionConfig,
        currentConfig: SessionConfig?,
        workspaceAvailable: Bool,
        snapshotExists: Bool
    ) -> ReviewCommandPlanResponse? {
        ReviewCoreBridge.call(
            functionName: "review_core_command_plan",
            request: ReviewCommandPlanRequest(
                schemaVersion: 1,
                action: command.action,
                sessionId: command.sessionId,
                conversationId: command.conversationId,
                payload: command.payload,
                workspaceAvailable: workspaceAvailable,
                snapshotExists: snapshotExists,
                currentConfig: currentConfig.map(ReviewCommandPlanConfig.init),
                defaultConfig: ReviewCommandPlanConfig(defaultConfig)
            )
        )
    }
}

private struct ReviewCommandPlanRequest: Encodable {
    let schemaVersion: Int
    let action: String
    let sessionId: String?
    let conversationId: String?
    let payload: [String: String]
    let workspaceAvailable: Bool
    let snapshotExists: Bool
    let currentConfig: ReviewCommandPlanConfig?
    let defaultConfig: ReviewCommandPlanConfig
}

struct ReviewCommandPlanConfig: Codable {
    let maxWorkers: Int
    let maxRounds: Int
    let analysisBackend: String
    let executionBackend: String
    let analysisOnly: Bool

    init(_ config: SessionConfig) {
        self.maxWorkers = config.maxWorkers
        self.maxRounds = config.maxRounds
        self.analysisBackend = config.analysisBackend
        self.executionBackend = config.executionBackend
        self.analysisOnly = config.analysisOnly
    }
}

struct ReviewCommandPlanResponse: Decodable {
    let isError: Bool
    let kind: String
    let message: String?
    let sessionId: String?
    let config: ReviewCommandPlanConfig?
    let action: String?
    let findingId: String?
    let reason: String?
    let author: String?
    let content: String?
    let deferred: Bool
}
