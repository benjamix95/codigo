import CoderEngine
import Foundation

struct CodeReviewCommandLoopDriver: Sendable {
    typealias ClaimPendingCommands = @Sendable () -> [MCPSharedCodeReviewCommand]
    typealias ProcessClaimedCommands = @MainActor @Sendable ([MCPSharedCodeReviewCommand]) async -> Void
    private let pollIntervalNanoseconds: UInt64
    private let claimPendingCommands: ClaimPendingCommands
    private let processClaimedCommands: ProcessClaimedCommands

    init(pollIntervalNanoseconds: UInt64 = 350_000_000, claimPendingCommands: @escaping ClaimPendingCommands, processClaimedCommands: @escaping ProcessClaimedCommands) {
        self.pollIntervalNanoseconds = pollIntervalNanoseconds
        self.claimPendingCommands = claimPendingCommands
        self.processClaimedCommands = processClaimedCommands
    }

    func run() async {
        while !Task.isCancelled {
            let commands = claimPendingCommands()
            if commands.isEmpty {
                try? await Task.sleep(nanoseconds: pollIntervalNanoseconds)
                continue
            }
            await processClaimedCommands(commands)
        }
    }
}

enum CodeReviewCommandRuntimeHooks {
    typealias ProviderFactoryOverride = @MainActor (ProviderFactoryConfig, ExecutionController?, String?, CodebaseIndex?, [URL], CodeReviewSessionState?, SessionConfig?) -> (any LLMProvider)?
    typealias WorkspaceContextOverride = @MainActor (CodigoApp) -> WorkspaceContext?
    static var providerFactoryOverride: ProviderFactoryOverride?
    static var workspaceContextOverride: WorkspaceContextOverride?

    @MainActor
    static func makeProvider(config: ProviderFactoryConfig, executionController: ExecutionController?, agentProviderId: String?, codebaseIndex: CodebaseIndex?, workspacePaths: [URL], sessionState: CodeReviewSessionState? = nil, initialSessionConfig: SessionConfig? = nil) -> (any LLMProvider)? {
        if let providerFactoryOverride {
            return providerFactoryOverride(config, executionController, agentProviderId, codebaseIndex, workspacePaths, sessionState, initialSessionConfig)
        }
        return ProviderFactory.codeReviewMultiSwarmProvider(config: config, executionController: executionController, agentProviderId: agentProviderId, codebaseIndex: codebaseIndex, workspacePaths: workspacePaths, sessionState: sessionState, initialSessionConfig: initialSessionConfig)
    }

    @MainActor
    static func workspaceContext(for app: CodigoApp) -> WorkspaceContext {
        if let workspaceContextOverride, let override = workspaceContextOverride(app) { return override }
        return WorkspaceContext(
            workspacePaths: app.workspaceStore.activeWorkspacePaths,
            excludedPaths: app.workspaceStore.activeExcludedPaths,
            openFiles: app.openFilesStore.openFilesForContext(),
            activeFilePath: app.openFilesStore.openFilePath,
            activeRootPath: app.workspaceStore.activeWorkspacePaths.first?.path
        )
    }
}

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

    static func upsertPatchSnapshot(
        _ snapshot: CodeReviewSessionSnapshot,
        artifact: ReviewPatchArtifact
    ) -> ReviewCommandMutationResponse? {
        guard let data = try? JSONEncoder().encode(artifact),
              let patchJSON = String(data: data, encoding: .utf8) else {
            return nil
        }
        return mutateSnapshot(
            snapshot,
            action: "upsert_patch",
            payload: ["patch_json": patchJSON]
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

    static func buildStartPrompt(
        sessionId: String,
        payload: [String: String],
        config: SessionConfig
    ) -> String? {
        let response: ReviewCommandPromptResponse? = ReviewCoreBridge.call(
            functionName: "review_core_command_build_start_prompt",
            request: ReviewCommandPromptRequest(
                schemaVersion: 1,
                sessionId: sessionId,
                payload: payload,
                config: ReviewCommandPlanConfig(config)
            )
        )
        return response?.prompt
    }

    static func buildPanelPrompt(
        _ request: ReviewPanelPromptBridgeRequest
    ) -> String? {
        let response: ReviewPanelPromptBridgeResponse? = ReviewCoreBridge.call(
            functionName: "review_core_panel_build_prompt",
            request: request
        )
        if let prompt = response?.prompt {
            return prompt
        }
        if shouldDeferRustReviewCoreBootstrap(environment: ProcessInfo.processInfo.environment) {
            return ReviewPanelPromptSwiftFallback.build(request)
        }
        return nil
    }
}

extension CodigoApp {
    @MainActor
    func configuredReviewSnapshot(snapshot: CodeReviewSessionSnapshot, sessionId: String, conversationId _: UUID?, config: SessionConfig) -> CodeReviewSessionSnapshot? {
        let payload = ["session_id": sessionId].merging(config.reviewCommandPayload) { _, rhs in rhs }
        guard let mutation = ReviewCommandRustBridge.mutateSnapshot(
            snapshot,
            action: "configure",
            payload: payload
        ),
              !mutation.isError else {
            return nil
        }
        return mutation.snapshot
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

private struct ReviewCommandPromptRequest: Encodable {
    let schemaVersion: Int
    let sessionId: String
    let payload: [String: String]
    let config: ReviewCommandPlanConfig
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
    let patches: [ReviewPatchArtifact]?
    let events: [CodeReviewSessionEvent]?
    let snapshot: CodeReviewSessionSnapshot?
}

struct ReviewDeferredCommandFinalizeResponse: Decodable {
    let isError: Bool
    let commandStatus: String
    let resultMessage: String
}

private struct ReviewCommandPromptResponse: Decodable {
    let isError: Bool
    let message: String?
    let prompt: String?
}

struct ReviewPanelPromptBridgeRequest: Encodable {
    let schemaVersion: Int
    let promptKind: String
    let scopeTag: String?
    let scopeKind: String?
    let currentBranch: String?
    let branchName: String?
    let commits: [String]
    let selectedModes: [String]
    let customInstructions: String?
    let userMessage: String?
    let sessionSummary: String?
    let findingsCount: Int?
    let openCount: Int?
    let activeSessionId: String?
    let conversationId: String?
}

struct ReviewPanelPromptBridgeResponse: Decodable {
    let prompt: String?
}
