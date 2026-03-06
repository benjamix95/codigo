import CoderEngine
import SwiftUI

enum DebugPipelineIntent {
    case startSession(summary: String)
    case continueInvestigation
    case resolveAfterFix(summary: String)

    var slice: DebugPipelineSlice {
        switch self {
        case .startSession:
            return .intake
        case .continueInvestigation:
            return .investigation
        case .resolveAfterFix:
            return .resolution
        }
    }

    var userFacingMessage: String {
        switch self {
        case .startSession(let summary):
            return summary.trimmingCharacters(in: .whitespacesAndNewlines)
        case .continueInvestigation:
            return "Bug reproduced. Proceed with investigation."
        case .resolveAfterFix(let summary):
            let normalized = summary.trimmingCharacters(in: .whitespacesAndNewlines)
            return normalized.isEmpty ? "Run cleanup and resolve the debug session." : normalized
        }
    }
}

extension ChatPanelView {
    @MainActor
    internal func executeDebugPipelineIntent(_ intent: DebugPipelineIntent) {
        guard let targetConversationId = conversationId else {
            appendTechnicalErrorMessage(
                "[Debug] Nessuna conversazione selezionata per avviare la pipeline debug.",
                in: nil
            )
            return
        }
        guard !pipelineIntegrationService.isRunning(for: targetConversationId) else {
            appendTechnicalErrorMessage(
                "[Debug] Una pipeline e' gia' in esecuzione per questa conversazione.",
                in: targetConversationId
            )
            return
        }
        guard let selectedProvider = providerRegistry.selectedProvider else {
            appendTechnicalErrorMessage(
                "[Debug] Nessun provider selezionato. Configura un provider in Settings.",
                in: targetConversationId
            )
            return
        }
        guard let runtimeProvider = resolveRuntimeProvider(
            selectedProvider: selectedProvider,
            shouldRunPlanInline: false,
            forcePlanInline: false,
            preferCodeReviewRuntimeProvider: false
        ) else {
            appendTechnicalErrorMessage(
                "[Debug] Impossibile risolvere il provider runtime per la pipeline debug.",
                in: targetConversationId
            )
            return
        }
        guard runtimeProvider.isAuthenticated() else {
            appendTechnicalErrorMessage(
                "[Debug] Provider \(runtimeProvider.displayName) non autenticato.",
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

        do {
            try createCheckpointBeforeTurn(
                conversationId: targetConversationId,
                workspaceContext: ctx
            )
        } catch {
            appendTechnicalErrorMessage(
                "[Debug checkpoint error: \(error.localizedDescription)]",
                in: targetConversationId
            )
            return
        }

        let userMessage = intent.userFacingMessage
        if !userMessage.isEmpty {
            chatStore.addMessage(
                ChatMessage(role: .user, content: userMessage, isStreaming: false),
                to: targetConversationId
            )
        }

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

        let workspaceHints = openFilesStore
            .openFilesForContext(linkedPaths: linkedContextPaths())
            .map(\.path)
        let request = buildDebugSessionRequest(
            for: intent,
            workspaceHints: workspaceHints
        )
        let (job, tasks) = PipelineJobFactory.fromDebugSession(
            request,
            workspace: ctx.workspacePath.path,
            providerId: runtimeProvider.id,
            slice: intent.slice
        )
        let workerAdapter = AgentWorkerAdapter(
            provider: runtimeProvider,
            context: ctx,
            jobId: job.jobId,
            directTaskExecutor: DebugNativePipelineExecutor(
                debugService: debugStore.nativeDebugService
            )
        )

        pipelineIntegrationService.executeJob(
            job,
            tasks: tasks,
            workerAdapter: workerAdapter,
            conversationId: targetConversationId,
            assistantMessageId: assistantMessageId
        )
    }

    @MainActor
    internal func buildDebugSessionRequest(
        for intent: DebugPipelineIntent,
        workspaceHints: [String]
    ) -> DebugSessionRequest {
        let baseSummary = debugStore.errorSummary.trimmingCharacters(in: .whitespacesAndNewlines)
        let errorSummary: String
        switch intent {
        case .startSession(let summary):
            let normalized = summary.trimmingCharacters(in: .whitespacesAndNewlines)
            errorSummary = normalized.isEmpty ? baseSummary : normalized
        case .continueInvestigation:
            errorSummary = baseSummary
        case .resolveAfterFix(let summary):
            let normalized = summary.trimmingCharacters(in: .whitespacesAndNewlines)
            errorSummary = normalized.isEmpty ? baseSummary : normalized
        }

        let includeNativeStages: Bool = debugStore.isNativeDebugEnabled
            && !debugStore.nativeTargetPathInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let targetPath = debugStore.nativeTargetPathInput.trimmingCharacters(in: .whitespacesAndNewlines)
        let nativeArguments = debugStore.nativeArgumentsInput
            .split(whereSeparator: { $0 == "," || $0.isNewline })
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        return DebugSessionRequest(
            errorSummary: errorSummary,
            workspaceHints: workspaceHints,
            targetPath: targetPath.isEmpty ? nil : targetPath,
            arguments: nativeArguments,
            breakpoints: debugStore.breakpoints.pipelineSpecs,
            watchExpressions: debugStore.parsedNativeWatchExpressions,
            backendPolicy: includeNativeStages ? .appleHybrid : .mcpOnly,
            includeReviewStage: true,
            includeCleanupStage: true,
            includeNativeStages: includeNativeStages
        )
    }
}
