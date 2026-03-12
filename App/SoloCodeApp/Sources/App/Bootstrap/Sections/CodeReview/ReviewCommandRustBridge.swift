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

    static func mutateSnapshot(
        _ snapshot: CodeReviewSessionSnapshot,
        command: MCPSharedCodeReviewCommand
    ) -> ReviewCommandMutationResponse? {
        mutateSnapshot(
            snapshot,
            action: command.action,
            payload: command.payload
        )
    }

    static func mutateSnapshot(
        _ snapshot: CodeReviewSessionSnapshot,
        action: String,
        payload: [String: String]
    ) -> ReviewCommandMutationResponse? {
        ReviewCoreBridge.call(
            functionName: "review_core_command_mutate_snapshot",
            request: ReviewCommandMutationRequest(
                schemaVersion: 1,
                action: action,
                snapshot: snapshot,
                payload: payload
            )
        )
    }

    static func finalizeDeferred(
        sessionId: String,
        phase: ReviewSessionPhase,
        lastError: String?,
        autoPrepareSucceeded: Bool,
        sourceStateSucceeded: Bool
    ) -> ReviewDeferredCommandFinalizeResponse? {
        ReviewCoreBridge.call(
            functionName: "review_core_command_finalize_deferred",
            request: ReviewDeferredCommandFinalizeRequest(
                schemaVersion: 1,
                sessionId: sessionId,
                phase: phase.rawValue,
                lastError: lastError,
                autoPrepareSucceeded: autoPrepareSucceeded,
                sourceStateSucceeded: sourceStateSucceeded
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

private struct ReviewCommandMutationRequest: Encodable {
    let schemaVersion: Int
    let action: String
    let snapshot: CodeReviewSessionSnapshot
    let payload: [String: String]
}

private struct ReviewDeferredCommandFinalizeRequest: Encodable {
    let schemaVersion: Int
    let sessionId: String
    let phase: String
    let lastError: String?
    let autoPrepareSucceeded: Bool
    let sourceStateSucceeded: Bool
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

struct ReviewCommandMutationResponse: Decodable {
    let isError: Bool
    let message: String?
    let config: SessionConfig?
    let findings: [CodeReviewFinding]?
    let events: [CodeReviewSessionEvent]?
}

struct ReviewDeferredCommandFinalizeResponse: Decodable {
    let isError: Bool
    let commandStatus: String
    let resultMessage: String
}
