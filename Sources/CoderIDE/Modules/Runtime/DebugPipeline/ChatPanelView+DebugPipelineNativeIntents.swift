import CoderEngine
import Foundation

enum DebugNativePipelineIntent {
    case start
    case refresh
    case syncCurrentConfiguration
    case syncWatchExpressions([String])
    case syncBreakpoints([DebugBreakpoint])
    case stepIn
    case stepOver
    case stepOut
    case stop

    var stage: DebugStageKind {
        switch self {
        case .start:
            return .nativeStart
        case .refresh:
            return .nativeRefresh
        case .syncCurrentConfiguration, .syncBreakpoints:
            return .nativeSyncBreakpoints
        case .syncWatchExpressions:
            return .nativeSyncWatches
        case .stepIn:
            return .nativeStepIn
        case .stepOver:
            return .nativeStepOver
        case .stepOut:
            return .nativeStepOut
        case .stop:
            return .nativeStop
        }
    }
}

extension ChatPanelView {
    @MainActor
    internal func executeDebugNativePipelineIntent(_ intent: DebugNativePipelineIntent) {
        guard debugStore.isNativeDebugEnabled else {
            appendTechnicalErrorMessage(
                "[Debug native] \(debugStore.nativeDebugDisabledReason ?? "Native debug disabilitato.")",
                in: conversationId
            )
            return
        }
        guard let targetConversationId = conversationId else {
            appendTechnicalErrorMessage(
                "[Debug native] Nessuna conversazione selezionata.",
                in: nil
            )
            return
        }
        guard !pipelineIntegrationService.isRunning(for: targetConversationId) else {
            appendTechnicalErrorMessage(
                "[Debug native] Una pipeline e' gia' in esecuzione per questa conversazione.",
                in: targetConversationId
            )
            return
        }
        guard let selectedProvider = providerRegistry.selectedProvider,
              let runtimeProvider = resolveRuntimeProvider(
                selectedProvider: selectedProvider,
                shouldRunPlanInline: false,
                forcePlanInline: false,
                preferCodeReviewRuntimeProvider: false
              ) else {
            appendTechnicalErrorMessage(
                "[Debug native] Impossibile risolvere il provider runtime.",
                in: targetConversationId
            )
            return
        }
        guard runtimeProvider.isAuthenticated() else {
            appendTechnicalErrorMessage(
                "[Debug native] Provider \(runtimeProvider.displayName) non autenticato.",
                in: targetConversationId
            )
            return
        }

        if coderMode != .debug {
            selectMode(.debug)
        }
        debugToggleEnabled = true
        showDebugPanel = true

        let ctx = effectiveContext.toWorkspaceContext(
            openFiles: openFilesStore.openFilesForContext(linkedPaths: linkedContextPaths()),
            activeSelection: nil,
            activeFilePath: openFilesStore.openFilePath,
            scopeMode: ContextScopeMode(rawValue: contextScopeModeRaw) ?? .auto
        )

        let assistantMessageId = UUID()
        chatStore.addMessage(
            ChatMessage(
                id: assistantMessageId,
                role: .assistant,
                content: "",
                isStreaming: true
            ),
            to: targetConversationId
        )
        startToolTraceTurn(
            conversationId: targetConversationId,
            assistantMessageId: assistantMessageId,
            providerId: runtimeProvider.id
        )

        if shouldResetTaskActivityStoreBeforeStartingTurn(
            activeTaskConversationIds: chatStore.activeTaskConversationIds,
            targetConversationId: targetConversationId
        ) {
            clearTaskActivityPipeline()
        }

        let request = buildNativeCommandDebugSessionRequest(for: intent)
        let (job, tasks) = PipelineJobFactory.fromDebugNativeStage(
            request,
            stage: intent.stage,
            workspace: ctx.workspacePath.path,
            providerId: runtimeProvider.id
        )
        let workerAdapter = AgentWorkerAdapter(
            provider: runtimeProvider,
            context: ctx,
            jobId: job.jobId,
            directTaskExecutor: DebugNativePipelineExecutor(
                debugService: debugStore.nativeDebugService
            )
        )

        pipelineIntegrationService.resumeDebugProjection(for: targetConversationId)
        pipelineIntegrationService.executeJob(
            job,
            tasks: tasks,
            workerAdapter: workerAdapter,
            conversationId: targetConversationId,
            assistantMessageId: assistantMessageId
        )
    }

