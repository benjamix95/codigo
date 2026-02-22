import AppKit
import CoderEngine
import SwiftUI
import UniformTypeIdentifiers

enum CoderMode: String, CaseIterable {
    case agent = "Agent"
    case agentSwarm = "Agent Swarm"
    case codeReviewMultiSwarm = "Code Review"
    case plan = "Plan"
    case ide = "IDE"
    case mcpServer = "MCP Server"
}

enum PlanningState: Equatable {
    case idle
    case awaitingClarification(questions: String)
    case awaitingChoice(planContent: String, options: [PlanOption])
}

enum PlanFlowPhase: Equatable {
    case idle
    case discovery
    case awaitingClarification
    case proposalReady
    case readyToBuild
    case building
}

func canExecutePlanBuild(phase: PlanFlowPhase, choice: String, allowIdleRebuild: Bool = false) -> Bool {
    let trimmed = choice.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return false }
    if allowIdleRebuild, phase == .idle {
        return true
    }
    return phase == .proposalReady || phase == .readyToBuild
}

func normalizeBuildFinalResponse(_ text: String) -> String {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return text }
    let lines = trimmed.components(separatedBy: .newlines)
    let headerScan = lines.prefix(8).map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
    let hasEarlyOptionHeader = headerScan.contains {
        $0.hasPrefix("## opzione") || $0.hasPrefix("## option")
    }
    let hasStrictOptions = !PlanOptionsParser.parseStrict(from: trimmed).isEmpty
    let checklistItems = lines.reduce(into: 0) { partialResult, line in
        if line.range(of: #"^\s*-\s*\[\s*.\s*\]\s+"#, options: .regularExpression) != nil {
            partialResult += 1
        }
    }
    let hasTodoHeader = lines.contains {
        $0.trimmingCharacters(in: .whitespaces).lowercased().hasPrefix("## todo")
    }
    let looksLikePlanEcho = hasEarlyOptionHeader && hasStrictOptions && hasTodoHeader
        && checklistItems >= 1
    guard looksLikePlanEcho else { return text }
    var kept: [String] = []
    var skippingPlanBlock = false
    for line in lines {
        let l = line.trimmingCharacters(in: .whitespaces)
        let low = l.lowercased()
        if low.hasPrefix("## opzione") || low.hasPrefix("## option") || low.hasPrefix("## todo") {
            skippingPlanBlock = true
            continue
        }
        if skippingPlanBlock && l.hasPrefix("##") {
            skippingPlanBlock = false
        }
        if !skippingPlanBlock {
            kept.append(line)
        }
    }
    let compact = kept.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    if compact.isEmpty {
        return text
    }
    return compact
}

func nextPlanFlowPhaseForOutput(
    fullText: String,
    current: PlanFlowPhase,
    coderMode: CoderMode,
    shouldRunPlanInline: Bool
) -> PlanFlowPhase {
    PlanOutputClassifier.classify(
        fullText: fullText,
        current: current,
        coderMode: coderMode,
        shouldRunPlanInline: shouldRunPlanInline
    ).nextPhase
}

func isPlanExecutionProviderIdAllowed(_ providerId: String) -> Bool {
    ProviderSupport.isUserSelectableRealProvider(id: providerId)
}

func isPlanBuildExecutionCapableProvider(_ providerId: String, registry: ProviderRegistry) -> Bool {
    ProviderSupport.isPlanBuildExecutionCapableProvider(id: providerId, registry: registry)
}

func shouldHandlePlanKeyboardShortcut(isInputFocused: Bool) -> Bool {
    isInputFocused
}

func canStartPlanBuild(isLoading: Bool, phase: PlanFlowPhase) -> Bool {
    !isLoading && phase != .building
}

func buildPlanClarificationPrompt(_ submission: PlanClarificationSubmission) -> String {
    let orderedAnswers = submission.answers.sorted(by: { $0.questionId < $1.questionId })
    let responseBody = orderedAnswers
        .map { answer in
            var lines: [String] = [
                "\(answer.questionId). \(answer.question)",
                "   Risposta selezionata: \(answer.optionId)) \(answer.optionText)",
            ]
            let custom = answer.customResponse?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !custom.isEmpty {
                lines.append("   Risposta personalizzata (precedenza): \(custom)")
            }
            return lines.joined(separator: "\n")
        }
        .joined(separator: "\n")

    let finalNote = submission.finalMandatoryNote.trimmingCharacters(in: .whitespacesAndNewlines)
    return """
    Risposte alle domande di chiarimento del piano:
    \(responseBody)

    Nota finale obbligatoria utente: \(finalNote)
    """
}

func isPlanResumeBuild(canonicalTodos: [TodoItem]) -> Bool {
    guard !canonicalTodos.isEmpty else { return false }
    return canonicalTodos.contains(where: { $0.status == .done })
}

func buildPlanExecutionPrompt(
    workflowInstructions: String,
    executionPlanBase: String,
    planTodos: [String],
    canonicalTodos: [TodoItem]
) -> (prompt: String, isResume: Bool) {
    let isResume = isPlanResumeBuild(canonicalTodos: canonicalTodos)
    if isResume {
        let sortedPlanTodos = canonicalTodos.sorted { lhs, rhs in
            if lhs.status.rank != rhs.status.rank { return lhs.status.rank < rhs.status.rank }
            return lhs.updatedAt < rhs.updatedAt
        }
        let doneList = sortedPlanTodos
            .filter { $0.status == .done }
            .map { "- [x] \($0.title)" }
            .joined(separator: "\n")
        let pendingList = sortedPlanTodos
            .filter { $0.status != .done }
            .map { "- [ ] \($0.title)" }
            .joined(separator: "\n")
        let prompt = """
        \(workflowInstructions)

        **RIPRESA IMPLEMENTAZIONE** — Continua da dove hai lasciato.

        \(executionPlanBase)

        **Todo già completati:** Verifica che le modifiche corrispondenti siano presenti nei file. Se mancano o sono state annullate, riapplicale.
        \(doneList.isEmpty ? "(nessuno)" : doneList)

        **Todo da completare:**
        \(pendingList.isEmpty ? "(tutti completati)" : pendingList)

        Procedi verificando i done, riapplicando eventuali modifiche mancanti, poi completa i todo rimanenti.
        """
        return (prompt, true)
    }

    var prompt = "\(workflowInstructions)\n\nL'utente ha selezionato un approccio da un piano. Implementalo seguendo gli step indicati.\n\n\(executionPlanBase)"
    if !planTodos.isEmpty {
        let todoList = planTodos.enumerated().map { "\($0.offset + 1). \($0.element)" }.joined(separator: "\n")
        prompt += "\n\n**Todo da completare (in ordine):**\n\(todoList)"
    }
    return (prompt, false)
}

func shouldFallbackToPreferredProvider(
    selectedProviderIsAuthenticated: Bool,
    hasPreferredAuthenticatedFallback: Bool
) -> Bool {
    !selectedProviderIsAuthenticated && hasPreferredAuthenticatedFallback
}

func shouldSyncModeOnProviderChange(suppressForUserPicker: Bool) -> Bool {
    !suppressForUserPicker
}

func shouldShowSwarmViewOnly(for mode: CoderMode) -> Bool {
    mode == .agentSwarm
}

func shouldShowComposer(for mode: CoderMode) -> Bool {
    !shouldShowSwarmViewOnly(for: mode)
}

func shouldShowUsageFooter(for mode: CoderMode) -> Bool {
    true
}

struct ComposerFrozenTimerState: Equatable {
    let text: String
    let dismissible: Bool
    let autoHideDelay: TimeInterval?
}

func formatComposerElapsed(_ seconds: Int) -> String {
    let safeSeconds = max(0, seconds)
    let minutes = safeSeconds / 60
    let remainder = safeSeconds % 60
    return String(format: "%d:%02d", minutes, remainder)
}

func buildComposerFrozenTimerState(
    elapsedSeconds: Int,
    endedByManualStop: Bool
) -> ComposerFrozenTimerState {
    ComposerFrozenTimerState(
        text: formatComposerElapsed(elapsedSeconds),
        dismissible: !endedByManualStop,
        autoHideDelay: endedByManualStop ? 2.0 : nil
    )
}

struct PlanCommandParseResult: Equatable {
    let displayedInput: String
    let llmPromptInput: String
    let forcePlanInline: Bool
}

private func hasStrictPlanCommandPrefix(_ text: String) -> Bool {
    guard text.lowercased().hasPrefix("/plan") else { return false }
    guard text.count > 5 else { return true }
    let boundary = text.index(text.startIndex, offsetBy: 5)
    let next = text[boundary]
    return next.isWhitespace || next.isNewline
}

func shouldUseClarificationPrompt(
    coderMode: CoderMode,
    planningState: PlanningState,
    shouldRunPlanInline: Bool
) -> Bool {
    guard case .awaitingClarification = planningState else { return false }
    return coderMode == .plan || shouldRunPlanInline
}

func parsePlanCommandInput(_ rawInput: String) -> PlanCommandParseResult {
    let text = rawInput.trimmingCharacters(in: .whitespacesAndNewlines)
    guard hasStrictPlanCommandPrefix(text) else {
        return PlanCommandParseResult(
            displayedInput: text,
            llmPromptInput: text,
            forcePlanInline: false
        )
    }
    let remainder = String(text.dropFirst(5)).trimmingCharacters(in: .whitespacesAndNewlines)
    let prompt = remainder.isEmpty
        ? "Genera un planning strutturato con opzioni alternative, pro/contro e complessità."
        : remainder
    return PlanCommandParseResult(
        displayedInput: prompt,
        llmPromptInput: prompt,
        forcePlanInline: true
    )
}

func isShiftTabShortcut(flags: NSEvent.ModifierFlags, charsIgnoringModifiers: String?, keyCode: UInt16)
    -> Bool
{
    let normalized = flags.intersection(.deviceIndependentFlagsMask)
    let isBacktabChar = charsIgnoringModifiers == "\u{19}"
    let isTabKeycode = keyCode == 48
    return (isBacktabChar || isTabKeycode)
        && normalized.contains(.shift)
        && !normalized.contains(.command)
        && !normalized.contains(.option)
        && !normalized.contains(.control)
}

func isCmdShiftPShortcut(flags: NSEvent.ModifierFlags, charsIgnoringModifiers: String?) -> Bool {
    let normalized = flags.intersection(.deviceIndependentFlagsMask)
    return normalized.contains(.command)
        && normalized.contains(.shift)
        && !normalized.contains(.option)
        && !normalized.contains(.control)
        && charsIgnoringModifiers?.lowercased() == "p"
}

struct ShiftTabPlanShortcutTransition: Equatable {
    let nextInputText: String
    let shouldFocusInput: Bool
    let shouldHighlightPlanToggle: Bool
    let nextPrimedUntil: Date?
}

func evaluateShiftTabPlanShortcut(
    now: Date,
    primedUntil: Date?,
    currentInputText: String
) -> ShiftTabPlanShortcutTransition {
    if let primedUntil, primedUntil > now {
        let trimmed = currentInputText.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return ShiftTabPlanShortcutTransition(
                nextInputText: "/plan ",
                shouldFocusInput: true,
                shouldHighlightPlanToggle: false,
                nextPrimedUntil: nil
            )
        }
        if trimmed.lowercased().hasPrefix("/plan") {
            return ShiftTabPlanShortcutTransition(
                nextInputText: currentInputText,
                shouldFocusInput: true,
                shouldHighlightPlanToggle: false,
                nextPrimedUntil: nil
            )
        }
        return ShiftTabPlanShortcutTransition(
            nextInputText: "/plan " + trimmed,
            shouldFocusInput: true,
            shouldHighlightPlanToggle: false,
            nextPrimedUntil: nil
        )
    }

    return ShiftTabPlanShortcutTransition(
        nextInputText: currentInputText,
        shouldFocusInput: false,
        shouldHighlightPlanToggle: true,
        nextPrimedUntil: now.addingTimeInterval(2.5)
    )
}

struct CmdShiftPPlanShortcutTransition: Equatable {
    let nextPlanToggleEnabled: Bool
    let nextShowPlanPanel: Bool
}

func evaluateCmdShiftPPlanShortcut(
    currentPlanToggleEnabled: Bool,
    currentShowPlanPanel: Bool
) -> CmdShiftPPlanShortcutTransition {
    // 1) off/off -> attiva plan inline (badge in chat)
    if !currentPlanToggleEnabled && !currentShowPlanPanel {
        return CmdShiftPPlanShortcutTransition(
            nextPlanToggleEnabled: true,
            nextShowPlanPanel: false
        )
    }

    // 2) on/off -> apri pannello plan
    if currentPlanToggleEnabled && !currentShowPlanPanel {
        return CmdShiftPPlanShortcutTransition(
            nextPlanToggleEnabled: true,
            nextShowPlanPanel: true
        )
    }

    // 3) qualunque stato con pannello aperto -> spegni tutto
    return CmdShiftPPlanShortcutTransition(
        nextPlanToggleEnabled: false,
        nextShowPlanPanel: false
    )
}

private struct InlinePlanSummary: Equatable {
    let title: String
    let body: String
}

struct ChatPanelView: View {
    @EnvironmentObject var providerRegistry: ProviderRegistry
    @EnvironmentObject var chatStore: ChatStore
    @EnvironmentObject var projectContextStore: ProjectContextStore
    @EnvironmentObject var openFilesStore: OpenFilesStore
    @EnvironmentObject var taskActivityStore: TaskActivityStore
    @EnvironmentObject var todoStore: TodoStore
    @EnvironmentObject var swarmProgressStore: SwarmProgressStore
    @EnvironmentObject var executionController: ExecutionController
    @EnvironmentObject var providerUsageStore: ProviderUsageStore
    @EnvironmentObject var gitPanelStore: GitPanelStore
    @EnvironmentObject var planHistoryStore: PlanHistoryStore
    @Binding var selectedConversationId: UUID?
    let effectiveContext: EffectiveContext

    private var conversationId: UUID? { selectedConversationId }

    /// Loading state solo per il thread attualmente visualizzato (evita di mostrare loading di altri thread).
    private var isLoadingForCurrentConversation: Bool {
        chatStore.isLoading && chatStore.activeTaskConversationId == conversationId
    }

