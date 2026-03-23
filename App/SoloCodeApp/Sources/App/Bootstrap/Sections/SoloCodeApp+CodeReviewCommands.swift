import CoderEngine
import Foundation

extension SoloCodeApp {
    @MainActor
    func startCodeReviewCommandLoopIfNeeded() {
        guard !didStartCodeReviewCommandLoop else { return }
        didStartCodeReviewCommandLoop = true

        let driver = CodeReviewCommandLoopDriver(
            claimPendingCommands: {
                MCPSharedState.claimPendingCodeReviewCommands()
            }
        ) { [self] commands in
            await processClaimedCodeReviewCommands(commands)
        }

        Task.detached(priority: .utility) {
            await driver.run()
        }
    }

    @MainActor
    func processPendingCodeReviewCommandsOnce() async {
        let commands = MCPSharedState.claimPendingCodeReviewCommands()
        guard !commands.isEmpty else { return }
        await processClaimedCodeReviewCommands(commands)
    }

    @MainActor
    private func processClaimedCodeReviewCommands(
        _ commands: [MCPSharedCodeReviewCommand]
    ) async {
        for command in commands {
            let outcome = await handleCodeReviewCommand(command)
            guard !outcome.deferred else { continue }
            MCPSharedState.markCodeReviewCommand(
                id: command.id,
                status: outcome.success ? .completed : .failed,
                resultMessage: outcome.message
            )
        }
    }

    @MainActor
    private func handleCodeReviewCommand(
        _ command: MCPSharedCodeReviewCommand
    ) async -> CodeReviewCommandOutcome {
        let cfg = providerFactoryConfig()
        let defaultConfig = SessionConfig(
            maxWorkers: cfg.codeReviewPartitions,
            maxRounds: cfg.codeReviewMaxRounds,
            analysisBackend: cfg.codeReviewAnalysisBackend,
            executionBackend: cfg.codeReviewExecutionBackend,
            analysisOnly: codeReviewAnalysisOnly
        )
        let commandConversationId = command.conversationId.flatMap { UUID(uuidString: $0) }
        let currentSnapshot = command.sessionId.flatMap { sessionId in
            resolveCodeReviewSnapshot(sessionId: sessionId, conversationId: commandConversationId)
        }
        let plan = ReviewCommandRustBridge.plan(
            command: command,
            defaultConfig: defaultConfig,
            currentConfig: currentSnapshot?.config,
            workspaceAvailable: !codeReviewCommandContext().workspacePaths.isEmpty,
            snapshotExists: currentSnapshot != nil
        )
        if plan == nil, ReviewCoreBridge.isEnabled {
            return .immediate(
                success: false,
                message: "Rust review command planner required but unavailable"
            )
        }
        if let plan, plan.isError {
            return .immediate(success: false, message: plan.message ?? "Invalid code review command")
        }

        switch plan?.kind ?? command.action {
        case "start":
            return await startReviewFromCommand(command, planned: plan)
        case "patch_action" where (plan?.action ?? command.action) == "apply_fix":
            return await applyFixFromCommand(command)
        case "patch_action", "verify_finding", "prepare_patch", "verify_patch", "apply_patch", "revalidate_finding", "rollback_patch", "close_finding", "open_pr", "merge_pr", "resolve_conflicts":
            return await handlePatchWorkflowCommand(command)
        case "dismiss":
            let result = await applyReviewMutation(command)
            return .immediate(success: result.success, message: result.message)
        case "comment":
            let result = await applyReviewMutation(command)
            return .immediate(success: result.success, message: result.message)
        case "configure":
            guard let sessionId = plan?.sessionId ?? command.sessionId else {
                return .immediate(success: false, message: "Missing session_id for configure")
            }
            guard let snapshot = resolveCodeReviewSnapshot(
                sessionId: sessionId,
                conversationId: commandConversationId
            ) else {
                return .immediate(success: false, message: "Review session not found")
            }
            let updatedConfig = plan?.config.map {
                SessionConfig(
                    maxWorkers: $0.maxWorkers,
                    maxRounds: $0.maxRounds,
                    analysisBackend: $0.analysisBackend,
                    executionBackend: $0.executionBackend,
                    analysisOnly: $0.analysisOnly
                )
            } ?? SessionConfig(
                maxWorkers: Int(command.payload["max_workers"] ?? "") ?? snapshot.config.maxWorkers,
                maxRounds: Int(command.payload["max_rounds"] ?? "") ?? snapshot.config.maxRounds,
                analysisBackend: command.payload["analysis_backend"] ?? snapshot.config.analysisBackend,
                executionBackend: command.payload["execution_backend"] ?? snapshot.config.executionBackend,
                analysisOnly: parseBoolValue(command.payload["analysis_only"]) ?? snapshot.config.analysisOnly
            )
            guard CodeReviewCommandRuntimeHooks.makeProvider(
                config: cfg,
                executionController: executionController,
                agentProviderId: providerRegistry.selectedProviderId,
                codebaseIndex: workspaceStore.codebaseIndex,
                workspacePaths: workspaceStore.activeWorkspacePaths,
                initialSessionConfig: updatedConfig
            ) != nil else {
                return .immediate(
                    success: false,
                    message: "Updated review configuration could not be resolved with the current providers"
                )
            }
            if let liveState = await ReviewSessionRegistry.shared.state(sessionId: sessionId) {
                guard await ReviewSessionRegistry.shared.updateConfig(
                    sessionId: sessionId,
                    config: updatedConfig
                ) else {
                    return .immediate(
                        success: false,
                        message: "Live review configuration update failed"
                    )
                }
                await persistLiveReviewState(
                    liveState,
                    conversationId: commandConversationId
                )
                return .immediate(success: true, message: "Live review configuration updated")
            }
            let result = await persistReviewSnapshotMutation(
                sessionId: sessionId,
                conversationId: commandConversationId
            ) { snapshot in
                configuredReviewSnapshot(
                    snapshot: snapshot,
                    sessionId: sessionId,
                    conversationId: commandConversationId,
                    config: updatedConfig
                )
            }
            let message = result.success
                ? "Persisted review configuration updated"
                : result.message
            return .immediate(success: result.success, message: message)
        default:
            return .immediate(success: false, message: "Unsupported code review command: \(command.action)")
        }
    }