    @MainActor
    internal func executeDebugNativeAddBreakpointIntent() {
        guard let updatedBreakpoints = buildBreakpointsAfterAddingFromInputs() else {
            return
        }
        executeDebugNativePipelineIntent(.syncBreakpoints(updatedBreakpoints))
    }

    @MainActor
    internal func executeDebugNativeToggleBreakpointIntent(_ breakpointId: UUID) {
        guard let updatedBreakpoints = buildBreakpointsAfterToggling(breakpointId) else {
            return
        }
        executeDebugNativePipelineIntent(.syncBreakpoints(updatedBreakpoints))
    }

    @MainActor
    internal func executeDebugNativeRemoveBreakpointIntent(_ breakpointId: UUID) {
        let updatedBreakpoints = debugStore.breakpoints.filter { $0.id != breakpointId }
        executeDebugNativePipelineIntent(.syncBreakpoints(updatedBreakpoints))
    }

    @MainActor
    private func buildNativeCommandDebugSessionRequest(
        for intent: DebugNativePipelineIntent
    ) -> DebugSessionRequest {
        let workspaceHints = openFilesStore
            .openFilesForContext(linkedPaths: linkedContextPaths())
            .map(\.path)
        var request = buildDebugSessionRequest(
            for: .continueInvestigation,
            workspaceHints: workspaceHints
        )
        request.includeNativeStages = true
        request.includeReviewStage = false
        request.includeCleanupStage = false
        request.backendPolicy = .appleHybrid

        switch intent {
        case .syncCurrentConfiguration:
            request.breakpoints = debugStore.breakpoints.pipelineSpecs
            request.watchExpressions = debugStore.parsedNativeWatchExpressions
        case .syncWatchExpressions(let expressions):
            request.watchExpressions = expressions
        case .syncBreakpoints(let breakpoints):
            request.breakpoints = breakpoints.pipelineSpecs
            request.watchExpressions = debugStore.parsedNativeWatchExpressions
        case .start, .refresh, .stepIn, .stepOver, .stepOut, .stop:
            break
        }

        if request.targetPath == nil {
            request.targetPath = debugStore.resolvedNativeTargetPathInput
        }
        return request
    }

    @MainActor
    private func buildBreakpointsAfterAddingFromInputs() -> [DebugBreakpoint]? {
        let filePath = debugStore.nativeBreakpointFilePathInput
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !filePath.isEmpty else {
            appendTechnicalErrorMessage(
                "[Debug native] Percorso file breakpoint obbligatorio.",
                in: conversationId
            )
            return nil
        }
        guard let line = Int(debugStore.nativeBreakpointLineInput), line > 0 else {
            appendTechnicalErrorMessage(
                "[Debug native] Linea breakpoint non valida.",
                in: conversationId
            )
            return nil
        }

        let condition = debugStore.nativeBreakpointConditionInput
            .trimmingCharacters(in: .whitespacesAndNewlines)
        var updatedBreakpoints = debugStore.breakpoints

        if let index = updatedBreakpoints.firstIndex(where: { breakpoint in
            breakpoint.filePath == filePath
                && breakpoint.line == line
                && breakpoint.condition == (condition.isEmpty ? nil : condition)
        }) {
            updatedBreakpoints[index].isActive = true
            return updatedBreakpoints
        }

        updatedBreakpoints.append(DebugBreakpoint(
            filePath: filePath,
            line: line,
            condition: condition.isEmpty ? nil : condition
        ))
        return updatedBreakpoints
    }

    @MainActor
    private func buildBreakpointsAfterToggling(_ breakpointId: UUID) -> [DebugBreakpoint]? {
        guard let index = debugStore.breakpoints.firstIndex(where: { $0.id == breakpointId }) else {
            appendTechnicalErrorMessage(
                "[Debug native] Breakpoint non trovato.",
                in: conversationId
            )
            return nil
        }
        var updatedBreakpoints = debugStore.breakpoints
        updatedBreakpoints[index].isActive.toggle()
        return updatedBreakpoints
    }
}