    @State private var coderMode: CoderMode = .agent
    @State private var inputText = ""
    @State private var isInputFocused: Bool = false
    @AppStorage("codex_path") private var codexPath = ""
    @AppStorage("codex_sandbox") private var codexSandbox = ""
    @AppStorage("codex_ask_for_approval") private var codexAskForApproval = "never"
    @AppStorage("codex_model_override") private var codexModelOverride = ""
    @AppStorage("codex_reasoning_effort") private var codexReasoningEffort = "low"
    @AppStorage("swarm_orchestrator") private var swarmOrchestrator = "openai"
    @AppStorage("swarm_worker_backend") private var swarmWorkerBackend = "codex"
    @AppStorage("swarm_auto_post_code_pipeline") private var swarmAutoPostCodePipeline = true
    @AppStorage("swarm_max_post_code_retries") private var swarmMaxPostCodeRetries = 10
    @AppStorage("swarm_max_review_loops") private var swarmMaxReviewLoops = 2
    @AppStorage("swarm_enabled_roles") private var swarmEnabledRoles =
        "planner,coder,debugger,reviewer,testWriter"
    @AppStorage("agent_auto_delegate_swarm") private var agentAutoDelegateSwarm = true
    @AppStorage("global_yolo") private var globalYolo = false
    @AppStorage("code_review_partitions") private var codeReviewPartitions = 3
    @AppStorage("code_review_analysis_only") private var codeReviewAnalysisOnly = false
    @AppStorage("code_review_max_rounds") private var codeReviewMaxRounds = 3
    @AppStorage("code_review_analysis_backend") private var codeReviewAnalysisBackend = "codex-cli"
    @AppStorage("code_review_execution_backend") private var codeReviewExecutionBackend = "codex-cli"
    @AppStorage("code_review_quick_commands_custom_json")
    private var codeReviewQuickCommandsCustomJSON = ""
    @AppStorage("openai_api_key") private var openaiApiKey = ""
    @AppStorage("openai_model") private var openaiModel = "gpt-4o-mini"
    @AppStorage("anthropic_api_key") private var anthropicApiKey = ""
    @AppStorage("anthropic_model") private var anthropicModel = "claude-sonnet-4-6"
    @AppStorage("google_api_key") private var googleApiKey = ""
    @AppStorage("google_model") private var googleModel = "gemini-2.5-pro"
    @AppStorage("openrouter_api_key") private var openrouterApiKey = ""
    @AppStorage("openrouter_model") private var openrouterModel = "anthropic/claude-sonnet-4-6"
    @State private var codexModels: [CodexModel] = []
    @State private var geminiModels: [GeminiModel] = []
    @State private var showSwarmHelp = false
    @AppStorage("task_panel_enabled") private var taskPanelEnabled = true
    @AppStorage("plan_mode_backend") private var planModeBackend = "codex"
    @AppStorage("claude_path") private var claudePath = ""
    @AppStorage("claude_model") private var claudeModel = "sonnet"
    @AppStorage("gemini_cli_path") private var geminiCliPath = ""
    @AppStorage("gemini_model_override") private var geminiModelOverride = ""
    @AppStorage("multi_cli_account_enabled") private var multiCLIAccountEnabled = false
    @AppStorage("summarize_threshold") private var summarizeThreshold = 0.8
    @AppStorage("summarize_keep_last") private var summarizeKeepLast = 6
    @AppStorage("summarize_provider") private var summarizeProvider = "openai-api"
    @AppStorage("context_scope_mode") private var contextScopeModeRaw = "auto"
    @AppStorage("plan_toggle_enabled") private var planToggleEnabled = false
    @AppStorage("flow_diagnostics_enabled") private var flowDiagnosticsEnabled = false
    @Binding var showPlanPanel: Bool
    @State private var planningState: PlanningState = .idle
    @State private var planFlowPhase: PlanFlowPhase = .idle
    @State private var activeBuildPlanConversationId: UUID?
    @State private var isProviderReady = false
    @State private var attachedImageURLs: [URL] = []
    @State private var isSelectingImage = false
    @State private var isComposerDropTargeted = false
    @State private var isConvertingHeic = false
    @State private var pasteMonitor: Any?
    @State private var isSummarizing = false
    @State private var isRewinding = false
    @State private var isPlanSummaryCollapsed = false
    @State private var isPlanTabHovered = false
    @State private var planShortcutPrimedUntil: Date?
    @State private var inlinePlanSummaries: [UUID: InlinePlanSummary] = [:]
    @State private var hasJustCompletedTask = false
    @State private var showRateLimitAlert = false
    @State private var rateLimitAlertText = ""
    @State private var isFollowingLive = true
    @State private var newEventsWhileDetached = 0
    @StateObject private var voiceInputController = VoiceInputController()
    @State private var composerFrozenTimerState: ComposerFrozenTimerState?
    @State private var composerTimerAutoHideTask: Task<Void, Never>?
    @State private var composerTaskStartDate: Date?
    @State private var lastTaskEndedByManualStop = false

    @State private var isAnyAgentProviderReady = false
    @State private var checkProviderAuthGeneration = 0
    @State private var userModeOverrideUntilConversationChange = false
    @State private var suppressModeSyncForNextProviderChange = false
    @State private var ignoreNextConversationChangeReset = false
    @State private var skipNextLoadingCompletedHandling = false
    @StateObject private var flowCoordinator = ConversationFlowCoordinator()
    @StateObject private var flowDiagnosticsStore = FlowDiagnosticsStore()
    @State private var pendingTaskActivities: [TaskActivity] = []
    @State private var pendingInstantGreps: [InstantGrepResult] = []
    @State private var taskFlushWorkItem: DispatchWorkItem?
    @State private var autoScrollWorkItem: DispatchWorkItem?
    @State private var fallbackTurnStartWorkItem: DispatchWorkItem?
    @State private var streamingReasoningText: String?
    @State private var streamingReasoningConversationId: UUID?
    private let checkpointGitStore = ConversationCheckpointGitStore()
    private let cliAccountsStore = CLIAccountsStore.shared
    private let cliAccountRouter = CLIAccountRouter.shared

    private static let imagePastedNotification = Notification.Name("CoderIDE.ImagePasted")
    private static let threadSearchAskAINotification = Notification.Name(
        "CoderIDE.ThreadSearchAskAI")
    private let topInteractiveInset: CGFloat = 22
    private let chatColumnMaxWidth: CGFloat = 900

    private var activeModeColor: Color { modeColor(for: coderMode) }
    private var activeModeGradient: LinearGradient { modeGradient(for: coderMode) }
    private var showPlanRequestIndicator: Bool {
        let trimmed = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        return planToggleEnabled || hasStrictPlanCommandPrefix(trimmed)
    }
    private var composerRuntimeStartDate: Date? {
        guard isLoadingForCurrentConversation else { return nil }
        return chatStore.taskStartDate ?? composerTaskStartDate
    }
    private var composerFrozenTimerText: String? { composerFrozenTimerState?.text }
    private var composerFrozenTimerDismissible: Bool { composerFrozenTimerState?.dismissible == true }
    private var supportsInlineActivityMode: Bool {
        coderMode == .agent || coderMode == .plan || coderMode == .codeReviewMultiSwarm
    }
    private var shouldShowTaskPanelTodoSection: Bool {
        let planFlowActive =
            coderMode == .plan
            || planToggleEnabled
            || planFlowPhase == .discovery
            || planFlowPhase == .awaitingClarification
            || planFlowPhase == .proposalReady
            || planFlowPhase == .readyToBuild
            || planFlowPhase == .building
        return !planFlowActive
    }
    private var showsSwarmViewOnly: Bool { shouldShowSwarmViewOnly(for: coderMode) }
    private var planPanelConversationId: UUID? { conversationId }

    var body: some View {
        HStack(spacing: 6) {
            VStack(spacing: 0) {
                // Keep tabs out of macOS titlebar hit-test zone while still using full-height content.
                Color.clear
                    .frame(height: topInteractiveInset)
                    .allowsHitTesting(false)
                modeTabBar
                separator
                chatHeader

                if coderMode == .agentSwarm
                    && (!swarmProgressStore.steps.isEmpty
                        || !TaskActivityStore.laneStates(from: taskActivityStore.activities).isEmpty)
                {
                    SwarmProgressView(
                        store: swarmProgressStore,
                        activities: taskActivityStore.activities,
                        isTaskRunning: isLoadingForCurrentConversation
                    )
                }

                if showsSwarmViewOnly {
                    swarmDashboardArea
                } else {
                    messagesArea
                }

                // Mantieni la task bar legacy solo quando il composer non è visibile (es. Swarm).
                if !shouldShowComposer(for: coderMode) && (isLoadingForCurrentConversation || isSummarizing) {
                    TaskControlBar(
                        chatStore: chatStore,
                        taskActivityStore: taskActivityStore,
                        executionController: executionController,
                        coderMode: coderMode,
                        isSummarizing: isSummarizing,
                        activeModeColor: activeModeColor,
                        onInterrupt: { interruptTask() }
                    )
                }

                if shouldShowComposer(for: coderMode) {
                    composerArea
                }
                if shouldShowUsageFooter(for: coderMode) {
                    usageFooterArea
                }
            }
            if showPlanPanel {
                planPanelSidebar
            }
        }
        .onChange(of: providerRegistry.selectedProviderId) { _, newId in
            if shouldSyncModeOnProviderChange(suppressForUserPicker: suppressModeSyncForNextProviderChange) {
                syncCoderModeToProvider(newId)
            } else {
                suppressModeSyncForNextProviderChange = false
            }
            checkProviderAuth()
        }
        .onChange(of: selectedConversationId) { oldId, newId in
            if ignoreNextConversationChangeReset {
                ignoreNextConversationChangeReset = false
            } else {
                userModeOverrideUntilConversationChange = false
            }
            planShortcutPrimedUntil = nil
            // Se c'è un task attivo sul thread che si sta lasciando, interrompilo.
            if let oldId, chatStore.activeTaskConversationId == oldId {
                skipNextLoadingCompletedHandling = true
                interruptTask(for: oldId)
            }
            // Quando cambi thread (incluso "New thread"), il Plan deve ripartire pulito
            // anche se il pannello non è visibile in quel momento.
            planningState = .idle
            planFlowPhase = .idle
            activeBuildPlanConversationId = nil
            planHistoryStore.setSelectedEntry(id: nil)
            syncProviderFromConversation()
        }
        .onAppear {
            syncProviderFromConversation()
            codexModels = CodexModelsCache.loadModels()
            geminiModels = GeminiModelsCache.loadModels()
            syncSwarmProvider()
            syncCodeReviewRuntimeConfig()
            syncPlanProvider()
            checkProviderAuth()
            gitPanelStore.refresh(workingDirectory: effectiveContext.primaryPath)
        }
        .onChange(of: effectiveContext.primaryPath) { _, newPath in
            gitPanelStore.refresh(workingDirectory: newPath)
        }
        .onChange(of: selectedConversationId) { _, _ in
            gitPanelStore.refresh(workingDirectory: effectiveContext.primaryPath)
            composerFrozenTimerState = nil
            composerTaskStartDate = nil
            composerTimerAutoHideTask?.cancel()
            composerTimerAutoHideTask = nil
            lastTaskEndedByManualStop = false
        }
        .onChange(of: chatStore.isLoading) { oldValue, newValue in
            if !oldValue && newValue {
                composerTaskStartDate = chatStore.taskStartDate ?? Date()
                composerFrozenTimerState = nil
                composerTimerAutoHideTask?.cancel()
                composerTimerAutoHideTask = nil
                lastTaskEndedByManualStop = false
            }
            if oldValue && !newValue {
                if skipNextLoadingCompletedHandling {
                    skipNextLoadingCompletedHandling = false
                    return
                }
                hasJustCompletedTask = true
                gitPanelStore.refresh(workingDirectory: effectiveContext.primaryPath)
                isFollowingLive = true
                newEventsWhileDetached = 0
                let startDate = composerTaskStartDate ?? Date()
                let elapsed = max(0, Int(Date().timeIntervalSince(startDate)))
                let frozen = buildComposerFrozenTimerState(
                    elapsedSeconds: elapsed,
                    endedByManualStop: lastTaskEndedByManualStop
                )
                composerFrozenTimerState = frozen
                composerTaskStartDate = nil
                composerTimerAutoHideTask?.cancel()
                composerTimerAutoHideTask = nil
                if let delay = frozen.autoHideDelay {
                    composerTimerAutoHideTask = Task { @MainActor in
                        try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                        guard !Task.isCancelled else { return }
                        if !chatStore.isLoading {
                            composerFrozenTimerState = nil
                        }
                    }
                }
                lastTaskEndedByManualStop = false
            }
        }
        .onChange(of: swarmOrchestrator) { _, _ in syncSwarmProvider() }
        .onChange(of: swarmWorkerBackend) { _, _ in syncSwarmProvider() }
        .onChange(of: swarmAutoPostCodePipeline) { _, _ in syncSwarmProvider() }
        .onChange(of: swarmMaxPostCodeRetries) { _, _ in syncSwarmProvider() }
        .onChange(of: globalYolo) { _, _ in
            syncCodexProvider()
            syncCodeReviewRuntimeConfig()
            syncPlanProvider()
        }
        .onChange(of: codeReviewPartitions) { _, _ in syncCodeReviewRuntimeConfig() }
        .onChange(of: codeReviewAnalysisOnly) { _, _ in syncCodeReviewRuntimeConfig() }
        .onChange(of: codeReviewAnalysisBackend) { _, _ in syncCodeReviewRuntimeConfig() }
        .onChange(of: codeReviewExecutionBackend) { _, _ in syncCodeReviewRuntimeConfig() }
        .sheet(isPresented: $showSwarmHelp) { AgentSwarmHelpView() }
        .fileImporter(
            isPresented: $isSelectingImage,
            allowedContentTypes: [.image, .png, .jpeg, .gif, .heic], allowsMultipleSelection: true
        ) { result in
            handleImageSelection(result: result)
        }
        .onAppear {
            installPasteMonitor()
        }
        .onDisappear {
            taskFlushWorkItem?.cancel()
            autoScrollWorkItem?.cancel()
            composerTimerAutoHideTask?.cancel()
            composerTimerAutoHideTask = nil
            voiceInputController.cancel()
            flushPendingTaskActivities()
            removePasteMonitor()
        }
        .onReceive(NotificationCenter.default.publisher(for: Self.imagePastedNotification)) {
            notification in
            if let url = notification.userInfo?["url"] as? URL {
                attachedImageURLs.append(url)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: Self.threadSearchAskAINotification)) {
            notification in
            guard let prompt = notification.userInfo?["prompt"] as? String else { return }
            if selectedConversationId == nil {
                selectedConversationId = chatStore.createConversation(
                    contextId: nil, contextFolderPath: nil, mode: coderMode)
            }
            inputText = prompt
            sendMessage()
        }
    }

