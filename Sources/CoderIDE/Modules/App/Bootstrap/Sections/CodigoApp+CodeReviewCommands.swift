import CoderEngine
import Foundation

extension CodigoApp {
    @MainActor
    func processCodeReviewCommandLoop() async {
        while true {
            await processPendingCodeReviewCommandsOnce()
            try? await Task.sleep(nanoseconds: 350_000_000)
        }
    }

    @MainActor
    func processPendingCodeReviewCommandsOnce() async {
        let commands = MCPSharedState.claimPendingCodeReviewCommands()
        guard !commands.isEmpty else { return }

        for command in commands {
            let outcome = await handleCodeReviewCommand(command)
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
    ) async -> (success: Bool, message: String) {
        switch command.action {
        case "start":
            return await startReviewFromCommand(command)
        case "apply_fix":
            return await applyReviewMutation(command) { state, payload in
                guard let findingId = payload["finding_id"] else { return false }
                return await state.applyFix(findingId: findingId)
            }
        case "dismiss":
            return await applyReviewMutation(command) { state, payload in
                guard let findingId = payload["finding_id"] else { return false }
                let reason = payload["reason"] ?? "dismissed"
                return await state.dismissFinding(findingId: findingId, reason: reason)
            }
        case "comment":
            return await applyReviewMutation(command) { state, payload in
                guard let findingId = payload["finding_id"],
                      let content = payload["content"] else { return false }
                let author = payload["author"] ?? "agent"
                return await state.addComment(
                    findingId: findingId,
                    comment: FindingComment(author: author, content: content)
                )
            }
        case "configure":
            guard let sessionId = command.sessionId else {
                return (false, "Missing session_id for configure")
            }
            let snapshot = taskActivityStore.codeReviewSnapshot(
                sessionId: sessionId,
                conversationId: command.conversationId.flatMap { UUID(uuidString: $0) }
            ) ?? MCPSharedState.readCodeReviewSnapshot(sessionId: sessionId)
            guard let snapshot else {
                return (false, "Review session not found")
            }
            let updatedConfig = SessionConfig(
                maxWorkers: Int(command.payload["max_workers"] ?? "") ?? snapshot.config.maxWorkers,
                maxRounds: Int(command.payload["max_rounds"] ?? "") ?? snapshot.config.maxRounds,
                analysisBackend: command.payload["analysis_backend"] ?? snapshot.config.analysisBackend,
                executionBackend: command.payload["execution_backend"] ?? snapshot.config.executionBackend
            )
            let cfg = providerFactoryConfig()
            guard ProviderFactory.codeReviewMultiSwarmProvider(
                config: cfg,
                executionController: executionController,
                agentProviderId: providerRegistry.selectedProviderId,
                codebaseIndex: workspaceStore.codebaseIndex,
                workspacePaths: workspaceStore.activeWorkspacePaths,
                initialSessionConfig: updatedConfig
            ) != nil else {
                return (false, "Updated review configuration could not be resolved with the current providers")
            }
            if let liveState = await ReviewSessionRegistry.shared.state(sessionId: sessionId) {
                await liveState.updateConfig(updatedConfig)
                await persistLiveReviewState(
                    liveState,
                    conversationId: command.conversationId.flatMap(UUID.init(uuidString:))
                )
                return (true, "Live review configuration updated")
            }
            return await persistReviewSnapshotMutation(sessionId: sessionId) { snapshot in
                CodeReviewSessionSnapshot(
                    sessionId: snapshot.sessionId,
                    conversationId: snapshot.conversationId,
                    phase: snapshot.phase,
                    stage: snapshot.stage,
                    findings: snapshot.findings,
                    events: snapshot.events + [
                        CodeReviewSessionEvent(type: .configUpdated, detail: "Config updated from command bus")
                    ],
                    config: updatedConfig,
                    scope: snapshot.scope,
                    workspacePath: snapshot.workspacePath,
                    currentRound: snapshot.currentRound,
                    activeWorkerCount: snapshot.activeWorkerCount,
                    startedAt: snapshot.startedAt,
                    completedAt: snapshot.completedAt,
                    analysisCompletedAt: snapshot.analysisCompletedAt,
                    lastError: snapshot.lastError,
                    currentJobId: snapshot.currentJobId,
                    lastTestStatus: snapshot.lastTestStatus,
                    lastUpdatedAt: Date()
                )
            }
        default:
            return (false, "Unsupported code review command: \(command.action)")
        }
    }

    @MainActor
    private func startReviewFromCommand(
        _ command: MCPSharedCodeReviewCommand
    ) async -> (success: Bool, message: String) {
        let conversationId = command.conversationId.flatMap { UUID(uuidString: $0) }
        let sessionId = command.sessionId ?? UUID().uuidString.lowercased()
        let cfg = providerFactoryConfig()
        guard !workspaceStore.activeWorkspacePaths.isEmpty else {
            return (false, "No active workspace is available for code review")
        }
        let sessionConfig = SessionConfig(
            maxWorkers: Int(command.payload["max_workers"] ?? "") ?? cfg.codeReviewPartitions,
            maxRounds: Int(command.payload["max_rounds"] ?? "") ?? cfg.codeReviewMaxRounds,
            analysisBackend: command.payload["analysis_backend"] ?? cfg.codeReviewAnalysisBackend,
            executionBackend: command.payload["execution_backend"] ?? cfg.codeReviewExecutionBackend
        )
        let sessionState = CodeReviewSessionState(
            sessionId: sessionId,
            conversationId: conversationId,
            config: sessionConfig,
            onStateChange: { snapshot in
                Task { @MainActor in
                    await ReviewSessionRegistry.shared.recordSnapshot(snapshot)
                    taskActivityStore.ingestCodeReviewSnapshot(snapshot, conversationId: conversationId)
                }
            }
        )

        guard let provider = ProviderFactory.codeReviewMultiSwarmProvider(
            config: cfg,
            executionController: executionController,
            agentProviderId: providerRegistry.selectedProviderId,
            codebaseIndex: workspaceStore.codebaseIndex,
            workspacePaths: workspaceStore.activeWorkspacePaths,
            sessionState: sessionState,
            initialSessionConfig: sessionConfig
        ) else {
            return (false, "Unable to create code review provider")
        }

        if await ReviewSessionRegistry.shared.state(sessionId: sessionId) != nil
            || MCPSharedState.readCodeReviewSnapshot(sessionId: sessionId) != nil {
            return (false, "Review session \(sessionId) already exists")
        }

        await ReviewSessionRegistry.shared.register(sessionState)
        await persistLiveReviewState(sessionState, conversationId: conversationId)
        let prompt = reviewPrompt(for: command, sessionId: sessionId)
        let context = WorkspaceContext(
            workspacePaths: workspaceStore.activeWorkspacePaths,
            excludedPaths: workspaceStore.activeExcludedPaths,
            openFiles: openFilesStore.openFilesForContext(),
            activeFilePath: openFilesStore.openFilePath,
            activeRootPath: workspaceStore.activeWorkspacePaths.first?.path
        )

        Task {
            do {
                let stream = try await provider.send(
                    prompt: prompt,
                    context: context,
                    imageURLs: nil
                )
                for try await _ in stream {}
            } catch {
                await sessionState.fail(error: error.localizedDescription)
            }
        }

        return (true, "Review session \(sessionId) started")
    }

    @MainActor
    private func reviewPrompt(
        for command: MCPSharedCodeReviewCommand,
        sessionId: String
    ) -> String {
        let scope = (command.payload["scope"] ?? "uncommitted")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        switch scope {
        case "staged":
            return """
            [REVIEW_SCOPE:staged] Start a structured code review session \(sessionId).
            Focus on actionable findings and pipeline-safe fixes.
            """
        case "against_ref":
            let ref = command.payload["ref"] ?? "HEAD~1"
            let analysisOnly = parseBoolValue(command.payload["analysis_only"]) ?? codeReviewAnalysisOnly
            let configuredMaxRounds = Int(command.payload["max_rounds"] ?? "") ?? codeReviewMaxRounds
            return CodeReviewQuickCommands.againstPrompt(
                ref: ref,
                autofixEnabled: !analysisOnly,
                maxRounds: configuredMaxRounds
            )
        default:
            return """
            [REVIEW_SCOPE:uncommitted] Start a structured code review session \(sessionId).
            Focus on actionable findings and pipeline-safe fixes.
            """
        }
    }

}