    @MainActor
    private func startReviewFromCommand(
        _ command: MCPSharedCodeReviewCommand,
        planned: ReviewCommandPlanResponse?
    ) async -> CodeReviewCommandOutcome {
        let conversationId = command.conversationId.flatMap { UUID(uuidString: $0) }
        let sessionId = planned?.sessionId
            ?? MCPSharedState.sanitizedCodeReviewSessionId(command.sessionId)
            ?? UUID().uuidString.lowercased()
        let cfg = providerFactoryConfig()
        let context = codeReviewCommandContext()
        guard !context.workspacePaths.isEmpty else {
            return .immediate(success: false, message: "No active workspace is available for code review")
        }
        let sessionConfig = planned?.config.map {
            SessionConfig(
                maxWorkers: $0.maxWorkers,
                maxRounds: $0.maxRounds,
                analysisBackend: $0.analysisBackend,
                executionBackend: $0.executionBackend,
                analysisOnly: $0.analysisOnly
            )
        } ?? SessionConfig(
            maxWorkers: Int(command.payload["max_workers"] ?? "") ?? cfg.codeReviewPartitions,
            maxRounds: Int(command.payload["max_rounds"] ?? "") ?? cfg.codeReviewMaxRounds,
            analysisBackend: command.payload["analysis_backend"] ?? cfg.codeReviewAnalysisBackend,
            executionBackend: command.payload["execution_backend"] ?? cfg.codeReviewExecutionBackend,
            analysisOnly: parseBoolValue(command.payload["analysis_only"]) ?? codeReviewAnalysisOnly
        )
        guard let prompt = ReviewCommandRustBridge.buildStartPrompt(
            sessionId: sessionId,
            payload: command.payload,
            config: sessionConfig
        ) else {
            return .immediate(
                success: false,
                message: "Rust review start prompt runtime required but unavailable"
            )
        }
        let sessionState = makeCommandReviewSessionState(
            sessionId: sessionId,
            conversationId: conversationId,
            config: sessionConfig
        )

        guard let provider = CodeReviewCommandRuntimeHooks.makeProvider(
            config: cfg,
            executionController: executionController,
            agentProviderId: providerRegistry.selectedProviderId,
            codebaseIndex: workspaceStore.codebaseIndex,
            workspacePaths: context.workspacePaths,
            sessionState: sessionState,
            initialSessionConfig: sessionConfig
        ) else {
            return .immediate(success: false, message: "Unable to create code review provider")
        }

        if await ReviewSessionRegistry.shared.state(sessionId: sessionId) != nil
            || MCPSharedState.readCodeReviewSnapshot(sessionId: sessionId) != nil {
            return .immediate(success: false, message: "Review session \(sessionId) already exists")
        }

        await ReviewSessionRegistry.shared.register(sessionState)
        await persistLiveReviewState(sessionState, conversationId: conversationId)
        launchDeferredReviewCommand(
            command: command,
            provider: provider,
            sessionState: sessionState,
            prompt: prompt,
            context: context
        )
        return .deferred(message: "Review session \(sessionId) started")
    }

    @MainActor
    private func applyFixFromCommand(
        _ command: MCPSharedCodeReviewCommand
    ) async -> CodeReviewCommandOutcome {
        await handlePatchWorkflowCommand(command)
    }
}