    @ViewBuilder
    private var planPanelSidebar: some View {
        PlanPanelView(
            todoStore: todoStore,
            chatStore: chatStore,
            taskActivityStore: taskActivityStore,
            conversationId: planPanelConversationId,
            isCurrentConversationLoading: isLoadingForCurrentConversation,
            planningState: planningState,
            planFlowPhase: planFlowPhase,
            onClose: {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    showPlanPanel = false
                }
            },
            onSelectOption: { option, providerId in
                executeWithPlanChoice(
                    option.fullText,
                    fromPlanConversationId: planPanelConversationId,
                    providerOverrideId: providerId
                )
            },
            onCustomResponse: { response in
                executeWithPlanChoice(response, fromPlanConversationId: planPanelConversationId)
            },
            onSubmitClarificationAnswers: { answers in
                submitPlanClarificationAnswers(answers)
            },
            onBuild: { choice, providerId, allowIdleRebuild in
                executeWithPlanChoice(
                    choice,
                    fromPlanConversationId: planPanelConversationId,
                    providerOverrideId: providerId,
                    allowIdleRebuild: allowIdleRebuild
                )
            },
            onStop: {
                lastTaskEndedByManualStop = true
                interruptTask()
            }
        )
        .id(planPanelConversationId)
        .frame(minWidth: 280, idealWidth: 340, maxWidth: 400)
        .transition(.move(edge: .trailing).combined(with: .opacity))
    }

    @ViewBuilder
    private var swarmDashboardArea: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                SwarmProgressView(
                    store: swarmProgressStore,
                    activities: taskActivityStore.activities,
                    isTaskRunning: isLoadingForCurrentConversation
                )
                if taskPanelEnabled {
                    if !taskActivityStore.concreteRecentActivities(limit: 1).isEmpty || !todoStore.todos.isEmpty {
                        TaskActivityPanel(
                            chatStore: chatStore,
                            taskActivityStore: taskActivityStore,
                            todoStore: todoStore,
                            coderMode: coderMode,
                            onOpenFile: { openFilesStore.openFile($0) },
                            effectivePrimaryPath: effectiveContext.primaryPath,
                            showTodoSection: shouldShowTaskPanelTodoSection
                        )
                    } else {
                        Text("Nessuna attività swarm disponibile.")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.secondary)
                            .padding(16)
                    }
                } else {
                    Text("Pannello attività swarm nascosto.")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                        .padding(16)
                }
            }
            .padding(.top, 12)
            .padding(.bottom, 16)
            .frame(maxWidth: chatColumnMaxWidth)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.horizontal, 20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func handleImageSelection(result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            let hasHeic = urls.contains { ImageAttachmentHelper.isHeic(url: $0) }
            if hasHeic {
                isConvertingHeic = true
            }
            Task {
                let valid = urls.compactMap {
                    ImageAttachmentHelper.normalizeToPngIfNeeded(url: $0)
                }
                await MainActor.run {
                    attachedImageURLs.append(contentsOf: valid)
                    if hasHeic { isConvertingHeic = false }
                }
            }
        case .failure:
            break
        }
    }

    private func installPasteMonitor() {
        pasteMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if shouldHandlePlanKeyboardShortcut(isInputFocused: isInputFocused) && isCmdShiftP(event) {
                cyclePlanShortcutState()
                return nil
            }
            if shouldHandlePlanKeyboardShortcut(isInputFocused: isInputFocused) && isShiftTab(event) {
                handleShiftTabPlanShortcut()
                return nil
            }
            guard event.modifierFlags.contains(.command), event.charactersIgnoringModifiers == "v"
            else {
                return event
            }
            if let url = ImageAttachmentHelper.imageURLFromPasteboard() {
                DispatchQueue.main.async {
                    NotificationCenter.default.post(
                        name: Self.imagePastedNotification, object: nil, userInfo: ["url": url])
                }
                return nil
            }
            return event
        }
    }

    private func isShiftTab(_ event: NSEvent) -> Bool {
        isShiftTabShortcut(
            flags: event.modifierFlags,
            charsIgnoringModifiers: event.charactersIgnoringModifiers,
            keyCode: event.keyCode
        )
    }

    private func isCmdShiftP(_ event: NSEvent) -> Bool {
        isCmdShiftPShortcut(
            flags: event.modifierFlags,
            charsIgnoringModifiers: event.charactersIgnoringModifiers
        )
    }

    private func removePasteMonitor() {
        if let m = pasteMonitor {
            NSEvent.removeMonitor(m)
            pasteMonitor = nil
        }
    }

    private func openPlanPanelForCurrentContext(preserveHistorySelection: Bool = false) {
        // Il toggle Plan deve aprire sempre un workspace vuoto.
        if !preserveHistorySelection {
            planHistoryStore.setSelectedEntry(id: nil)
        }
        planShortcutPrimedUntil = nil
        showPlanPanel = true
    }

    private func cyclePlanShortcutState() {
        let transition = evaluateCmdShiftPPlanShortcut(
            currentPlanToggleEnabled: planToggleEnabled,
            currentShowPlanPanel: showPlanPanel
        )
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            planToggleEnabled = transition.nextPlanToggleEnabled
            if transition.nextShowPlanPanel {
                openPlanPanelForCurrentContext()
            } else {
                showPlanPanel = false
                planShortcutPrimedUntil = nil
                if !transition.nextPlanToggleEnabled {
                    planningState = .idle
                    planFlowPhase = .idle
                    planHistoryStore.setSelectedEntry(id: nil)
                }
            }
        }
        isInputFocused = true
    }

    private func handleShiftTabPlanShortcut() {
        let transition = evaluateShiftTabPlanShortcut(
            now: Date(),
            primedUntil: planShortcutPrimedUntil,
            currentInputText: inputText
        )
        inputText = transition.nextInputText
        if transition.shouldFocusInput {
            isInputFocused = true
        }
        planShortcutPrimedUntil = transition.nextPrimedUntil
        if transition.shouldHighlightPlanToggle {
            isPlanTabHovered = true
            isInputFocused = false
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                isPlanTabHovered = false
            }
        }
    }

    private func downloadPlanEntry(_ entry: PlanHistoryEntry) {
        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [.plainText]
        savePanel.canCreateDirectories = true
        let baseName = entry.title.isEmpty ? "PLAN" : entry.title
        savePanel.nameFieldStringValue = "\(baseName.replacingOccurrences(of: " ", with: "_")).md"
        savePanel.begin { response in
            guard response == .OK, let url = savePanel.url else { return }
            do {
                try entry.markdown.write(to: url, atomically: true, encoding: .utf8)
            } catch {
            }
        }
    }

    private var separator: some View {
        Rectangle()
            .fill(DesignSystem.Colors.border.opacity(0.5))
            .frame(height: 0.5)
    }

    private var chatHeader: some View {
        HStack(spacing: 8) {
            Text(chatStore.conversation(for: conversationId)?.title ?? "Nuova conversazione")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer()
            Button {
                rewindConversation()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.uturn.backward")
                        .font(.system(size: 11, weight: .medium))
                    if isRewinding {
                        ProgressView()
                            .controlSize(.small)
                    }
                }
                .foregroundStyle(
                    (chatStore.canRewind(conversationId: conversationId) && !isLoadingForCurrentConversation
                        && !isRewinding) ? .secondary : .quaternary)
            }
            .buttonStyle(.plain)
            .disabled(
                !chatStore.canRewind(conversationId: conversationId) || isLoadingForCurrentConversation
                    || isRewinding
            )
            .help("Torna al checkpoint precedente (ripristina chat e file)")
            .accessibilityLabel("Rewind checkpoint chat")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
    }

    // MARK: - Mode Tab Bar
    private var modeTabBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 2) {
                ForEach(CoderMode.allCases.filter({ $0 != .plan }), id: \.self) { mode in
                    modeTabButton(for: mode)
                }
                Spacer(minLength: 4)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
        }
    }


    @ViewBuilder
    private func modeTabButton(for mode: CoderMode) -> some View {
        let isSelected = coderMode == mode
        let color = modeColor(for: mode)
        Button {
            withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
                self.selectMode(mode)
            }
        } label: {
            VStack(spacing: 4) {
                HStack(spacing: 4) {
                    Image(systemName: modeIcon(for: mode))
                        .font(.system(size: 9.5, weight: .medium))
                    Text(mode.rawValue)
                        .font(.system(size: 11, weight: isSelected ? .semibold : .regular))
                }
                .foregroundStyle(isSelected ? color : Color.secondary.opacity(0.5))
                .padding(.horizontal, 10)
                .padding(.vertical, 4)

                // Underline indicator
                RoundedRectangle(cornerRadius: 1)
                    .fill(isSelected ? color : Color.clear)
                    .frame(height: 2)
                    .padding(.horizontal, 6)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }


    // MARK: - Messages Area
    private var messagesArea: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: 20) {
                    if let conv = chatStore.conversation(for: conversationId) {
                        let messages = conv.messages
                        let lastMsg = messages.last

                        ForEach(Array(messages.enumerated()), id: \.element.id) { item in
                            let index = item.offset
                            let message = item.element
                            let isLast = message.id == lastMsg?.id
                            let isLastAssistant = lastMsg?.role == .assistant && isLast
                            let userMessageCheckpoint = message.role == .user
                                ? chatStore.checkpoint(forMessageIndex: index, conversationId: conv.id)
                                : nil
                            let hasCheckpointForMessage = userMessageCheckpoint != nil
                            let canRewindFromMessage = message.role == .user && !isRewinding && index > 0

                            HStack(alignment: .top, spacing: 0) {
                                if message.role == .user { Spacer(minLength: 0) }
                                if message.role == .assistant,
                                    let attachment = message.planAttachment,
                                    let entry = planHistoryStore.findEntry(id: attachment.historyEntryId)
                                {
                                    PlanChatCardView(
                                        entry: entry,
                                        onDownload: { downloadPlanEntry(entry) },
                                        onDuplicate: { _ = planHistoryStore.duplicateEntry(id: entry.id) },
                                        onRebuild: {
                                            let choice = (entry.chosenPath?.isEmpty == false)
                                                ? (entry.chosenPath ?? entry.markdown)
                                                : entry.markdown
                                            executeWithPlanChoice(
                                                choice,
                                                fromPlanConversationId: entry.conversationId
                                            )
                                            planHistoryStore.markRebuilt(id: entry.id)
                                        },
                                        onOpenInPanel: {
                                            planHistoryStore.setSelectedEntry(id: entry.id)
                                            openPlanPanelForCurrentContext(
                                                preserveHistorySelection: true
                                            )
                                        },
                                        onRemove: { planHistoryStore.deleteEntry(id: entry.id) },
                                        onExpandPlan: {
                                            planHistoryStore.setSelectedEntry(id: entry.id)
                                            openPlanPanelForCurrentContext(
                                                preserveHistorySelection: true
                                            )
                                        }
                                    )
                                } else {
                                    let effectiveReasoning = (conv.id == streamingReasoningConversationId
                                        && isLastAssistant
                                        && message.isStreaming)
                                        ? streamingReasoningText
                                        : nil
                                    let showInlineActivityFeed =
                                        isLastAssistant
                                        && isLoadingForCurrentConversation
                                        && supportsInlineActivityMode
                                        && conv.id == chatStore.activeTaskConversationId
                                    let llmOrActivityStatus: String? = {
                                        if executionController.runState == .paused { return "Pausa" }
                                        return streamingDetailText(for: message, conversationId: conv.id)
                                    }()
                                    if showInlineActivityFeed {
                                        VStack(alignment: .leading, spacing: 14) {
                                            InlineActivityFeedView(
                                                activities: taskActivityStore.concreteRecentActivities(limit: 20),
                                                modeColor: activeModeColor,
                                                statusFromLLMOrActivity: llmOrActivityStatus
                                            )
                                            MessageRow(
                                                message: message,
                                                context: effectiveContext.context,
                                                modeColor: activeModeColor,
                                                isActuallyLoading: isLoadingForCurrentConversation,
                                                streamingStatusText: streamingStatusText(for: message),
                                                streamingDetailText: streamingDetailText(for: message, conversationId: conv.id),
                                                streamingReasoningText: effectiveReasoning,
                                                showStreamingBar: false,
                                                onFileClicked: { openFilesStore.openFile($0) },
                                                onRestoreCheckpoint: message.role == .user
                                                    ? { rewindToMessage(at: index, conversationId: conv.id) }
                                                    : nil,
                                                canRewind: canRewindFromMessage,
                                                hasCheckpointForRestore: hasCheckpointForMessage
                                            )
                                        }
                                    } else {
                                        let shouldHideStreamingBarOnPreviousAssistant =
                                            message.role == .assistant
                                            && !isLastAssistant
                                            && lastMsg?.role == .assistant
                                            && (lastMsg?.isStreaming ?? false)
                                            && isLoadingForCurrentConversation
                                        MessageRow(
                                            message: message,
                                            context: effectiveContext.context,
                                            modeColor: activeModeColor,
                                            isActuallyLoading: isLoadingForCurrentConversation,
                                            streamingStatusText: streamingStatusText(for: message),
                                            streamingDetailText: streamingDetailText(for: message, conversationId: conv.id),
                                            streamingReasoningText: effectiveReasoning,
                                            showStreamingBar: !shouldHideStreamingBarOnPreviousAssistant,
                                            onFileClicked: { openFilesStore.openFile($0) },
                                            onRestoreCheckpoint: message.role == .user
                                                ? { rewindToMessage(at: index, conversationId: conv.id) }
                                                : nil,
                                            canRewind: canRewindFromMessage,
                                            hasCheckpointForRestore: hasCheckpointForMessage
                                        )
                                    }
                                }
                                if message.role == .assistant { Spacer(minLength: 0) }
                            }
                            .id(message.id)
                        }
                        let hasPersistentPlanCard = messages.contains { $0.planAttachment != nil }
                        if coderMode == .agent,
                            !hasPersistentPlanCard,
                            let cid = conversationId,
                            let summary = inlinePlanSummaries[cid]
                        {
                            PlanSummaryCardView(
                                title: summary.title,
                                summaryMarkdown: summary.body,
                                isCollapsed: isPlanSummaryCollapsed,
                                onToggleCollapse: { isPlanSummaryCollapsed.toggle() },
                                onExpandPlan: {
                                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                        openPlanPanelForCurrentContext()
                                    }
                                }
                            )
                            .padding(.horizontal, 16)
                            .padding(.bottom, 8)
                            .id("plan-summary-card")
                        }
                        if coderMode == .plan, let board = chatStore.planBoard(for: conversationId) {
                            PlanBoardView(
                                board: board,
                                onSelectOption: { executeWithPlanChoice($0.fullText) }
                            )
                            .padding(.horizontal, 16)
                            .padding(.bottom, 8)
                            .id("plan-board")
                        }
                        if flowDiagnosticsEnabled,
                            let snapshot = flowDiagnosticsStore.snapshot(for: conv.id)
                        {
                            diagnosticsCard(snapshot)
                                .padding(.horizontal, 16)
                                .padding(.bottom, 8)
                                .id("flow-diagnostics-card")
                        }
                    }
                }
            }
                .padding(.top, 12).padding(.bottom, 16)
                .frame(maxWidth: chatColumnMaxWidth)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.horizontal, 20)
            .overlay {
                let conv = chatStore.conversation(for: conversationId)
                let isEmpty = conv == nil || conv!.messages.isEmpty
                if isEmpty && !isLoadingForCurrentConversation {
                    VStack(spacing: 16) {
                        if let url = Bundle.module.url(forResource: "AppLogo", withExtension: "png"),
                           let icon = NSImage(contentsOf: url) {
                            Image(nsImage: icon)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 64, height: 64)
                                .cornerRadius(14)
                                .saturation(0)
                                .opacity(0.35)
                        }
                        Text("codigo")
                            .font(.system(size: 18, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary.opacity(0.5))
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .allowsHitTesting(false)
                }
            }
            .onChange(of: chatStore.conversation(for: conversationId)?.messages.last?.content ?? "")
            { _, _ in
                if let last = chatStore.conversation(for: conversationId)?.messages.last,
                    isFollowingLive
                {
                    scheduleAutoScroll(proxy: proxy, target: last.id)
                }
            }
            .onChange(of: planningState) { _, new in
                if case .awaitingChoice = new {
                    scheduleAutoScroll(proxy: proxy, target: "plan-options", animated: true, delay: 0)
                } else if case .awaitingClarification = new {
                    scheduleAutoScroll(
                        proxy: proxy,
                        target: "plan-clarification",
                        animated: true,
                        delay: 0
                    )
                }
            }
            .onChange(of: chatStore.isLoading) { _, loading in
                if loading && isLoadingForCurrentConversation {
                    if let target = liveScrollTarget() {
                        scheduleAutoScroll(proxy: proxy, target: target, delay: 0)
                    }
                } else if !loading {
                    cancelFallbackTurnStartEvent()
                }
            }
            .onChange(of: taskActivityStore.activities.count) { _, _ in
                if isLoadingForCurrentConversation {
                    if isFollowingLive {
                        if let target = liveScrollTarget() {
                            scheduleAutoScroll(proxy: proxy, target: target)
                        }
                    } else {
                        newEventsWhileDetached += 1
                    }
                }
            }
            .simultaneousGesture(
                DragGesture(minimumDistance: 3).onChanged { _ in
                    if isLoadingForCurrentConversation {
                        isFollowingLive = false
                    }
                }
            )
            .overlay(alignment: .bottomTrailing) {
                if !isFollowingLive && isLoadingForCurrentConversation {
                    Button {
                        isFollowingLive = true
                        newEventsWhileDetached = 0
                        if let target = liveScrollTarget() {
                            scheduleAutoScroll(proxy: proxy, target: target, animated: true, delay: 0)
                        }
                        taskActivityStore.markLiveEventsSeen()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.down.circle.fill")
                                .font(.system(size: 12, weight: .semibold))
                            Text("Torna al live")
                                .font(.system(size: 11, weight: .semibold))
                            if newEventsWhileDetached > 0 {
                                Text("\(newEventsWhileDetached)")
                                    .font(.system(size: 10, weight: .bold))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.white.opacity(0.22), in: Capsule())
                            }
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(
                            DesignSystem.Colors.backgroundSecondary.opacity(0.9), in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .padding(.trailing, 14)
                    .padding(.bottom, 10)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func enableTaskPanelIfNeeded() {
        guard coderMode == .agentSwarm else { return }
        if !taskPanelEnabled {
            taskPanelEnabled = true
        }
    }

    private func scheduleFallbackTurnStartEvent(conversationId: UUID, providerId: String) {
        fallbackTurnStartWorkItem?.cancel()
        let work = DispatchWorkItem {
            Task { @MainActor in
                guard chatStore.isLoading, chatStore.activeTaskConversationId == conversationId else { return }
                guard taskActivityStore.activities.isEmpty else { return }
                recordTaskActivity(
                    type: "turn_started",
                    payload: [
                        "title": "Turno avviato",
                        "detail": "Esecuzione richiesta in corso",
                        "status": "started",
                        "group_id": "ui-fallback-\(conversationId.uuidString)",
                    ],
                    providerId: providerId
                )
            }
        }
        fallbackTurnStartWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: work)
    }

    private func cancelFallbackTurnStartEvent() {
        fallbackTurnStartWorkItem?.cancel()
        fallbackTurnStartWorkItem = nil
    }

    private func liveScrollTarget() -> AnyHashable? {
        guard isLoadingForCurrentConversation else { return nil }
        if let last = chatStore.conversation(for: conversationId)?.messages.last {
            return AnyHashable(last.id)
        }
        return nil
    }

    private func scheduleAutoScroll(
        proxy: ScrollViewProxy,
        target: AnyHashable,
        animated: Bool = false,
        delay: TimeInterval = 0.08
    ) {
        autoScrollWorkItem?.cancel()
        let work = DispatchWorkItem {
            if animated {
                withAnimation(.easeOut(duration: 0.18)) {
                    proxy.scrollTo(target, anchor: .bottom)
                }
            } else {
                proxy.scrollTo(target, anchor: .bottom)
            }
        }
        autoScrollWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func interruptTask() {
        interruptTask(for: conversationId)
    }

    private func interruptTask(for targetConversationId: UUID?) {
        let scope = executionScopeForCurrentMode()
        executionController.terminate(scope: scope)
        flowCoordinator.interrupt()
        if let cid = targetConversationId {
            let cur =
                chatStore.conversation(for: cid)?.messages.last(where: {
                    $0.role == .assistant
                })?.content ?? ""
            chatStore.updateLastAssistantMessage(
                content: cur.isEmpty
                    ? "[Interrotto dall'utente]"
                    : cur + "\n\n[Interrotto dall'utente]", in: cid)
            chatStore.setLastAssistantStreaming(false, in: cid)
            clearStreamingReasoning(for: cid)
        }
        cancelFallbackTurnStartEvent()
        chatStore.endTask(conversationId: targetConversationId)
        activeBuildPlanConversationId = nil
        if planFlowPhase == .building {
            planFlowPhase = .proposalReady
        }
    }

    private func executionScopeForCurrentMode() -> ExecutionScope {
        switch coderMode {
        case .agentSwarm: return .swarm
        case .codeReviewMultiSwarm: return .review
        case .plan: return .plan
        default: return .agent
        }
    }

    private func pauseOrResumeActiveTask() {
        let scope = executionScopeForCurrentMode()
        if executionController.runState == .paused {
            executionController.resume(scope: scope)
            taskActivityStore.markResumed()
            taskActivityStore.addActivity(
                TaskActivity(
                    type: "process_resumed",
                    title: "Processo ripreso",
                    detail: "Esecuzione ripresa dall'utente",
                    payload: [:],
                    phase: .executing,
                    isRunning: true
                )
            )
            return
        }

        executionController.pause(scope: scope)
        taskActivityStore.markPaused()
        taskActivityStore.addActivity(
            TaskActivity(
                type: "process_paused",
                title: "Processo in pausa",
                detail: "Esecuzione sospesa dall'utente",
                payload: [:],
                phase: .planning,
                isRunning: false
            )
        )
    }

    private func handleVoiceAction() {
        if chatStore.isLoading {
            return
        }
        switch voiceInputController.state {
        case .idle, .failed:
            voiceInputController.start { transcript in
                let trimmed = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { return }
                if inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    inputText = trimmed
                } else {
                    inputText = inputText + (inputText.hasSuffix(" ") ? "" : " ") + trimmed
                }
                isInputFocused = true
            }
        case .listening:
            voiceInputController.stop()
        case .requestingPermission, .transcribing:
            break
        }
    }

    @MainActor
    private func recordTaskActivity(type: String, payload: [String: String], providerId: String) {
        cancelFallbackTurnStartEvent()
        let envelope = flowCoordinator.normalizeRawEvent(
            providerId: providerId, type: type, payload: payload)
        taskActivityStore.addEnvelope(envelope)

        for event in envelope.events {
            switch event {
            case .taskActivity(let activity):
                enqueueTaskActivity(activity)
            case .instantGrep(let grep):
                enableTaskPanelIfNeeded()
                pendingInstantGreps.append(grep)
                scheduleTaskActivityFlush()
            case .todoWrite(let todo):
                enableTaskPanelIfNeeded()
                if planFlowPhase == .building {
                    _ = todoStore.upsertCanonicalOnlyFromAgent(
                        id: todo.id,
                        title: todo.title,
                        status: todo.status,
                        priority: todo.priority,
                        notes: todo.notes,
                        linkedFiles: todo.files
                    )
                } else {
                    todoStore.upsertFromAgent(
                        id: todo.id,
                        title: todo.title,
                        status: todo.status,
                        priority: todo.priority,
                        notes: todo.notes,
                        linkedFiles: todo.files
                    )
                }
            case .todoRead:
                enableTaskPanelIfNeeded()
                break
            case .planStepUpdate(let stepId, let status, let stepTitle):
                let targetId = chatStore.activeTaskConversationId ?? conversationId
                chatStore.upsertPlanStep(stepId: stepId, status: status, title: stepTitle, in: targetId)
                if let sourcePlanId = activeBuildPlanConversationId, sourcePlanId != targetId {
                    chatStore.upsertPlanStep(stepId: stepId, status: status, title: stepTitle, in: sourcePlanId)
                }
                if !showPlanPanel {
                    openPlanPanelForCurrentContext(preserveHistorySelection: true)
                }
            }
        }
    }

    @MainActor
    private func enqueueTaskActivity(_ activity: TaskActivity) {
        pendingTaskActivities.append(activity)
        scheduleTaskActivityFlush()
    }

    @MainActor
    private func scheduleTaskActivityFlush() {
        taskFlushWorkItem?.cancel()
        let work = DispatchWorkItem { @MainActor in
            flushPendingTaskActivities()
        }
        taskFlushWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1, execute: work)
    }

    @MainActor
    private func flushPendingTaskActivities() {
        guard !pendingTaskActivities.isEmpty || !pendingInstantGreps.isEmpty else { return }
        let activities = pendingTaskActivities
        let greps = pendingInstantGreps
        pendingTaskActivities.removeAll(keepingCapacity: true)
        pendingInstantGreps.removeAll(keepingCapacity: true)

        for activity in activities {
            if activity.type == "read_batch_started" || activity.type == "read_batch_completed"
                || activity.type == "web_search_started"
                || activity.type == "web_search_completed"
                || activity.type == "web_search_failed" || activity.type == "command_execution"
                || activity.type == "bash" || activity.type == "mcp_tool_call"
            {
                if taskActivityStore.shouldPreserveSwarmCriticalEvent(activity) {
                    taskActivityStore.addActivity(activity)
                } else {
                    taskActivityStore.appendOrMergeBatchEvent(activity)
                }
            } else {
                taskActivityStore.addActivity(activity)
            }
        }

        for grep in greps {
            taskActivityStore.addInstantGrep(grep)
        }
    }

    // MARK: - Composer
    @ViewBuilder
    private var composerArea: some View {
        VStack(spacing: 0) {
            ChatComposerView(
                inputText: $inputText,
                attachedImageURLs: $attachedImageURLs,
                isSelectingImage: $isSelectingImage,
                isComposerDropTargeted: $isComposerDropTargeted,
                isConvertingHeic: $isConvertingHeic,
                isInputFocused: $isInputFocused,
                isProviderReady: isProviderReady,
                isLoading: isLoadingForCurrentConversation,
                planningState: planningState,
                runtimeRunState: executionController.runState,
                runtimeTaskStartDate: composerRuntimeStartDate,
                frozenTimerText: composerFrozenTimerText,
                frozenTimerDismissible: composerFrozenTimerDismissible,
                activeModeColor: activeModeColor,
                activeModeGradient: activeModeGradient,
                inputHint: inputHint,
                providerNotReadyMessage: providerNotReadyMessage,
                quickCommandPresets: composerQuickCommandPresets,
                showCodeReviewAutofixToggle: coderMode == .codeReviewMultiSwarm,
                showPlanRequestIndicator: showPlanRequestIndicator,
                controlsRow: AnyView(modeControlsRow),
                voiceState: voiceInputController.state,
                codeReviewAutofixEnabled: Binding(
                    get: { !codeReviewAnalysisOnly },
                    set: { enabled in
                        codeReviewAnalysisOnly = !enabled
                    }
                ),
                onSend: sendMessage,
                onApplyQuickCommand: { text in
                    inputText = text
                    isInputFocused = true
                },
                onInputTextChanged: { newValue in
                    let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                    if hasStrictPlanCommandPrefix(trimmed) {
                        planToggleEnabled = true
                    }
                },
                onRunQuickCommand: { text in
                    inputText = text
                    isInputFocused = true
                    sendMessage()
                },
                onPauseResume: { pauseOrResumeActiveTask() },
                onStop: {
                    lastTaskEndedByManualStop = true
                    interruptTask()
                },
                onDismissFrozenTimer: { composerFrozenTimerState = nil },
                onVoiceAction: { handleVoiceAction() }
            )
        }
        .frame(maxWidth: chatColumnMaxWidth)
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.horizontal, 20)
        .alert("Rate Limit Raggiunto", isPresented: $showRateLimitAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(rateLimitAlertText)
        }
    }

    @ViewBuilder
    private var modeControlsRow: some View {
        ModeControlsBarView(
            providerRegistry: providerRegistry,
            chatStore: chatStore,
            coderMode: coderMode,
            conversationId: conversationId,
            isAnyAgentProviderReady: isAnyAgentProviderReady,
            codexModelOverride: $codexModelOverride,
            codexReasoningEffort: $codexReasoningEffort,
            codexSandbox: $codexSandbox,
            geminiModelOverride: $geminiModelOverride,
            swarmOrchestrator: $swarmOrchestrator,
            taskPanelEnabled: $taskPanelEnabled,
            showSwarmHelp: $showSwarmHelp,
            inputText: $inputText,
            planModeBackend: $planModeBackend,
            swarmWorkerBackend: $swarmWorkerBackend,
            openaiModel: $openaiModel,
            claudeModel: $claudeModel,
            openrouterModel: $openrouterModel,
            codexModels: codexModels,
            geminiModels: geminiModels,
            effectiveModeProviderLabel: effectiveModeProviderLabel,
            onSyncCodexProvider: syncCodexProvider,
            onSyncGeminiProvider: syncGeminiProvider,
            onSyncSwarmProvider: syncSwarmProvider,
            onSyncPlanProvider: syncPlanProvider,
            onSyncOpenRouterProvider: syncOpenRouterProvider,
            onSyncToolRuntimePolicy: syncToolRuntimePolicy,
            onUserSelectedProvider: { suppressModeSyncForNextProviderChange = true },
            onDelegateToAgent: delegateToAgent,
            attachedImageURLs: attachedImageURLs,
            planToggleEnabled: $planToggleEnabled,
            highlightPlanButton: isPlanTabHovered
        )
    }

    @ViewBuilder
    private var usageFooterArea: some View {
        UsageFooterView(
            selectedConversationId: $selectedConversationId,
            effectiveContext: effectiveContext,
            planModeBackend: planModeBackend,
            swarmWorkerBackend: swarmWorkerBackend,
            openaiModel: openaiModel,
            claudeModel: claudeModel
        )
        .frame(maxWidth: chatColumnMaxWidth)
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.horizontal, 20)
    }

    private var providerNotReadyMessage: String {
        guard let id = providerRegistry.selectedProviderId else {
            return "Nessun provider selezionato. Vai nelle Impostazioni per configurare."
        }
        switch id {
        case "openai-api": return "API Key OpenAI mancante. Configurala nelle Impostazioni."
        case "anthropic-api": return "API Key Anthropic mancante. Configurala nelle Impostazioni."
        case "google-api": return "API Key Google Gemini mancante. Configurala nelle Impostazioni."
        case "codex-cli":
            return "Codex CLI non connesso. Configuralo nelle Impostazioni → Codex CLI."
        case "claude-cli":
            return "Claude Code non trovato. Configuralo nelle Impostazioni → Claude Code."
        case "gemini-cli":
            return "Gemini CLI non trovato/non autenticato. Configuralo nelle Impostazioni."
        case "openrouter-api": return "API Key OpenRouter mancante. Configurala nelle Impostazioni."
        case "minimax-api": return "API Key MiniMax mancante. Configurala nelle Impostazioni."
        default:
            return "Provider \"\(id)\" non autenticato. Vai nelle Impostazioni per configurare."
        }
    }

    /// Provider effettivo usato dalla modalità corrente, mostrato come badge sotto al provider.
    private var effectiveModeProviderLabel: String? {
        if coderMode == .agentSwarm {
            let workerLabel: String = {
                switch swarmWorkerBackend {
                case "codex": return "Codex CLI"
                case "claude": return "Claude Code"
                case "gemini": return "Gemini CLI"
                case "openai", "openai-api": return "OpenAI API"
                case "anthropic-api": return "Anthropic API"
                case "google-api": return "Google API"
                case "openrouter-api", "openrouter": return "OpenRouter"
                case "minimax-api": return "MiniMax"
                default: return swarmWorkerBackend
                }
            }()
            return "Swarm → \(workerLabel)"
        }
        if coderMode == .codeReviewMultiSwarm {
            let execLabel: String = {
                switch codeReviewExecutionBackend {
                case "claude", "claude-cli": return "Claude CLI"
                case "codex", "codex-cli": return "Codex CLI"
                case "gemini", "gemini-cli": return "Gemini CLI"
                case "anthropic-api": return "Anthropic API"
                case "openai-api": return "OpenAI API"
                case "google-api": return "Google API"
                case "openrouter-api": return "OpenRouter API"
                case "minimax-api": return "MiniMax API"
                default: return codeReviewExecutionBackend
                }
            }()
            return "Review → esecuzione: \(execLabel)"
        }
        if coderMode == .plan {
            if let selected = providerRegistry.selectedProviderId,
               let provider = providerRegistry.provider(for: selected) {
                return "Plan → \(provider.displayName)"
            }
            return "Plan"
        }
        if coderMode == .ide {
            guard let selected = providerRegistry.selectedProviderId,
                ProviderSupport.isIDEProvider(id: selected),
                let provider = providerRegistry.provider(for: selected)
            else {
                return "IDE → Auto"
            }
            return "IDE → \(provider.displayName)"
        }
        if coderMode == .agent || coderMode == .codeReviewMultiSwarm {
            if let selected = providerRegistry.selectedProviderId,
               let provider = providerRegistry.provider(for: selected),
               ProviderSupport.isAgentCompatibleProvider(id: selected)
            {
                return provider.displayName
            }
        }
        return nil
    }

    private var inputHint: String {
        switch coderMode {
        case .agent: return "L'agente può modificare file ed eseguire comandi"
        case .agentSwarm: return "Swarm di agenti specializzati"
        case .codeReviewMultiSwarm:
            return
                "Stai usando Code Review Multi-Swarm: la richiesta verrà suddivisa in partizioni."
        case .plan: return "Piano con opzioni + risposta custom"
        case .ide: return "Modalità IDE: chat API + modifica manuale nell'editor"
        case .mcpServer: return "Invia al server MCP configurato"
        }
    }

    private var composerQuickCommandPresets: [ChatComposerView.QuickCommandPreset] {
        guard coderMode == .codeReviewMultiSwarm else { return [] }
        let defaults: [ChatComposerView.QuickCommandPreset] = [
            .init(
                id: "review-uncommitted",
                slash: "/review-uncommitted",
                label: "Audit completo non committato",
                prompt:
                    """
                    Esegui code review ultra-deep su tutte le modifiche non committate (staged, unstaged, untracked).
                    Output richiesto:
                    1) findings prioritizzati (P0-P3),
                    2) aree impattate file-per-file,
                    3) rischi regressione,
                    4) verdetto finale correttezza patch.
                    """
            ),
            .init(
                id: "review-staged-only",
                slash: "/review-staged-only",
                label: "Solo staged diff",
                prompt:
                    """
                    Esegui review SOLO sulle modifiche staged.
                    Ignora unstaged e untracked.
                    Restituisci findings severi e azionabili con priorità/confidenza.
                    """
            ),
            .init(
                id: "review-autofix",
                slash: "/review-autofix",
                label: "Review + fix automatico",
                prompt:
                    """
                    Fai review deep delle modifiche non committate e correggi direttamente tutti i bug confermati.
                    Dopo i fix esegui build/test pertinenti e riporta il changelog tecnico.
                    """
            ),
            .init(
                id: "review-autofix-commit",
                slash: "/review-autofix-commit",
                label: "Review + fix + commit",
                prompt:
                    """
                    Esegui review completa su staged/unstaged/untracked, applica i fix necessari e crea commit atomico finale.
                    Requisiti: niente modifiche superflue, build/test verdi, messaggio commit specifico.
                    """
            ),
            .init(
                id: "review-ui-realtime",
                slash: "/review-ui-realtime",
                label: "Focus UI realtime",
                prompt:
                    """
                    Focus su flussi realtime della review:
                    - stream step-by-step visibile,
                    - card read/tool/terminal aggiornate live,
                    - todo coerente e senza glitch layout.
                    Correggi i problemi trovati e valida con test/build.
                    """
            ),
        ]
        return defaults + customCodeReviewQuickPresets
    }

    private var customCodeReviewQuickPresets: [ChatComposerView.QuickCommandPreset] {
        struct CustomPreset: Decodable {
            let slash: String
            let label: String
            let prompt: String
        }
        let raw = codeReviewQuickCommandsCustomJSON.trimmingCharacters(
            in: .whitespacesAndNewlines)
        guard !raw.isEmpty, let data = raw.data(using: .utf8) else { return [] }
        guard let decoded = try? JSONDecoder().decode([CustomPreset].self, from: data) else {
            return []
        }
        return decoded.enumerated().compactMap { idx, item in
            let slash = item.slash.trimmingCharacters(in: .whitespacesAndNewlines)
            let label = item.label.trimmingCharacters(in: .whitespacesAndNewlines)
            let prompt = item.prompt.trimmingCharacters(in: .whitespacesAndNewlines)
            guard slash.hasPrefix("/"), !label.isEmpty, !prompt.isEmpty else { return nil }
            return .init(
                id: "review-custom-\(idx)-\(slash)",
                slash: slash,
                label: label,
                prompt: prompt
            )
        }
    }

    private var effectiveSandbox: String {
        codexSandbox.isEmpty
            ? (CodexConfigLoader.load().sandboxMode ?? "workspace-write") : codexSandbox
    }

    private func selectMode(_ mode: CoderMode) {
        userModeOverrideUntilConversationChange = true
        // Un solo thread per contesto: non si cambia conversazione al cambio tab.
        // Resta selectedConversationId, si aggiorna solo coderMode e provider.
        let currentConv = chatStore.conversation(for: selectedConversationId)
        switch mode {
        case .ide:
            if let preferred = currentConv?.preferredProviderId,
                ProviderSupport.isIDEProvider(id: preferred),
                providerRegistry.provider(for: preferred) != nil
            {
                providerRegistry.selectedProviderId = preferred
            } else {
                providerRegistry.selectedProviderId = ProviderSupport.preferredIDEProvider(
                    in: providerRegistry)
            }
        case .agent:
            if let preferred = currentConv?.preferredProviderId,
                ProviderSupport.isAgentCompatibleProvider(id: preferred),
                providerRegistry.provider(for: preferred) != nil
            {
                providerRegistry.selectedProviderId = preferred
            } else if let current = providerRegistry.selectedProviderId,
                ProviderSupport.isAgentCompatibleProvider(id: current)
            {
                // Mantieni provider attuale se già valido per Agent
            } else {
                providerRegistry.selectedProviderId = "codex-cli"
            }
        case .agentSwarm:
            if let preferred = currentConv?.preferredProviderId,
               ProviderSupport.isAgentCompatibleProvider(id: preferred),
               providerRegistry.provider(for: preferred) != nil {
                providerRegistry.selectedProviderId = preferred
            } else if let current = providerRegistry.selectedProviderId,
                      ProviderSupport.isAgentCompatibleProvider(id: current) {
                // keep current real provider
            } else {
                providerRegistry.selectedProviderId = "codex-cli"
            }
        case .codeReviewMultiSwarm:
            if let preferred = currentConv?.preferredProviderId,
               ProviderSupport.isAgentCompatibleProvider(id: preferred),
               providerRegistry.provider(for: preferred) != nil {
                providerRegistry.selectedProviderId = preferred
            } else if let current = providerRegistry.selectedProviderId,
                      ProviderSupport.isAgentCompatibleProvider(id: current) {
                // keep current real provider
            } else {
                providerRegistry.selectedProviderId = "codex-cli"
            }
        case .plan:
            if let preferred = currentConv?.preferredProviderId,
               ProviderSupport.isAgentCompatibleProvider(id: preferred),
               providerRegistry.provider(for: preferred) != nil {
                providerRegistry.selectedProviderId = preferred
            } else if let current = providerRegistry.selectedProviderId,
                      ProviderSupport.isAgentCompatibleProvider(id: current) {
                // keep current real provider
            } else {
                providerRegistry.selectedProviderId = "codex-cli"
            }
            planningState = .idle
            planFlowPhase = .idle
            planToggleEnabled = true
        case .mcpServer: providerRegistry.selectedProviderId = "claude-cli"
        }
        coderMode = mode
    }

    private func modeColor(for m: CoderMode) -> Color {
        switch m {
        case .agent: return DesignSystem.Colors.agentColor
        case .agentSwarm: return DesignSystem.Colors.swarmColor
        case .codeReviewMultiSwarm: return DesignSystem.Colors.reviewColor
        case .plan: return DesignSystem.Colors.planColor
        case .ide: return DesignSystem.Colors.ideColor
        case .mcpServer: return DesignSystem.Colors.mcpColor
        }
    }
    private func modeIcon(for m: CoderMode) -> String {
        switch m {
        case .agent: return "brain.head.profile"
        case .agentSwarm: return "ant.fill"
        case .codeReviewMultiSwarm: return "doc.text.magnifyingglass"
        case .plan: return "list.bullet.rectangle"
        case .ide: return "sparkles"
        case .mcpServer: return "server.rack"
        }
    }
    private func modeGradient(for m: CoderMode) -> LinearGradient {
        switch m {
        case .agent: return DesignSystem.Colors.agentGradient
        case .agentSwarm: return DesignSystem.Colors.swarmGradient
        case .codeReviewMultiSwarm: return DesignSystem.Colors.reviewGradient
        case .plan: return DesignSystem.Colors.planGradient
        case .ide: return DesignSystem.Colors.ideGradient
        case .mcpServer: return DesignSystem.Colors.mcpGradient
        }
    }

    // MARK: - Provider Sync

    private func checkProviderAuth() {
        if coderMode == .ide {
            let preferred = ProviderSupport.preferredIDEProvider(in: providerRegistry)
            if providerRegistry.selectedProviderId != preferred {
                DispatchQueue.main.async {
                    // Evita mutazioni re-entrant durante transazioni SwiftUI/AppKit (Picker/Menu).
                    if coderMode == .ide, providerRegistry.selectedProviderId != preferred {
                        providerRegistry.selectedProviderId = preferred
                    }
                }
            }
        }
        let selectedProviderId = providerRegistry.selectedProviderId
        if multiCLIAccountEnabled,
            let selectedProviderId,
            let kind = CLIProviderKind.fromProviderId(selectedProviderId)
        {
            Task { @MainActor in
                let hasAvailable =
                    cliAccountRouter.currentAvailability(provider: kind) == .available
                isProviderReady = hasAvailable
                isAnyAgentProviderReady =
                    cliAccountRouter.currentAvailability(provider: .codex) == .available
                    || cliAccountRouter.currentAvailability(provider: .claude) == .available
                    || cliAccountRouter.currentAvailability(provider: .gemini) == .available
            }
            return
        }
        checkProviderAuthGeneration += 1
        let generation = checkProviderAuthGeneration
        let provider = providerRegistry.selectedProvider
        let codexProvider = providerRegistry.provider(for: "codex-cli")
        let claudeProvider = providerRegistry.provider(for: "claude-cli")
        let geminiProvider = providerRegistry.provider(for: "gemini-cli")
        let anyRealProvider = providerRegistry.providers.first {
            ProviderSupport.isUserSelectableRealProvider(id: $0.id) && $0.isAuthenticated()
        }
        Task.detached {
            let ready = provider?.isAuthenticated() ?? false
            let anyAgentReady =
                (codexProvider?.isAuthenticated() ?? false)
                || (claudeProvider?.isAuthenticated() ?? false)
                || (geminiProvider?.isAuthenticated() ?? false)
                || (anyRealProvider != nil)
            await MainActor.run {
                guard generation == checkProviderAuthGeneration else { return }
                isProviderReady = ready
                isAnyAgentProviderReady = anyAgentReady
            }
        }
    }

    private func syncCodexProvider() {
        let p = ProviderFactory.codexProvider(
            config: providerFactoryConfig(), executionController: executionController)
        reregisterProviderPreservingSelection(id: "codex-cli", provider: p)
        syncSwarmProvider()
        syncPlanProvider()
        checkProviderAuth()
        persistCodexConfigToToml()
    }

    private func syncGeminiProvider() {
        let p = ProviderFactory.geminiProvider(
            config: providerFactoryConfig(), executionController: executionController)
        reregisterProviderPreservingSelection(id: "gemini-cli", provider: p)
        checkProviderAuth()
    }

    private func syncOpenRouterProvider() {
        let p = ProviderFactory.openRouterAPIProvider(
            config: providerFactoryConfig(), executionController: executionController)
        reregisterProviderPreservingSelection(id: "openrouter-api", provider: p)
        checkProviderAuth()
    }

    private func syncToolRuntimePolicy() {
        let cfg = providerFactoryConfig()
        let codex = ProviderFactory.codexProvider(
            config: cfg, executionController: executionController)
        reregisterProviderPreservingSelection(id: "codex-cli", provider: codex)

        if !cfg.openrouterApiKey.isEmpty {
            let p = ProviderFactory.openRouterAPIProvider(
                config: cfg, executionController: executionController)
            reregisterProviderPreservingSelection(id: "openrouter-api", provider: p)
        }
        if !cfg.openaiApiKey.isEmpty {
            let p = ProviderFactory.openAIAPIProvider(
                config: cfg, executionController: executionController)
            reregisterProviderPreservingSelection(id: "openai-api", provider: p)
        }
        if !cfg.anthropicApiKey.isEmpty {
            let p = ProviderFactory.anthropicAPIProvider(
                config: cfg, executionController: executionController)
            reregisterProviderPreservingSelection(id: "anthropic-api", provider: p)
        }
        if !cfg.googleApiKey.isEmpty {
            let p = ProviderFactory.googleAPIProvider(
                config: cfg, executionController: executionController)
            reregisterProviderPreservingSelection(id: "google-api", provider: p)
        }
        if !cfg.minimaxApiKey.isEmpty {
            let p = ProviderFactory.miniMaxAPIProvider(
                config: cfg, executionController: executionController)
            reregisterProviderPreservingSelection(id: "minimax-api", provider: p)
        }

        syncSwarmProvider()
        syncPlanProvider()
        checkProviderAuth()
        persistCodexConfigToToml()
    }

    private func reregisterProviderPreservingSelection(id: String, provider: any LLMProvider) {
        let wasSelected = providerRegistry.selectedProviderId == id
        providerRegistry.unregister(id: id)
        providerRegistry.register(provider)
        if wasSelected {
            providerRegistry.selectedProviderId = id
        }
    }

    private func persistCodexConfigToToml() {
        var cfg = CodexConfigLoader.load()
        cfg.sandboxMode = codexSandbox.isEmpty ? nil : codexSandbox
        cfg.model = codexModelOverride.isEmpty ? nil : codexModelOverride
        cfg.modelReasoningEffort = codexReasoningEffort.isEmpty ? nil : codexReasoningEffort
        CodexConfigLoader.save(cfg)
    }
    private func syncSwarmProvider() {
        // Swarm provider is created on-demand at runtime using real providers.
        checkProviderAuth()
    }
    private func syncCodeReviewRuntimeConfig() {
        // Review provider is created on-demand at runtime using real providers.
        checkProviderAuth()
    }
    private func syncProviderFromConversation() {
        guard let conv = chatStore.conversation(for: selectedConversationId), let mode = conv.mode
        else {
            syncCoderModeToProvider(providerRegistry.selectedProviderId)
            return
        }
        coderMode = mode
        planningState = .idle
        planFlowPhase = .idle
        switch mode {
        case .ide:
            if let preferred = conv.preferredProviderId,
                ProviderSupport.isIDEProvider(id: preferred),
                providerRegistry.provider(for: preferred) != nil
            {
                providerRegistry.selectedProviderId = preferred
            } else {
                providerRegistry.selectedProviderId = ProviderSupport.preferredIDEProvider(
                    in: providerRegistry)
            }
        case .agent:
            if let preferred = conv.preferredProviderId,
                ProviderSupport.isAgentCompatibleProvider(id: preferred),
                providerRegistry.provider(for: preferred) != nil
            {
                providerRegistry.selectedProviderId = preferred
            } else if let current = providerRegistry.selectedProviderId,
                ProviderSupport.isAgentCompatibleProvider(id: current)
            {
                // Mantieni provider attuale se già valido per Agent
            } else {
                providerRegistry.selectedProviderId = "codex-cli"
            }
        case .agentSwarm, .codeReviewMultiSwarm, .plan:
            if let preferred = conv.preferredProviderId,
               ProviderSupport.isAgentCompatibleProvider(id: preferred),
               providerRegistry.provider(for: preferred) != nil {
                providerRegistry.selectedProviderId = preferred
            } else if let current = providerRegistry.selectedProviderId,
                      ProviderSupport.isAgentCompatibleProvider(id: current) {
                // keep current real provider
            } else {
                providerRegistry.selectedProviderId = "codex-cli"
            }
        case .mcpServer: providerRegistry.selectedProviderId = "claude-cli"
        }
        checkProviderAuth()
    }

    private func syncCoderModeToProvider(_ pid: String?) {
        if userModeOverrideUntilConversationChange {
            return
        }
        guard let id = pid else { return }
        if ProviderSupport.isAgentCompatibleProvider(id: id) {
            coderMode = .agent
            planningState = .idle
            planFlowPhase = .idle
            return
        }
        if ProviderSupport.isIDEProvider(id: id) {
            coderMode = .ide
            planningState = .idle
            planFlowPhase = .idle
            return
        }
        switch id {
        case "codex-cli", "claude-cli", "gemini-cli":
            coderMode = .agent
            planningState = .idle
            planFlowPhase = .idle
        default: break
        }
    }
    private func syncPlanProvider() {
        // Plan mode uses selected real provider at runtime.
        checkProviderAuth()
    }

    private func providerFactoryConfig() -> ProviderFactoryConfig {
        ProviderFactoryConfig(
            openaiApiKey: openaiApiKey,
            openaiModel: openaiModel,
            anthropicApiKey: anthropicApiKey,
            anthropicModel: anthropicModel,
            googleApiKey: googleApiKey,
            googleModel: googleModel,
            minimaxApiKey: "",
            minimaxModel: "",
            openrouterApiKey: openrouterApiKey,
            openrouterModel: openrouterModel,
            codexPath: codexPath,
            codexSandbox: effectiveSandbox,
            codexSessionFullAccess: false,
            codexAskForApproval: codexAskForApproval,
            codexModelOverride: codexModelOverride,
            codexReasoningEffort: codexReasoningEffort,
            planModeBackend: planModeBackend,
            swarmOrchestrator: swarmOrchestrator,
            swarmWorkerBackend: swarmWorkerBackend,
            swarmAutoPostCodePipeline: swarmAutoPostCodePipeline,
            swarmMaxPostCodeRetries: swarmMaxPostCodeRetries,
            swarmMaxReviewLoops: swarmMaxReviewLoops,
            swarmEnabledRoles: swarmEnabledRoles,
            globalYolo: globalYolo,
            codeReviewPartitions: codeReviewPartitions,
            codeReviewAnalysisOnly: codeReviewAnalysisOnly,
            codeReviewMaxRounds: codeReviewMaxRounds,
            codeReviewAnalysisBackend: codeReviewAnalysisBackend,
            codeReviewExecutionBackend: codeReviewExecutionBackend,
            claudePath: claudePath,
            claudeModel: claudeModel,
            claudeAllowedTools: ["Read", "Edit", "Bash", "Write", "Search"],
            geminiCliPath: geminiCliPath,
            geminiModelOverride: geminiModelOverride
        )
    }

    private func trySummarizeIfNeeded(ctx: WorkspaceContext) async {
        // Con Codex CLI preferiamo il compact nativo del provider rispetto al riassunto custom.
        if summarizeProvider == "codex-cli" {
            return
        }
        guard let conv = chatStore.conversation(for: conversationId) else { return }
        let ctxPrompt = ctx.contextPrompt()
        let size = ContextEstimator.contextSize(
            for: providerRegistry.selectedProviderId, model: openaiModel)
        let (_, _, pct) = ContextEstimator.estimate(
            messages: conv.messages, contextPrompt: ctxPrompt, modelContextSize: size)
        guard pct >= summarizeThreshold else { return }
        guard let prov = providerRegistry.provider(for: summarizeProvider), prov.isAuthenticated()
        else {
            if let fallback = providerRegistry.selectedProvider, fallback.isAuthenticated() {
                await runSummarize(provider: fallback, ctx: ctx)
            }
            return
        }
        await runSummarize(provider: prov, ctx: ctx)
    }

    private func runSummarize(provider: any LLMProvider, ctx: WorkspaceContext) async {
        await MainActor.run { isSummarizing = true }
        defer { Task { @MainActor in isSummarizing = false } }
        do {
            _ = try await chatStore.summarizeConversation(
                id: conversationId, keepLast: summarizeKeepLast, provider: provider, context: ctx)
        } catch {
            // Non bloccare su errore
        }
    }

    // MARK: - Delega ad Agent (da IDE)
    private func delegateToAgent() {
        var msg = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        if msg.isEmpty {
            msg =
                chatStore.conversation(for: conversationId)?.messages.last(where: {
                    $0.role == .user
                })?.content ?? ""
        }
        guard !msg.isEmpty || !attachedImageURLs.isEmpty else { return }
        let codex = providerRegistry.provider(for: "codex-cli")
        let claude = providerRegistry.provider(for: "claude-cli")
        let agentProvider: (any LLMProvider)? =
            codex?.isAuthenticated() == true
            ? codex : (claude?.isAuthenticated() == true ? claude : nil)
        guard let agentProvider else { return }

        let currentConv = chatStore.conversation(for: conversationId)
        let contextId = currentConv?.contextId
        let contextFolderPath = currentConv?.contextFolderPath
        let agentConvId = chatStore.getOrCreateConversationForMode(
            contextId: contextId, contextFolderPath: contextFolderPath, mode: .agent)

        selectedConversationId = agentConvId
        providerRegistry.selectedProviderId = agentProvider.id
        coderMode = .agent
        inputText = msg.isEmpty ? "" : msg

        sendMessage()
    }

    // MARK: - Plan Choice Execution
    private func preferredRealProvider() -> (any LLMProvider)? {
        if let selectedId = providerRegistry.selectedProviderId,
           ProviderSupport.isPlanBuildExecutionCapableProvider(id: selectedId, registry: providerRegistry),
           let selected = providerRegistry.provider(for: selectedId),
           selected.isAuthenticated() {
            return selected
        }
        if let fallback = providerRegistry.providers.first(where: {
            ProviderSupport.isPlanBuildExecutionCapableProvider(id: $0.id, registry: providerRegistry)
                && $0.isAuthenticated()
        }) {
            return fallback
        }
        return nil
    }

    private func resolvePreferredRealProvider() -> (any LLMProvider)? {
        if let provider = preferredRealProvider() {
            return provider
        }
        appendTechnicalErrorMessage(
            "[Provider] Nessun provider execution-capable autenticato disponibile.",
            in: conversationId
        )
        return nil
    }

    @MainActor
    private func submitPlanClarificationAnswers(_ submission: PlanClarificationSubmission) {
        let orderedAnswers = submission.answers.sorted(by: { $0.questionId < $1.questionId })
        guard !orderedAnswers.isEmpty else { return }
        let finalMandatoryNote = submission.finalMandatoryNote.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !finalMandatoryNote.isEmpty else { return }
        let normalizedAnswers = orderedAnswers.map { answer in
            let normalizedCustom = answer.customResponse?.trimmingCharacters(in: .whitespacesAndNewlines)
            return PlanClarificationAnswer(
                questionId: answer.questionId,
                question: answer.question,
                optionId: answer.optionId,
                optionText: answer.optionText,
                customResponse: (normalizedCustom?.isEmpty == false) ? normalizedCustom : nil
            )
        }
        let prompt = buildPlanClarificationPrompt(
            PlanClarificationSubmission(
                answers: normalizedAnswers,
                finalMandatoryNote: finalMandatoryNote
            )
        )

        if coderMode == .agent {
            planToggleEnabled = true
        }
        inputText = prompt
        isInputFocused = false
        sendMessage()
    }

    private func executeWithPlanChoice(
        _ choice: String,
        fromPlanConversationId explicitPlanConversationId: UUID? = nil,
        providerOverrideId: String? = nil,
        allowIdleRebuild: Bool = false
    ) {
        guard canStartPlanBuild(isLoading: isLoadingForCurrentConversation, phase: planFlowPhase) else {
            return
        }
        guard canExecutePlanBuild(
            phase: planFlowPhase,
            choice: choice,
            allowIdleRebuild: allowIdleRebuild
        ) else {
            appendTechnicalErrorMessage(
                "[Plan] Build non disponibile: completa discovery/chiarimenti e genera un piano valido prima di eseguire.",
                in: conversationId
            )
            return
        }
        let planTodos = PlanOptionsParser.extractTodosFromOptionText(choice)
        guard !planTodos.isEmpty else {
            appendTechnicalErrorMessage(
                "[Plan] Build bloccata: l'opzione selezionata non contiene la sezione ## Todo.",
                in: conversationId
            )
            if !showPlanPanel {
                openPlanPanelForCurrentContext(preserveHistorySelection: true)
            }
            return
        }
        let planConversationId = explicitPlanConversationId ?? conversationId
        let provider: any LLMProvider
        let normalizedOverride = providerOverrideId?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let overrideId = normalizedOverride, !overrideId.isEmpty {
            guard isPlanExecutionProviderIdAllowed(overrideId) else {
                appendTechnicalErrorMessage(
                    "[Plan] Provider non valido per il build (\(overrideId)).",
                    in: conversationId
                )
                return
            }
            guard isPlanBuildExecutionCapableProvider(overrideId, registry: providerRegistry) else {
                appendTechnicalErrorMessage(
                    "[Plan] Provider non idoneo al build operativo (\(overrideId)). Seleziona un provider execution-capable.",
                    in: conversationId
                )
                return
            }
            if let overrideProvider = providerRegistry.provider(for: overrideId) {
                if overrideProvider.isAuthenticated() {
                    provider = overrideProvider
                } else {
                    appendTechnicalErrorMessage(
                        "[Plan] Provider selezionato nel pannello non autenticato (\(overrideProvider.displayName)). Uso provider reale di fallback.",
                        in: conversationId
                    )
                    guard let backendProvider = resolvePreferredRealProvider() else {
                        return
                    }
                    provider = backendProvider
                }
            } else {
                appendTechnicalErrorMessage(
                    "[Plan] Provider selezionato nel pannello non disponibile (\(overrideId)). Uso provider reale di fallback.",
                    in: conversationId
                )
                guard let backendProvider = resolvePreferredRealProvider() else {
                    return
                }
                provider = backendProvider
            }
        } else {
            guard let backendProvider = resolvePreferredRealProvider() else {
                return
            }
            provider = backendProvider
        }

        let currentConv = chatStore.conversation(for: conversationId)
        let contextId = currentConv?.contextId
        let contextFolderPath = currentConv?.contextFolderPath
        let agentConvId = chatStore.getOrCreateConversationForMode(
            contextId: contextId, contextFolderPath: contextFolderPath, mode: .agent)
        let ctx = effectiveContext.toWorkspaceContext(
            openFiles: openFilesStore.openFilesForContext(linkedPaths: linkedContextPaths()),
            activeSelection: nil,
            activeFilePath: openFilesStore.openFilePath,
            scopeMode: ContextScopeMode(rawValue: contextScopeModeRaw) ?? .auto
        )

        do {
            try createCheckpointBeforeTurn(conversationId: agentConvId, workspaceContext: ctx)
        } catch {
            appendTechnicalErrorMessage(
                "[Errore checkpoint: \(error.localizedDescription)]", in: conversationId)
            return
        }

        planningState = .idle
        planFlowPhase = .readyToBuild
        chatStore.choosePlanPath(choice, for: planConversationId)

        todoStore.upsertCanonicalPlanTodos(planTodos)
        let canonicalTodos = todoStore.todos.filter { $0.isPlanCanonical }
        let isResume = isPlanResumeBuild(canonicalTodos: canonicalTodos)

        if let selected = planHistoryStore.selectedEntryId {
            planHistoryStore.updateChosenPath(id: selected, chosenPath: choice)
            planHistoryStore.markRebuilt(id: selected)
        }
        chatStore.updatePlanStepStatus(stepId: "1", status: .running, in: planConversationId)
        selectedConversationId = agentConvId
        providerRegistry.selectedProviderId = provider.id
        coderMode = .agent
        planFlowPhase = .building
        activeBuildPlanConversationId = planConversationId

        chatStore.addMessage(
            ChatMessage(
                role: .user,
                content: isResume ? "Build piano ripresa: esegui i task rimanenti." : "Build piano avviata: esegui il piano selezionato.",
                isStreaming: false
            ),
            to: agentConvId)
        chatStore.addMessage(
            ChatMessage(role: .assistant, content: "", isStreaming: true), to: agentConvId)
        chatStore.beginTask(conversationId: agentConvId)
        flowDiagnosticsStore.reset(for: agentConvId)
        taskActivityStore.clear()
        scheduleFallbackTurnStartEvent(conversationId: agentConvId, providerId: provider.id)

        let planExecutionWorkflow = """
            **Workflow Todo (obbligatorio):** All'inizio di ogni task:
            1. Includi subito \(CoderIDEMarkers.showTaskPanel) per mostrare il pannello attività.
            2. NON creare una nuova lista TODO da zero: usa e aggiorna i TODO canonici del plan già presenti.
            3. Se emetti \(CoderIDEMarkers.todoWritePrefix), deve aggiornare TODO esistenti; nuovi TODO solo se strettamente necessari.
            4. Durante l'esecuzione aggiorna lo status a in_progress e poi done.
            5. Prima di concludere verifica che tutti i todo canonici del plan siano done o spiega i blocchi.
            6. Non ripetere integralmente il piano in chat: esegui, aggiorna TODO/step, e fornisci feedback operativo.
            """

        let executionPlanBase: String
        if let board = chatStore.planBoard(for: planConversationId), !board.goal.isEmpty {
            executionPlanBase = """
            **Obiettivo:** \(board.goal)

            **Piano (opzione scelta):**
            \(choice)
            """
        } else {
            executionPlanBase = "**Piano da implementare:**\n\(choice)"
        }

        let prompt = buildPlanExecutionPrompt(
            workflowInstructions: planExecutionWorkflow,
            executionPlanBase: executionPlanBase,
            planTodos: planTodos,
            canonicalTodos: canonicalTodos
        ).prompt

        Task {
            do {
                _ = try await flowCoordinator.runStream(
                    provider: provider,
                    prompt: prompt,
                    context: ctx,
                    imageURLs: nil,
                    onText: { content in
                        applyStreamingUpdate(content: content, conversationId: agentConvId)
                    },
                    onRaw: { t, p, pid in
                        handleRawStreamEvent(type: t, payload: p, providerId: pid, conversationId: agentConvId)
                    },
                    onError: { content in
                        DispatchQueue.main.async {
                            chatStore.updateLastAssistantMessage(content: content, in: agentConvId)
                        }
                    },
                    onSignal: { signal in
                        flowDiagnosticsStore.record(signal: signal, conversationId: agentConvId)
                    }
                )
                chatStore.setLastAssistantStreaming(false, in: agentConvId)
                clearStreamingReasoning(for: agentConvId)
                chatStore.updatePlanStepStatus(stepId: "1", status: .done, in: planConversationId)
                await MainActor.run { planFlowPhase = .readyToBuild }
            } catch {
                chatStore.setLastAssistantStreaming(false, in: agentConvId)
                clearStreamingReasoning(for: agentConvId)
                if isInterruptedStreamError(error) {
                    chatStore.updatePlanStepStatus(stepId: "1", status: .failed, in: planConversationId)
                    await MainActor.run {
                        flowCoordinator.interrupt()
                        planFlowPhase = .proposalReady
                    }
                } else {
                    chatStore.updatePlanStepStatus(stepId: "1", status: .failed, in: planConversationId)
                    chatStore.updateLastAssistantMessage(
                        content: userFacingStreamError(error), in: agentConvId)
                    await MainActor.run {
                        flowCoordinator.fail()
                        planFlowPhase = .proposalReady
                    }
                }
            }
            chatStore.endTask(conversationId: agentConvId)
            await MainActor.run { activeBuildPlanConversationId = nil }
        }
    }

    // MARK: - Send Message
    // MARK: - Send Message (orchestrator)

    private func sendMessage() {
        let parsedInput = parsePlanCommandInput(inputText)
        let text = parsedInput.llmPromptInput
        let displayedInput = parsedInput.displayedInput
        let forcePlanInline = parsedInput.forcePlanInline
        if forcePlanInline {
            // /plan deve solo guidare il prompt LLM, senza aprire il pannello.
            showPlanPanel = false
        }
        guard !text.isEmpty || !attachedImageURLs.isEmpty else { return }
        guard let targetConversationId = conversationId else {
            appendTechnicalErrorMessage(
                "[Errore] Nessuna conversazione selezionata. Crea o seleziona un thread e riprova.",
                in: nil
            )
            return
        }
        guard let selectedProvider = providerRegistry.selectedProvider else {
            appendTechnicalErrorMessage(
                "[Errore] Nessun provider selezionato. Configura un provider nelle Impostazioni.",
                in: targetConversationId
            )
            return
        }
        hasJustCompletedTask = false

        // Check rate limit before proceeding — show alert popup if at 100%
        if let rateLimitMsg = providerUsageStore.rateLimitAlertMessage(
            for: providerRegistry.selectedProviderId)
        {
            rateLimitAlertText = rateLimitMsg
            showRateLimitAlert = true
            return
        }

        // Aprire il pannello plan non deve attivare automaticamente la pianificazione.
        let shouldRunPlanInline = forcePlanInline || (coderMode == .agent && planToggleEnabled)
        if coderMode == .plan || shouldRunPlanInline {
            planFlowPhase = .discovery
            openPlanPanelForCurrentContext()
        } else if planFlowPhase != .building {
            planFlowPhase = .idle
        }

        // 1. Resolve the runtime provider
        guard
            let runtimeProvider = resolveRuntimeProvider(
                selectedProvider: selectedProvider,
                shouldRunPlanInline: shouldRunPlanInline,
                forcePlanInline: forcePlanInline
            )
        else {
            appendTechnicalErrorMessage(
                "[Errore] Impossibile risolvere il provider runtime per questa modalità.",
                in: targetConversationId
            )
            return
        }

        let selectedProviderAuthenticated = runtimeProvider.isAuthenticated()
        let preferredFallbackProvider = preferredRealProvider()
        var effectiveRuntimeProvider: any LLMProvider = runtimeProvider
        if shouldFallbackToPreferredProvider(
            selectedProviderIsAuthenticated: selectedProviderAuthenticated,
            hasPreferredAuthenticatedFallback: preferredFallbackProvider != nil
        ),
            let fallbackProvider = preferredFallbackProvider
        {
            effectiveRuntimeProvider = fallbackProvider
            appendTechnicalErrorMessage(
                "[Provider] \(runtimeProvider.displayName) non autenticato. Uso fallback: \(fallbackProvider.displayName).",
                in: targetConversationId
            )
        } else if !selectedProviderAuthenticated {
            let providerName = runtimeProvider.displayName
            appendTechnicalErrorMessage(
                "[Errore] Provider \(providerName) non autenticato e nessun fallback disponibile. Apri Impostazioni e autentica un provider execution-capable.",
                in: targetConversationId
            )
            return
        }

        // 2. Build workspace context & checkpoint
        let ctx = effectiveContext.toWorkspaceContext(
            openFiles: openFilesStore.openFilesForContext(linkedPaths: linkedContextPaths()),
            activeSelection: nil,
            activeFilePath: openFilesStore.openFilePath,
            scopeMode: ContextScopeMode(rawValue: contextScopeModeRaw) ?? .auto
        )
        do {
            try createCheckpointBeforeTurn(conversationId: targetConversationId, workspaceContext: ctx)
        } catch {
            appendTechnicalErrorMessage(
                "[Errore checkpoint: \(error.localizedDescription)]", in: targetConversationId)
            return
        }

        // 3. Prepare messages in chat store
        let imagePathsToStore = attachedImageURLs.map { $0.path }
        inputText = ""
        let userVisibleText = displayedInput
        let contentToStore =
            userVisibleText.isEmpty ? (attachedImageURLs.isEmpty ? "" : "[Immagine allegata]") : userVisibleText
        chatStore.addMessage(
            ChatMessage(
                role: .user, content: contentToStore, isStreaming: false,
                imagePaths: imagePathsToStore.isEmpty ? nil : imagePathsToStore),
            to: targetConversationId
        )
        chatStore.addMessage(
            ChatMessage(role: .assistant, content: "", isStreaming: true), to: targetConversationId)
        if let conv = chatStore.conversation(for: targetConversationId), let ctxId = conv.contextId {
            projectContextStore.setLastActiveConversation(
                contextId: ctxId, folderPath: conv.contextFolderPath, conversationId: conv.id)
        }
        chatStore.beginTask(conversationId: targetConversationId)
        flowDiagnosticsStore.reset(for: targetConversationId)
        taskActivityStore.clear()
        // Preserve manual todos across turns; for a new standard turn reset all agent todos,
        // including stale canonical plan tasks from previous plans/conversations.
        todoStore.clearAgentTodos(includePlanCanonical: true)
        scheduleFallbackTurnStartEvent(
            conversationId: targetConversationId,
            providerId: effectiveRuntimeProvider.id
        )
        if coderMode == .agentSwarm { swarmProgressStore.clear() }

        let imageURLsToSend = attachedImageURLs.isEmpty ? nil : attachedImageURLs
        attachedImageURLs = []

        // 4. Build the prompt with mode-specific instructions
        let prompt = buildPrompt(userText: text, shouldRunPlanInline: shouldRunPlanInline)

        // 5. Execute async stream
        let isPlanDiscoveryStreaming = (coderMode == .plan || shouldRunPlanInline) && planFlowPhase == .discovery
        Task {
            do {
                let streamResult = try await flowCoordinator.runStream(
                    provider: effectiveRuntimeProvider,
                    prompt: prompt,
                    context: ctx,
                    imageURLs: imageURLsToSend,
                    onText: { content in
                        let displayContent = isPlanDiscoveryStreaming
                            ? "Planning in corso… Apri il pannello Planning per vedere il risultato."
                            : content
                        applyStreamingUpdate(
                            content: displayContent,
                            conversationId: targetConversationId
                        )
                    },
                    onRaw: { t, p, pid in
                        handleRawStreamEvent(type: t, payload: p, providerId: pid, conversationId: targetConversationId)
                    },
                    onError: { content in
                        DispatchQueue.main.async {
                            chatStore.updateLastAssistantMessage(content: content, in: targetConversationId)
                        }
                    },
                    onSignal: { signal in
                        flowDiagnosticsStore.record(signal: signal, conversationId: targetConversationId)
                    }
                )

                let finalizedResult = try await continueIfPrematureStub(
                    initial: streamResult,
                    provider: effectiveRuntimeProvider,
                    originalPrompt: prompt,
                    context: ctx,
                    conversationId: targetConversationId,
                    hideContentDuringPlanDiscovery: isPlanDiscoveryStreaming
                )

                // 6. Handle stream completion (plan options, swarm delegation)
                await handleStreamResult(
                    conversationId: targetConversationId,
                    finalizedResult, shouldRunPlanInline: shouldRunPlanInline,
                    ctx: ctx, imageURLsToSend: imageURLsToSend, prompt: prompt
                )
            } catch {
                chatStore.setLastAssistantStreaming(false, in: targetConversationId)
                clearStreamingReasoning(for: targetConversationId)
                if isInterruptedStreamError(error) {
                    await MainActor.run {
                        flowCoordinator.interrupt()
                    }
                } else {
                    chatStore.updateLastAssistantMessage(
                        content: userFacingStreamError(error), in: targetConversationId)
                    await MainActor.run {
                        flowCoordinator.fail()
                    }
                }
            }
            chatStore.endTask(conversationId: targetConversationId)
        }
    }

    private func continueIfPrematureStub(
        initial: (fullText: String, pendingSwarmTask: String?),
        provider: any LLMProvider,
        originalPrompt: String,
        context: WorkspaceContext,
        conversationId: UUID,
        hideContentDuringPlanDiscovery: Bool = false
    ) async throws -> (fullText: String, pendingSwarmTask: String?) {
        guard initial.pendingSwarmTask == nil else { return initial }
        guard shouldAutoContinueStub(initial.fullText) else { return initial }

        let continuationPrompt = """
        Continua immediatamente la tua risposta precedente e completala fino a un risultato utile e concreto.
        Non fermarti a descrivere cosa farai: esegui il ragionamento e fornisci l'output finale.

        Richiesta originale:
        \(originalPrompt)

        Testo già inviato:
        \(initial.fullText)
        """

        let followUp = try await flowCoordinator.runStream(
            provider: provider,
            prompt: continuationPrompt,
            context: context,
            imageURLs: nil,
            onText: { deltaFull in
                let combined = initial.fullText + "\n" + deltaFull
                let displayContent = hideContentDuringPlanDiscovery
                    ? "Planning in corso… Apri il pannello Planning per vedere il risultato."
                    : combined
                applyStreamingUpdate(
                    content: displayContent,
                    conversationId: conversationId
                )
            },
            onRaw: { t, p, pid in
                handleRawStreamEvent(type: t, payload: p, providerId: pid, conversationId: conversationId)
            },
            onError: { content in
                DispatchQueue.main.async {
                    let combined = initial.fullText + "\n" + content
                    chatStore.updateLastAssistantMessage(content: combined, in: conversationId)
                }
            },
            onSignal: { signal in
                flowDiagnosticsStore.record(signal: signal, conversationId: conversationId)
            }
        )

        let combinedText = initial.fullText + "\n" + followUp.fullText
        let combinedSwarmTask = initial.pendingSwarmTask ?? followUp.pendingSwarmTask
        return (fullText: combinedText, pendingSwarmTask: combinedSwarmTask)
    }

    private func shouldAutoContinueStub(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        let wordCount = trimmed.split(whereSeparator: \.isWhitespace).count
        guard wordCount <= 40 else { return false }
        let low = trimmed.lowercased()
        let stubSignals = [
            "inizierò",
            "iniziero",
            "comincerò",
            "comincero",
            "esplorerò",
            "esplorero",
            "cercherò",
            "cerchero",
            "i'll start",
            "i will start",
            "i'll begin",
            "i will begin",
            "first, i'll",
            "first i will",
        ]
        return stubSignals.contains { low.contains($0) }
    }

    // MARK: - Resolve Runtime Provider

    private func resolveRuntimeProvider(
        selectedProvider: any LLMProvider,
        shouldRunPlanInline: Bool,
        forcePlanInline: Bool
    ) -> (any LLMProvider)? {
        // Plan/Review/Swarm usano provider reali selezionati, senza provider virtuali.
        if forcePlanInline || shouldRunPlanInline || coderMode == .plan || coderMode == .codeReviewMultiSwarm || coderMode == .agentSwarm {
            return selectedProvider
        }
        if multiCLIAccountEnabled,
            let selectedProviderId = providerRegistry.selectedProviderId,
            let kind = CLIProviderKind.fromProviderId(selectedProviderId)
        {
            // Check if all accounts are exhausted
            if case .allExhausted(let reason) = cliAccountRouter.currentAvailability(
                provider: kind)
            {
                appendTechnicalErrorMessage(
                    "[Multi-account \(kind.displayName): \(reason). Configura account o resetta i limiti nelle Impostazioni.]",
                    in: conversationId)
                return nil
            }
            let availability = cliAccountRouter.currentAvailability(provider: kind)
            if case .allExhausted = availability {
                return selectedProvider
            }
            return CLIMultiAccountProviderAdapter(
                providerKind: kind,
                id: selectedProviderId,
                displayName: selectedProvider.displayName,
                router: cliAccountRouter,
                accountsStore: cliAccountsStore,
                makeProvider: { _, env in
                    let cfg = providerFactoryConfig()
                    switch kind {
                    case .codex:
                        return ProviderFactory.codexProvider(
                            config: cfg, executionController: executionController,
                            environmentOverride: env)
                    case .claude:
                        return ProviderFactory.claudeProvider(
                            config: cfg, executionController: executionController,
                            environmentOverride: env)
                    case .gemini:
                        return ProviderFactory.geminiProvider(
                            config: cfg, executionController: executionController,
                            environmentOverride: env)
                    }
                }
            )
        }
        return selectedProvider
    }

    // MARK: - Build Prompt

    private func buildPrompt(userText: String, shouldRunPlanInline: Bool) -> String {
        var prompt =
            userText.isEmpty
            ? "[L'utente ha allegato un'immagine. Analizzala e rispondi.]" : userText

        // Plan mode: risposta a domande di chiarimento → includi contesto per proseguire
        if shouldUseClarificationPrompt(
            coderMode: coderMode,
            planningState: planningState,
            shouldRunPlanInline: shouldRunPlanInline
        ),
            case .awaitingClarification(let questions) = planningState
        {
            prompt = """
            Risposta dell'utente alle domande di chiarimento:

            \(userText.isEmpty ? "[Nessun testo inserito]" : userText)

            Le domande poste erano:
            \(questions)

            Procedi con l'analisi del codebase (usa Read, Glob e Grep per esplorare i file rilevanti) e proponi 2-4 opzioni con il formato richiesto, includendo la sezione ## Todo per ogni opzione.
            """
        }

        if coderMode == .ide {
            prompt =
                "Rispondi solo con testo. Non modificare file né eseguire comandi.\n\n" + prompt
        }
        if coderMode == .mcpServer { prompt = "[MCP Server] " + prompt }
        let isPlanningDiscoveryFlow =
            (coderMode == .plan || shouldRunPlanInline)
            && planFlowPhase != .building

        if ProviderSupport.isAgentCompatibleProvider(id: providerRegistry.selectedProviderId) {
            if isPlanningDiscoveryFlow {
                let planningInstructions = """
                **Workflow Planning (obbligatorio):**
                1. Prima di proporre qualsiasi opzione, DEVI esplorare il codebase usando Read, Glob e Grep per capire struttura, dipendenze e vincoli. Non proporre opzioni senza aver letto almeno 2-3 file rilevanti o effettuato grep/glob.
                2. Se mancano informazioni critiche dopo l'analisi, rispondi SOLO con una sezione:
                   ## Questions
                   1. Domanda?
                   A) Opzione 1
                   B) Opzione 2
                   C) Opzione 3 (facoltativa)
                   (2-4 domande al massimo, opzioni mutualmente esclusive)
                   Usa "Other..." solo quando la domanda è realmente aperta/ambigua.
                   Evita "Other..." quando le opzioni chiuse coprono già il dominio decisionale.
                3. Solo dopo aver completato l'analisi: se le informazioni sono sufficienti, proponi 2-4 opzioni concrete. Per ogni opzione includi SEMPRE:
                   ## Todo
                   - [ ] task 1
                   - [ ] task 2
                4. Non emettere marker \(CoderIDEMarkers.todoWritePrefix) o \(CoderIDEMarkers.todoRead) durante la discovery del piano.
                5. Mantieni output operativo e compatibile con parser: niente testo ambiguo fuori formato.
                """
                prompt = planningInstructions + "\n\n" + prompt
            } else {
                let baseInstructions = """
                    **Workflow Todo (obbligatorio):** All'inizio di ogni task:
                    1. Includi subito \(CoderIDEMarkers.showTaskPanel) per mostrare il pannello attività.
                    2. PRIMA di leggere file, modificare o eseguire comandi, crea la lista di todo con tutti i task necessari usando marker:
                    \(CoderIDEMarkers.todoWritePrefix)title=TASK|status=pending|priority=medium|notes=...|files=file1.swift]
                    (usa un marker per ogni task; puoi includere id=uuid per aggiornamenti successivi)
                    3. Durante l'esecuzione, aggiorna lo status: in_progress quando lavori su un task, done quando è completato.
                    4. Verifica che tutti i todo siano done prima di concludere la risposta.
                    Se devi sapere lo stato attuale dei todo, emetti \(CoderIDEMarkers.todoRead) — il contesto include la lista sotto.
                    Per aggiornare step del piano usa marker:
                    \(CoderIDEMarkers.planStepPrefix)step_id=1|status=running]
                    Se fai ricerche codice con rg, puoi emettere marker con risultati:
                    \(CoderIDEMarkers.instantGrepPrefix)query=foo|pathScope=Sources|matchesCount=3|previewLines=Sources/A.swift:12:linea]
                    Leggi i file in batch paralleli (max 8 per batch) quando serve contesto ampio. Per tracciare il batch puoi emettere:
                    \(CoderIDEMarkers.readBatchPrefix)count=8|files=FileA.swift,FileB.swift|group_id=batch-1]
                    Per ricerche web concorrenti (max 4 query in parallelo), emetti marker stato:
                    \(CoderIDEMarkers.webSearchPrefix)queryId=q1|query=swift concurrency|status=started|group_id=web-1]
                    """
                if agentAutoDelegateSwarm {
                    let swarmInstructions =
                        "Per task semplici o lineari resta in single-agent e non delegare. Usa la delega swarm solo quando l'effort richiede parallelizzazione reale o ruoli multipli (planner, coder, reviewer, debugger, testWriter, ecc.), scrivendo: \(CoderIDEMarkers.invokeSwarmPrefix)DESCRIZIONE_TASK\(CoderIDEMarkers.invokeSwarmSuffix)\n\n"
                    prompt = baseInstructions + swarmInstructions + prompt
                } else {
                    prompt = baseInstructions + "\n" + prompt
                }
                if !todoStore.todos.isEmpty {
                    let todoSection = todoStore.todos.sorted { $0.status.rank < $1.status.rank }
                        .map { t -> String in
                            let check = t.status == .done ? "x" : " "
                            return "- [\(check)] \(t.title) (\(t.status.rawValue))"
                        }
                        .joined(separator: "\n")
                    prompt += "\n\n## Todo correnti\n\(todoSection)"
                }
            }
        }
        return prompt
    }

    // MARK: - Handle Raw Stream Events

    private func handleRawStreamEvent(
        type t: String, payload p: [String: String], providerId pid: String,
        conversationId convId: UUID?
    ) {
        if t == "reasoning", let output = p["output"], !output.isEmpty {
            streamingReasoningText = output
            streamingReasoningConversationId = convId
        }
        if t == "coderide_show_task_panel" { enableTaskPanelIfNeeded() }
        if t == "swarm_steps", let s = p["steps"], !s.isEmpty {
            let n = s.split(separator: ",").map {
                String($0).trimmingCharacters(in: .whitespaces)
            }
            swarmProgressStore.setSteps(n)
        }
        if t == "agent", let title = p["title"], let detail = p["detail"] {
            if detail == "started" {
                swarmProgressStore.markStarted(name: title)
            } else if detail == "completed" {
                swarmProgressStore.markCompleted(name: title)
            }
        }
        if t == "usage", let selectedId = providerRegistry.selectedProviderId,
            selectedId.hasSuffix("-api"),
            let inpStr = p["input_tokens"], let outStr = p["output_tokens"],
            let inp = Int(inpStr), let out = Int(outStr)
        {
            providerUsageStore.addApiUsage(
                inputTokens: inp, outputTokens: out,
                model: p["model"] ?? "gpt-4o-mini")
        }
        recordTaskActivity(type: t, payload: p, providerId: pid)
    }

    private func clearStreamingReasoning(for conversationId: UUID?) {
        guard let id = conversationId, streamingReasoningConversationId == id else { return }
        streamingReasoningText = nil
        streamingReasoningConversationId = nil
    }

    private func applyStreamingUpdate(
        content: String,
        conversationId: UUID?
    ) {
        chatStore.updateLastAssistantMessage(
            content: content,
            in: conversationId,
            persistImmediately: false
        )
    }

    // MARK: - Handle Stream Result (plan options + swarm delegation)

    private func handleStreamResult(
        conversationId streamConversationId: UUID,
        _ streamResult: (fullText: String, pendingSwarmTask: String?),
        shouldRunPlanInline: Bool,
        ctx: WorkspaceContext,
        imageURLsToSend: [URL]?,
        prompt: String
    ) async {
        let full = (planFlowPhase == .building)
            ? normalizeBuildFinalResponse(streamResult.fullText)
            : streamResult.fullText
        let pendingSwarmTask = streamResult.pendingSwarmTask
        chatStore.updateLastAssistantMessage(content: full, in: streamConversationId, persistImmediately: true)
        chatStore.setLastAssistantStreaming(false, in: streamConversationId)
        clearStreamingReasoning(for: streamConversationId)
        await trySummarizeIfNeeded(ctx: ctx)

        // Handle plan options parsing
        if coderMode == .plan || shouldRunPlanInline {
            let classification = PlanOutputClassifier.classify(
                fullText: full,
                current: planFlowPhase,
                coderMode: coderMode,
                shouldRunPlanInline: shouldRunPlanInline
            )
            await MainActor.run {
                planFlowPhase = classification.nextPhase
                if let state = classification.planningState {
                    planningState = state
                }
            }
            if case .awaitingClarification = classification.planningState {
                let summaryContent = "Servono chiarimenti per procedere con il piano. Apri il pannello Planning per rispondere alle domande."
                chatStore.updateLastAssistantMessage(content: summaryContent, in: streamConversationId, persistImmediately: true)
                await MainActor.run {
                    openPlanPanelForCurrentContext(preserveHistorySelection: true)
                }
            }
            if case .awaitingChoice(_, let opts) = classification.planningState {
                let board = PlanBoard.build(from: full, options: opts)
                chatStore.setPlanBoard(board, for: streamConversationId)
                let currentConv = chatStore.conversation(for: streamConversationId)
                let parsedSummary = PlanOptionsParser.extractDisplaySummary(from: full)
                let summaryContent = "Piano pronto: \(parsedSummary.title)\n\nApri il pannello Planning per selezionare un'opzione."
                chatStore.updateLastAssistantMessage(content: summaryContent, in: streamConversationId, persistImmediately: true)
                let entry = planHistoryStore.createEntry(
                    conversationId: streamConversationId,
                    contextId: currentConv?.contextId,
                    contextFolderPath: currentConv?.contextFolderPath,
                    title: parsedSummary.title,
                    markdown: full,
                    options: opts,
                    chosenPath: board.chosenPath,
                    tags: [],
                    sourceMessageId: nil
                )
                let sourceMessageId = chatStore.attachPlanEntryToLastAssistant(
                    conversationId: streamConversationId,
                    entry: entry
                )
                planHistoryStore.updateSourceMessageId(id: entry.id, sourceMessageId: sourceMessageId)
                if shouldRunPlanInline {
                    let cid = streamConversationId
                    inlinePlanSummaries[cid] = {
                        let parsed = PlanOptionsParser.extractDisplaySummary(from: full)
                        return InlinePlanSummary(title: parsed.title, body: parsed.body)
                    }()
                    isPlanSummaryCollapsed = false
                    let contextId = currentConv?.contextId
                    let contextFolderPath = currentConv?.contextFolderPath
                    let planConvId = chatStore.getOrCreateConversationForMode(
                        contextId: contextId, contextFolderPath: contextFolderPath,
                        mode: .plan)
                    chatStore.setPlanBoard(board, for: planConvId)
                }
                await MainActor.run {
                    openPlanPanelForCurrentContext(preserveHistorySelection: true)
                }
            }
        }

        // Handle delegated swarm if pending
        if let task = pendingSwarmTask {
            let evaluation = SwarmDelegationPolicyEvaluator().evaluate(
                userPrompt: prompt,
                suggestedTask: task,
                isAutoDelegateEnabled: agentAutoDelegateSwarm,
                mode: coderMode
            )
            switch evaluation.decision {
            case .autoDelegate:
                await handleDelegatedSwarm(
                    task: task, ctx: ctx, imageURLsToSend: imageURLsToSend, prompt: prompt
                )
            case .noDelegate:
                handleRawStreamEvent(
                    type: "swarm_delegation_skipped",
                    payload: [
                        "title": "Swarm delegation skipped",
                        "detail": evaluation.reason,
                        "task": task
                    ],
                    providerId: providerRegistry.selectedProviderId ?? "agent-policy",
                    conversationId: streamConversationId
                )
            }
        }
    }

    // MARK: - Delegated Swarm Handling

    private func handleDelegatedSwarm(
        task: String,
        ctx: WorkspaceContext,
        imageURLsToSend: [URL]?,
        prompt: String
    ) async {
        guard let swarm = ProviderFactory.swarmProvider(
            config: providerFactoryConfig(),
            executionController: executionController
        ), swarm.isAuthenticated() else { return }

        let agentProviderIdBeforeSwarm = providerRegistry.selectedProviderId
        chatStore.addMessage(
            ChatMessage(
                role: .user, content: "[Delegato allo swarm] \(task)",
                isStreaming: false), to: conversationId)
        chatStore.addMessage(
            ChatMessage(role: .assistant, content: "", isStreaming: true),
            to: conversationId)
        chatStore.beginTask(conversationId: conversationId)
        taskActivityStore.clear()
        if let activeConversationId = conversationId {
            scheduleFallbackTurnStartEvent(
                conversationId: activeConversationId,
                providerId: swarm.id
            )
        }
        swarmProgressStore.clear()

        let followUpProvider: (any LLMProvider)? = {
            guard let agentId = agentProviderIdBeforeSwarm,
                ProviderSupport.isAgentCompatibleProvider(id: agentId),
                let agentProvider = providerRegistry.provider(for: agentId),
                agentProvider.isAuthenticated()
            else { return nil }
            chatStore.setLastAssistantStreaming(false, in: conversationId)
            clearStreamingReasoning(for: conversationId)
            chatStore.addMessage(
                ChatMessage(
                    role: .user, content: "[Seguito agent dopo swarm]",
                    isStreaming: false), to: conversationId)
            chatStore.addMessage(
                ChatMessage(role: .assistant, content: "", isStreaming: true),
                to: conversationId)
            return agentProvider
        }()

        await flowCoordinator.runDelegatedSwarm(
            task: task,
            swarmProvider: swarm,
            context: ctx,
            imageURLs: imageURLsToSend,
            agentFollowUpProvider: followUpProvider,
            originalPrompt: prompt,
            onSwarmText: { content in
                applyStreamingUpdate(
                    content: content,
                    conversationId: conversationId
                )
            },
            onRaw: { t, p, pid in
                handleRawStreamEvent(type: t, payload: p, providerId: pid, conversationId: conversationId)
            },
            onFollowUpText: { content in
                applyStreamingUpdate(
                    content: content,
                    conversationId: conversationId
                )
            },
            onError: { content in
                DispatchQueue.main.async {
                    chatStore.updateLastAssistantMessage(
                        content: content, in: conversationId)
                }
            }
        )
        chatStore.setLastAssistantStreaming(false, in: conversationId)
        clearStreamingReasoning(for: conversationId)
        chatStore.endTask(conversationId: conversationId)
        await trySummarizeIfNeeded(ctx: ctx)
    }

    private func createCheckpointBeforeTurn(
        conversationId: UUID?, workspaceContext: WorkspaceContext
    ) throws {
        guard let conversationId else { return }
        guard let conv = chatStore.conversation(for: conversationId), !conv.messages.isEmpty else {
            // Non creare checkpoint per il primo messaggio: non ha senso offrire rewind
            // verso una chat vuota.
            return
        }
        let pathStrings = workspaceContext.workspacePaths.map(\.path)
        do {
            let states = try checkpointGitStore.captureSnapshots(
                conversationId: conversationId, workspacePaths: pathStrings)
            chatStore.createCheckpoint(for: conversationId, gitStates: states)
        } catch {
            // Fallback cursor-style: checkpoint chat valido anche fuori da repository Git.
            if let gitError = error as? ConversationCheckpointGitStore.GitStoreError {
                switch gitError {
                case .notGitRepository:
                    chatStore.createCheckpoint(for: conversationId, gitStates: [])
                    return
                default:
                    throw error
                }
            }
            throw error
        }
    }

    private func appendTechnicalErrorMessage(_ message: String, in conversationId: UUID?) {
        let normalized = normalizeTechnicalErrorMessage(message)
        if let conversationId,
            let last = chatStore.conversation(for: conversationId)?.messages.last,
            last.role == .assistant,
            last.content == normalized
        {
            return
        }
        chatStore.addMessage(
            ChatMessage(role: .assistant, content: normalized, isStreaming: false),
            to: conversationId
        )
    }

    private func normalizeTechnicalErrorMessage(_ message: String) -> String {
        let raw = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else {
            return "[Errore] Operazione non completata. Riprova."
        }
        let lower = raw.lowercased()
        if lower.contains("coderengine.coderengineerror error 0")
            || (lower.contains("operation couldn") && lower.contains("coderengine"))
        {
            return
                "[Errore runtime] Operazione non completata dal provider CLI. Verifica autenticazione e limiti di utilizzo, poi riprova."
        }
        return raw
    }

    private func userFacingStreamError(_ error: Error) -> String {
        let detail = String(describing: error)
        let normalized = normalizeTechnicalErrorMessage(detail)
        if normalized == detail.trimmingCharacters(in: .whitespacesAndNewlines) {
            return "[Errore] \(error.localizedDescription)"
        }
        return normalized
    }

    private func isInterruptedStreamError(_ error: Error) -> Bool {
        if error is CancellationError { return true }

        let nsError = error as NSError
        if nsError.domain == NSCocoaErrorDomain, nsError.code == NSUserCancelledError {
            return true
        }

        if executionController.runState == .stopping || flowCoordinator.state == .interrupted {
            return true
        }

        let normalized = String(describing: error).lowercased()
        if normalized.contains("cancellationerror")
            || normalized.contains("cancelled")
            || normalized.contains("canceled")
        {
            return true
        }

        return false
    }

    private func rewindConversation() {
        guard !isRewinding else { return }
        guard let convId = conversationId,
            let conv = chatStore.conversation(for: convId),
            let lastUserIndex = conv.messages.lastIndex(where: { $0.role == .user })
        else { return }
        let lastUserMessage = conv.messages[lastUserIndex]
        let checkpoint = chatStore.previousCheckpoint(conversationId: convId)
        isRewinding = true

        Task {
            await MainActor.run {
                if isLoadingForCurrentConversation {
                    switch coderMode {
                    case .agentSwarm:
                        executionController.terminate(scope: .swarm)
                    case .codeReviewMultiSwarm:
                        executionController.terminate(scope: .review)
                    case .plan:
                        executionController.terminate(scope: .plan)
                    default:
                        executionController.terminate(scope: .agent)
                    }
                    flowCoordinator.interrupt()
                    chatStore.endTask(conversationId: convId)
                }
            }

            // Prova restore file solo se abbiamo snapshot git; in caso di errore continua
            // comunque con rewind chat-only (comportamento sempre disponibile).
            if let checkpoint {
                for state in checkpoint.gitStates {
                    do {
                        try checkpointGitStore.restoreSnapshot(
                            ref: state.gitSnapshotRef, gitRoot: state.gitRootPath)
                    } catch {
                        await MainActor.run {
                            appendTechnicalErrorMessage(
                                "[Rewind file parziale] \(error.localizedDescription)",
                                in: convId
                            )
                        }
                    }
                }
            }

            await MainActor.run {
                var rewound: Bool
                if let checkpoint {
                    rewound = chatStore.rewindConversationState(
                        to: checkpoint.id, conversationId: convId)
                    if rewound {
                        // Assicurati che il messaggio utente sia rimosso dalla chat
                        // (rimane solo nell'input per modifica).
                        rewound = chatStore.rewindConversationToMessageCount(
                            lastUserIndex, conversationId: convId)
                    }
                } else {
                    // Fallback senza checkpoint: rimuove ultimo turno utente+risposta.
                    rewound = chatStore.rewindConversationToMessageCount(
                        lastUserIndex, conversationId: convId)
                }
                guard rewound else {
                    appendTechnicalErrorMessage(
                        "[Errore rewind: impossibile ripristinare lo stato chat.]", in: convId)
                    isRewinding = false
                    return
                }

                // Cursor-style: riporta l'ultimo prompt utente nel composer in modifica.
                let placeholderImageOnly = "[Immagine allegata]"
                inputText =
                    (lastUserMessage.content == placeholderImageOnly) ? "" : lastUserMessage.content
                attachedImageURLs = (lastUserMessage.imagePaths ?? []).map {
                    URL(fileURLWithPath: $0)
                }
                isInputFocused = true
                planningState = .idle
                planFlowPhase = .idle
                taskActivityStore.clear()
                swarmProgressStore.clear()
                activeBuildPlanConversationId = nil
                isRewinding = false
            }
        }
    }

    private func rewindToMessage(at messageIndex: Int, conversationId: UUID) {
        guard !isRewinding else { return }
        guard let conv = chatStore.conversation(for: conversationId),
            messageIndex < conv.messages.count,
            conv.messages[messageIndex].role == .user
        else { return }
        let userMessage = conv.messages[messageIndex]
        let checkpoint = chatStore.checkpoint(forMessageIndex: messageIndex, conversationId: conversationId)
        isRewinding = true

        Task {
            await MainActor.run {
                if isLoadingForCurrentConversation {
                    switch coderMode {
                    case .agentSwarm:
                        executionController.terminate(scope: .swarm)
                    case .codeReviewMultiSwarm:
                        executionController.terminate(scope: .review)
                    case .plan:
                        executionController.terminate(scope: .plan)
                    default:
                        executionController.terminate(scope: .agent)
                    }
                    flowCoordinator.interrupt()
                    chatStore.endTask(conversationId: conversationId)
                }
            }

            if let checkpoint {
                for state in checkpoint.gitStates {
                    do {
                        try checkpointGitStore.restoreSnapshot(
                            ref: state.gitSnapshotRef, gitRoot: state.gitRootPath)
                    } catch {
                        await MainActor.run {
                            appendTechnicalErrorMessage(
                                "[Rewind file parziale] \(error.localizedDescription)",
                                in: conversationId
                            )
                        }
                    }
                }
            }

            await MainActor.run {
                // Rimuove il messaggio user dalla chat (e tutto ciò che segue) così può essere
                // modificato nell'input e reinviato senza duplicati.
                let rewound = chatStore.rewindConversationToMessageCount(
                    messageIndex, conversationId: conversationId)
                guard rewound else {
                    appendTechnicalErrorMessage(
                        "[Errore rewind: impossibile ripristinare lo stato chat.]", in: conversationId)
                    isRewinding = false
                    return
                }

                let placeholderImageOnly = "[Immagine allegata]"
                inputText =
                    (userMessage.content == placeholderImageOnly) ? "" : userMessage.content
                attachedImageURLs = (userMessage.imagePaths ?? []).map {
                    URL(fileURLWithPath: $0)
                }
                isInputFocused = true
                planningState = .idle
                planFlowPhase = .idle
                taskActivityStore.clear()
                swarmProgressStore.clear()
                activeBuildPlanConversationId = nil
                isRewinding = false
            }
        }
    }

    private func linkedContextPaths() -> [String] {
        var ordered: [String] = []
        ordered.append(contentsOf: todoStore.todos.flatMap(\.linkedFiles))
        if let board = chatStore.planBoard(for: conversationId) {
            ordered.append(contentsOf: board.steps.compactMap(\.targetFile))
        }
        var seen = Set<String>()
        let deduped = ordered.filter { seen.insert($0).inserted }
        guard let context = effectiveContext.context else { return deduped }
        return deduped.compactMap { ref in
            switch ContextPathResolver.resolve(reference: ref, context: context) {
            case .resolved(let path):
                return path
            case .ambiguous(let matches):
                return matches.first
            case .notFound:
                return nil
            }
        }
    }

    private func openChangedFile(_ repoRelativePath: String) {
        guard let gitRoot = gitPanelStore.gitRoot else { return }
        let absolutePath = URL(fileURLWithPath: gitRoot).appendingPathComponent(repoRelativePath)
            .path
        let gitService = GitService()
        openFilesStore.openFileWithDiff(absolutePath, gitRoot: gitRoot, gitService: gitService)
        selectMode(.ide)
    }

    @ViewBuilder
    private func diagnosticsCard(_ snapshot: FlowLatencySnapshot) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Diagnostics")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
            diagnosticsRow("start stream", snapshot.streamStartedAt?.formatted(date: .omitted, time: .standard))
            diagnosticsRow("first event", formattedLatency(snapshot.firstEventLatencyMs))
            diagnosticsRow("first text delta", formattedLatency(snapshot.firstTextLatencyMs))
            diagnosticsRow("completion total", formattedLatency(snapshot.totalLatencyMs))
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.45))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(DesignSystem.Colors.border.opacity(0.45), lineWidth: 0.5)
        )
    }

    @ViewBuilder
    private func diagnosticsRow(_ label: String, _ value: String?) -> some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                .foregroundStyle(.tertiary)
            Spacer()
            Text(value ?? "—")
                .font(.system(size: 10.5, design: .monospaced))
                .foregroundStyle(.secondary)
        }
    }

    private func formattedLatency(_ valueMs: Int?) -> String? {
        guard let valueMs else { return nil }
        return "\(valueMs) ms"
    }

    private func streamingStatusText(for message: ChatMessage) -> String {
        guard message.isStreaming, message.role == .assistant else { return "" }
        return TaskActivityStore.streamingStatusText(
            isPaused: executionController.runState == .paused,
            activities: taskActivityStore.activities
        )
    }

    private func streamingDetailText(for message: ChatMessage, conversationId convId: UUID?) -> String? {
        guard message.isStreaming, message.role == .assistant else { return nil }
        if let fromActivities = TaskActivityStore.streamingDetailText(
            activities: taskActivityStore.activities,
            activeOperationsCount: taskActivityStore.activeOperationsCount
        ) {
            return fromActivities
        }
        if let fromContent = ChatStore.extractLastOperationalThinkingLine(from: message.content) {
            return fromContent
        }
        if convId == streamingReasoningConversationId, let reasoning = streamingReasoningText, !reasoning.isEmpty {
            let lastLine = reasoning.split(separator: "\n", omittingEmptySubsequences: false)
                .last?
                .trimmingCharacters(in: .whitespaces) ?? ""
            if !lastLine.isEmpty {
                return lastLine.count > 80 ? String(lastLine.prefix(77)) + "…" : lastLine
            }
        }
        return nil
    }
}
