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
    case analyzing          // Phase 1: codebase analysis in progress
    case questioning        // Phase 2: generating/awaiting clarification questions
    case generating         // Phase 3: generating structured plan options
    case proposalReady
    case readyToBuild
    case building
}

enum ToolTraceTurnOutcome: Equatable {
    case success
    case failed
    case aborted
}

func toolTraceTurnOutcome(for flowState: ConversationFlowCoordinator.State) -> ToolTraceTurnOutcome {
    switch flowState {
    case .error:
        return .failed
    case .interrupted:
        return .aborted
    default:
        return .success
    }
}

func autoTodoFinalStatus(for outcome: ToolTraceTurnOutcome) -> TodoStatus {
    switch outcome {
    case .success:
        return .done
    case .failed, .aborted:
        return .blocked
    }
}

func rolloverAutoTodoOutcome(
    for flowState: ConversationFlowCoordinator.State,
    hasRunningOperations: Bool
) -> ToolTraceTurnOutcome {
    switch flowState {
    case .error:
        return .failed
    case .interrupted:
        return .aborted
    case .streaming, .delegatedSwarm, .followUp:
        // A new turn started before the previous one reached completion.
        return .aborted
    case .idle, .completed:
        return hasRunningOperations ? .aborted : .success
    }
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
        $0.hasPrefix("## option")
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
        if low.hasPrefix("## option") || low.hasPrefix("## todo") {
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
                "   Selected answer: \(answer.optionId)) \(answer.optionText)",
            ]
            let custom = answer.customResponse?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !custom.isEmpty {
                lines.append("   Custom response (overrides selection): \(custom)")
            }
            return lines.joined(separator: "\n")
        }
        .joined(separator: "\n")

    let finalNote = submission.finalNote.trimmingCharacters(in: .whitespacesAndNewlines)
    let finalNoteLine: String
    if finalNote.isEmpty {
        finalNoteLine = "Final user note: (omitted)"
    } else {
        finalNoteLine = "Final user note (optional): \(finalNote)"
    }
    return """
    Answers to plan clarification questions:
    \(responseBody)

    \(finalNoteLine)

    After these answers, run additional codebase analysis using the selected constraints.
    If new ambiguities appear, you may ask follow-up questions again using ## Questions.
    Propose final options (## Option + ## Todo) only when you are fully confident.
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

        **IMPLEMENTATION RESUME** - Continue from where you left off.

        \(executionPlanBase)

        **Already completed todos:** Verify the corresponding file changes are present. If missing or reverted, re-apply them.
        \(doneList.isEmpty ? "(none)" : doneList)

        **Remaining todos:**
        \(pendingList.isEmpty ? "(all completed)" : pendingList)

        Proceed by validating completed tasks, restoring any missing ones, then finishing the remaining tasks.
        """
        return (prompt, true)
    }

    var prompt = "\(workflowInstructions)\n\nThe user selected a plan option. Implement it by following TODOs EXACTLY in order. TODOs are mandatory: do not deviate, skip, or reorder.\n\n\(executionPlanBase)"
    if !planTodos.isEmpty {
        let todoList = planTodos.enumerated().map { "\($0.offset + 1). [ ] \($0.element)" }.joined(separator: "\n")
        prompt += "\n\n**MANDATORY TODOs (follow in order, complete ALL):**\n\(todoList)\n\nREMINDER: each TODO must go pending -> in_progress -> done. Do not finish until all are done."
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
    false
}

func shouldShowComposer(for mode: CoderMode) -> Bool {
    !shouldShowSwarmViewOnly(for: mode)
}

func shouldShowUsageFooter(for mode: CoderMode) -> Bool {
    true
}

func shouldEnableTaskPanelForMode(_ mode: CoderMode) -> Bool {
    switch mode {
    case .agent, .plan, .codeReviewMultiSwarm, .agentSwarm:
        return true
    case .ide, .mcpServer:
        return false
    }
}

func resolveDebugFlowPhaseAlias(_ rawValue: String?) -> DebugFlowPhase? {
    guard let rawValue else { return nil }
    let normalized = rawValue
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .lowercased()
    if let exact = DebugFlowPhase(rawValue: normalized) {
        return exact
    }
    switch normalized {
    case "analyze", "analyzing", "analysis", "describe":
        return .describing
    case "reproduce", "reproducing":
        return .reproducing
    case "fix", "fixing":
        return .fixing
    case "instrument", "instrumenting":
        return .instrumenting
    case "verify", "verifying":
        return .verifying
    case "resolve", "resolved":
        return .resolved
    default:
        return nil
    }
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
        ? "Generate a structured plan with alternative options, pros/cons, and complexity."
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
    // 1) off/off -> enable inline Plan (chat badge)
    if !currentPlanToggleEnabled && !currentShowPlanPanel {
        return CmdShiftPPlanShortcutTransition(
            nextPlanToggleEnabled: true,
            nextShowPlanPanel: false
        )
    }

    // 2) on/off -> open plan panel
    if currentPlanToggleEnabled && !currentShowPlanPanel {
        return CmdShiftPPlanShortcutTransition(
            nextPlanToggleEnabled: true,
            nextShowPlanPanel: true
        )
    }

    // 3) any state with panel open -> turn off everything
    return CmdShiftPPlanShortcutTransition(
        nextPlanToggleEnabled: false,
        nextShowPlanPanel: false
    )
}

enum PlanPanelAutoOpenTrigger: Equatable {
    case flowStarted
    case planStepUpdate
    case awaitingClarification
    case awaitingChoice
}

func shouldAutoOpenPlanPanel(trigger: PlanPanelAutoOpenTrigger) -> Bool {
    switch trigger {
    case .awaitingClarification, .awaitingChoice:
        return true
    case .flowStarted, .planStepUpdate:
        return false
    }
}

func resolveShouldRunPlanInline(
    forcePlanInline: Bool,
    coderMode: CoderMode,
    planToggleEnabled: Bool
) -> Bool {
    forcePlanInline || (coderMode == .agent && planToggleEnabled)
}

private struct InlinePlanSummary: Equatable {
    let title: String
    let body: String
}

private struct ToolTraceTurnContext: Equatable {
    let conversationId: UUID
    let assistantMessageId: UUID
    let providerId: String
}

private struct PolicyAckState: Equatable {
    let expectedHash: String
    var acknowledgedHash: String?
    var violationEmitted: Bool = false

    var isSatisfied: Bool {
        acknowledgedHash == expectedHash
    }
}

struct ChatPanelView: View {
    @EnvironmentObject var providerRegistry: ProviderRegistry
    @EnvironmentObject var chatStore: ChatStore
    @EnvironmentObject var workspaceStore: WorkspaceStore
    @EnvironmentObject var projectContextStore: ProjectContextStore
    @EnvironmentObject var openFilesStore: OpenFilesStore
    @EnvironmentObject var taskActivityStore: TaskActivityStore
    @EnvironmentObject var toolTraceStore: ToolTraceStore
    @EnvironmentObject var todoStore: TodoStore
    @EnvironmentObject var swarmProgressStore: SwarmProgressStore
    @EnvironmentObject var executionController: ExecutionController
    @EnvironmentObject var providerUsageStore: ProviderUsageStore
    @EnvironmentObject var gitPanelStore: GitPanelStore
    @EnvironmentObject var planHistoryStore: PlanHistoryStore
    @Binding var selectedConversationId: UUID?
    let effectiveContext: EffectiveContext

    private var conversationId: UUID? { selectedConversationId }

    /// Loading state only for the currently displayed thread (avoids showing loading for other threads).
    private var isLoadingForCurrentConversation: Bool {
        chatStore.isTaskActive(for: conversationId)
    }

    @State private var coderMode: CoderMode = .agent
    @State private var inputText = ""
    @State private var isInputFocused: Bool = false
    @AppStorage("codex_path") private var codexPath = ""
    @AppStorage("codex_sandbox") private var codexSandbox = ""
    @AppStorage("codex_ask_for_approval") private var codexAskForApproval = "never"
    @AppStorage("codex_model_override") private var codexModelOverride = ""
    @AppStorage("codex_reasoning_effort") private var codexReasoningEffort = "low"
    @AppStorage("codex_model_provider") private var codexModelProvider = ""
    @AppStorage("codex_prefer_responses_wire_api")
    private var codexPreferResponsesWireAPI = false
    @AppStorage("swarm_orchestrator") private var swarmOrchestrator = "auto"
    @AppStorage("swarm_worker_backend") private var swarmWorkerBackend = "auto"
    @AppStorage("swarm_provider_auto_migrated_v1") private var swarmProviderAutoMigrated = false
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
    @AppStorage("claude_model") private var claudeModel = "claude-sonnet-4-6"
    @AppStorage("claude_allowed_tools") private var claudeAllowedTools = "Read,Edit,Bash,Write,Search"
    @AppStorage("gemini_cli_path") private var geminiCliPath = ""
    @AppStorage("gemini_model_override") private var geminiModelOverride = ""
    @AppStorage("unified_tool_runtime_enabled") private var unifiedToolRuntimeEnabled = true
    @AppStorage("agents_hard_block_enabled") private var agentsHardBlockEnabled = true
    @AppStorage("web_search_provider") private var webSearchProvider = "duckduckgo"
    @AppStorage("brave_search_api_key") private var braveSearchApiKey = ""
    @AppStorage("tavily_api_key") private var tavilyApiKey = ""
    @AppStorage("serper_api_key") private var serperApiKey = ""
    @AppStorage("multi_cli_account_enabled") private var multiCLIAccountEnabled = false
    @AppStorage("summarize_threshold") private var summarizeThreshold = 0.8
    @AppStorage("summarize_keep_last") private var summarizeKeepLast = 6
    @AppStorage("summarize_provider") private var summarizeProvider = "openai-api"
    @AppStorage("context_scope_mode") private var contextScopeModeRaw = "auto"
    @AppStorage("plan_panel_width") private var planPanelWidthStorage: Double = 320
    @AppStorage("debug_panel_width") private var debugPanelWidthStorage: Double = 340
    @AppStorage("swarm_panel_width") private var swarmPanelWidthStorage: Double = 360
    @AppStorage("code_review_panel_width") private var codeReviewPanelWidthStorage: Double = 380
    @State private var planToggleEnabled = false
    @State private var debugToggleEnabled = false
    @Binding var showPlanPanel: Bool
    @Binding var showDebugPanel: Bool
    @Binding var showSwarmPanel: Bool
    @Binding var showCodeReviewPanel: Bool
    @State private var planPanelPresentationSource: PlanPanelPresentationSource = .manualDeepLink
    @ObservedObject var debugStore: DebugStore
    @State private var planningState: PlanningState = .idle
    @State private var planFlowPhase: PlanFlowPhase = .idle
    @State private var planAnalysisContext: String = ""
    @State private var planUserRequest: String = ""
    @State private var planClarificationAnswers: String = ""
    @State private var planStreamingContent: String = ""
    @State private var activeBuildPlanConversationId: UUID?
    @State private var suppressedEmptyBuildAssistantMessageIds: Set<UUID> = []
    @State private var isProviderReady = false
    @State private var attachedComposerAttachments: [ComposerAttachment] = []
    @State private var isSelectingImage = false
    @State private var isComposerDropTargeted = false
    @State private var isConvertingHeic = false
    @State private var pasteMonitor: Any?
    @State private var isSummarizing = false
    @State private var isRewinding = false
    @State private var isPlanSummaryCollapsed = false
    @State private var isPlanTabHovered = false
    @State private var planShortcutPrimedUntil: Date?
    @State private var lastPlanShortcutCycleAt: Date?
    @State private var inlinePlanSummaries: [UUID: InlinePlanSummary] = [:]
    @State private var hasJustCompletedTask = false
    @State private var showRateLimitAlert = false
    @State private var rateLimitAlertText = ""
    @State private var didCopyAllChat = false
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
    @State private var pendingTaskActivities: [TaskActivity] = []
    @State private var pendingInstantGreps: [InstantGrepResult] = []
    @State private var taskFlushTask: Task<Void, Never>?
    @State private var autoScrollWorkItem: DispatchWorkItem?
    @State private var lastAutoScrollTarget: AnyHashable?
    @State private var lastAutoScrollAt: Date = .distantPast
    @State private var fallbackTurnStartWorkItem: DispatchWorkItem?
    @State private var streamContentVersion: Int = 0
    @State private var streamingReasoningText: String?
    @State private var streamingReasoningConversationId: UUID?
    /// Pending streaming content waiting to be flushed to ChatStore.
    @State private var pendingStreamContent: String?
    @State private var pendingStreamConversationId: UUID?
    @State private var streamThrottleTask: Task<Void, Never>?
    @State private var activeToolTraceTurn: ToolTraceTurnContext?
    @State private var toolTraceNextSequenceByMessage: [UUID: Int] = [:]
    @State private var toolTraceOperationalSeenByMessage: [UUID: Bool] = [:]
    @State private var toolTraceOperationalCountByMessage: [UUID: Int] = [:]
    @State private var policyAckStateByMessage: [UUID: PolicyAckState] = [:]
    @State private var autoTodoIdByMessage: [UUID: UUID] = [:]
    @State private var didReceiveExplicitTodoByMessage: Set<UUID> = []
    /// Minimum interval between streaming content updates (≈30fps).
    private let streamThrottleInterval: TimeInterval = 0.033
    /// Coalescing flush interval for task activity feed.
    private let taskActivityFlushInterval: TimeInterval = 0.1
    /// Backlog threshold used only for lightweight stream diagnostics.
    private let taskBacklogDiagnosticThreshold = 40
    private let checkpointGitStore = ConversationCheckpointGitStore()
    private let cliAccountsStore = CLIAccountsStore.shared
    private let cliAccountRouter = CLIAccountRouter.shared

    private static let attachmentPastedNotification = Notification.Name("CoderIDE.AttachmentPasted")
    static let planBuildShortcutNotification = Notification.Name("CoderIDE.PlanBuildShortcutPressed")
    static let debugPanelToggleNotification = Notification.Name("CoderIDE.DebugPanelToggle")
    private static let threadSearchAskAINotification = Notification.Name(
        "CoderIDE.ThreadSearchAskAI")
    private static let markdownExportContentType = UTType(filenameExtension: "md") ?? .plainText
    private let topInteractiveInset: CGFloat = 22
    private let chatColumnMaxWidth: CGFloat = 960

    private var activeModeColor: Color { modeColor(for: coderMode) }
    private var activeModeGradient: LinearGradient { modeGradient(for: coderMode) }
    private var showPlanRequestIndicator: Bool {
        let trimmed = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        return planToggleEnabled || hasStrictPlanCommandPrefix(trimmed)
    }
    private var composerRuntimeStartDate: Date? {
        guard isLoadingForCurrentConversation else { return nil }
        return chatStore.taskStartDate(for: conversationId) ?? composerTaskStartDate
    }
    private var composerFrozenTimerText: String? { composerFrozenTimerState?.text }
    private var composerFrozenTimerDismissible: Bool { composerFrozenTimerState?.dismissible == true }
    private var shouldShowTaskPanelTodoSection: Bool {
        let planFlowActive =
            coderMode == .plan
            || planToggleEnabled
            || planFlowPhase == .analyzing
            || planFlowPhase == .questioning
            || planFlowPhase == .generating
            || planFlowPhase == .proposalReady
            || planFlowPhase == .readyToBuild
            || planFlowPhase == .building
        return !planFlowActive
    }
    private var showsSwarmViewOnly: Bool { shouldShowSwarmViewOnly(for: coderMode) }
    private var planPanelConversationId: UUID? { conversationId }
    private var shouldShowFinalChatActions: Bool {
        Self.shouldShowFinalChatActions(
            conversation: chatStore.conversation(for: conversationId),
            isLoadingForCurrentConversation: isLoadingForCurrentConversation
        ) && !showsSwarmViewOnly
    }

    var body: some View {
        applyNotificationAndImporterModifiers(
            to: applyRuntimeLifecycleModifiers(
                to: applyProviderSelectionModifiers(to: rootLayout)
            )
        )
    }

    @ViewBuilder
    private var rootLayout: some View {
        HStack(spacing: 6) {
            VStack(spacing: 0) {
                // Keep out of macOS titlebar hit-test zone while still using full-height content.
                Color.clear
                    .frame(height: topInteractiveInset)
                    .allowsHitTesting(false)
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

                if shouldShowFinalChatActions {
                    finalChatActionsBar
                }

                // Keep the legacy task bar only when the composer is not visible (e.g. Swarm).
                if !shouldShowComposer(for: coderMode) && (isLoadingForCurrentConversation || isSummarizing) {
                    TaskControlBar(
                        chatStore: chatStore,
                        taskActivityStore: taskActivityStore,
                        executionController: executionController,
                        conversationId: conversationId,
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
                PanelResizeHandle(
                    panelWidth: Binding(get: { CGFloat(planPanelWidthStorage) }, set: { planPanelWidthStorage = Double($0) }),
                    minWidth: 220, maxWidth: 500, leadingEdge: false
                )
                planPanelSidebar
            }
            if showDebugPanel {
                PanelResizeHandle(
                    panelWidth: Binding(get: { CGFloat(debugPanelWidthStorage) }, set: { debugPanelWidthStorage = Double($0) }),
                    minWidth: 240, maxWidth: 500, leadingEdge: false
                )
                debugPanelSidebar
            }
            if showSwarmPanel {
                PanelResizeHandle(
                    panelWidth: Binding(get: { CGFloat(swarmPanelWidthStorage) }, set: { swarmPanelWidthStorage = Double($0) }),
                    minWidth: 260, maxWidth: 540, leadingEdge: false
                )
                swarmPanelSidebar
            }
            if showCodeReviewPanel {
                PanelResizeHandle(
                    panelWidth: Binding(get: { CGFloat(codeReviewPanelWidthStorage) }, set: { codeReviewPanelWidthStorage = Double($0) }),
                    minWidth: 280, maxWidth: 560, leadingEdge: false
                )
                codeReviewPanelSidebar
            }
        }
    }

    private func applyProviderSelectionModifiers<Content: View>(to content: Content) -> some View {
        content
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
            // Allow the previous thread to keep running in the background —
            // no longer interrupt it when switching conversations.
            // Restore the plan state if the destination conversation already has a plan.
            activeBuildPlanConversationId = nil
            planHistoryStore.setSelectedEntry(id: nil)
            restorePlanStateIfNeeded(for: newId)
            syncProviderFromConversation()
        }
        .onAppear {
            migrateSwarmProviderDefaultsIfNeeded()
            syncProviderFromConversation()
            codexModels = CodexModelsCache.loadModels()
            geminiModels = GeminiModelsCache.loadModels()
            syncSwarmProvider()
            syncCodeReviewRuntimeConfig()
            syncPlanProvider()
            checkProviderAuth()
            gitPanelStore.refresh(workingDirectory: effectiveContext.primaryPath)
        }
    }

    private func applyRuntimeLifecycleModifiers<Content: View>(to content: Content) -> some View {
        let lifecycleTracked = content
            .onChange(of: showSwarmPanel) { wasOpen, isShowing in
                if isShowing && coderMode != .agentSwarm {
                    selectMode(.agentSwarm)
                }
                if !isShowing && coderMode == .agentSwarm {
                    selectMode(.agent)
                }
                let w = CGFloat(swarmPanelWidthStorage) + 12
                if isShowing && !wasOpen { WindowResizeHelper.adjustWidth(by: w) }
                else if !isShowing && wasOpen { WindowResizeHelper.adjustWidth(by: -w) }
            }
            .onChange(of: showDebugPanel) { wasOpen, isShowing in
                if debugToggleEnabled != isShowing {
                    debugToggleEnabled = isShowing
                }
                let w = CGFloat(debugPanelWidthStorage) + 12
                if isShowing && !wasOpen { WindowResizeHelper.adjustWidth(by: w) }
                else if !isShowing && wasOpen { WindowResizeHelper.adjustWidth(by: -w) }
            }
            .onChange(of: debugToggleEnabled) { _, isEnabled in
                guard showDebugPanel != isEnabled else { return }
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    showDebugPanel = isEnabled
                }
            }
            // Auto-expand/shrink window when side panels open/close
            .onChange(of: showPlanPanel) { wasOpen, isOpen in
                let w = CGFloat(planPanelWidthStorage) + 12
                if isOpen && !wasOpen { WindowResizeHelper.adjustWidth(by: w) }
                else if !isOpen && wasOpen { WindowResizeHelper.adjustWidth(by: -w) }
            }
            .onChange(of: showCodeReviewPanel) { wasOpen, isOpen in
                let w = CGFloat(codeReviewPanelWidthStorage) + 12
                if isOpen && !wasOpen { WindowResizeHelper.adjustWidth(by: w) }
                else if !isOpen && wasOpen { WindowResizeHelper.adjustWidth(by: -w) }
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
            .onChange(of: chatStore.activeTaskConversationIds) { oldSet, newSet in
                guard let cid = conversationId else { return }
                let wasActive = oldSet.contains(cid)
                let isActive = newSet.contains(cid)
                if !wasActive && isActive {
                    composerTaskStartDate = chatStore.taskStartDate(for: cid) ?? Date()
                    composerFrozenTimerState = nil
                    composerTimerAutoHideTask?.cancel()
                    composerTimerAutoHideTask = nil
                    lastTaskEndedByManualStop = false
                }
                if wasActive && !isActive {
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
                            if !self.isLoadingForCurrentConversation {
                                composerFrozenTimerState = nil
                            }
                        }
                    }
                    lastTaskEndedByManualStop = false
                }
            }

        let swarmTracked = lifecycleTracked
            .onChange(of: swarmOrchestrator) { _, _ in syncSwarmProvider() }
            .onChange(of: swarmWorkerBackend) { _, _ in syncSwarmProvider() }
            .onChange(of: swarmAutoPostCodePipeline) { _, _ in syncSwarmProvider() }
            .onChange(of: swarmMaxPostCodeRetries) { _, _ in syncSwarmProvider() }
            .onChange(of: claudeAllowedTools) { _, _ in
                syncClaudeProvider()
            }
            .onChange(of: unifiedToolRuntimeEnabled) { _, _ in
                syncClaudeProvider()
                syncGeminiProvider()
                syncToolRuntimePolicy()
            }
            .onChange(of: globalYolo) { _, _ in
                syncCodexProvider()
                syncCodeReviewRuntimeConfig()
                syncPlanProvider()
            }

        let workspaceTracked = swarmTracked
            .onChange(of: workspaceStore.activeWorkspaceId) { _, _ in
                syncToolRuntimePolicy()
                syncCodeReviewRuntimeConfig()
            }
            .onChange(of: workspaceStore.workspaces.map(\.id)) { _, _ in
                syncToolRuntimePolicy()
                syncCodeReviewRuntimeConfig()
            }

        return workspaceTracked
            .onChange(of: codeReviewPartitions) { _, _ in syncCodeReviewRuntimeConfig() }
            .onChange(of: codeReviewAnalysisOnly) { _, _ in syncCodeReviewRuntimeConfig() }
            .onChange(of: codeReviewAnalysisBackend) { _, _ in syncCodeReviewRuntimeConfig() }
            .onChange(of: codeReviewExecutionBackend) { _, _ in syncCodeReviewRuntimeConfig() }
    }

    private func applyNotificationAndImporterModifiers<Content: View>(to content: Content) -> some View {
        content
        .sheet(isPresented: $showSwarmHelp) { AgentSwarmHelpView() }
        .fileImporter(
            isPresented: $isSelectingImage,
            allowedContentTypes: [.item], allowsMultipleSelection: true
        ) { result in
            handleAttachmentSelection(result: result)
        }
        .onAppear {
            installPasteMonitor()
        }
        .onDisappear {
            taskFlushTask?.cancel()
            taskFlushTask = nil
            streamThrottleTask?.cancel()
            streamThrottleTask = nil
            autoScrollWorkItem?.cancel()
            composerTimerAutoHideTask?.cancel()
            composerTimerAutoHideTask = nil
            voiceInputController.cancel()
            flushPendingTaskActivities()
            removePasteMonitor()
        }
        .onReceive(NotificationCenter.default.publisher(for: Self.attachmentPastedNotification)) {
            notification in
            if let attachments = notification.userInfo?["attachments"] as? [ComposerAttachment] {
                appendComposerAttachments(attachments)
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
            planStreamingContent: planStreamingContent,
            showHistorySection: shouldShowPlanPanelHistory(source: planPanelPresentationSource),
            workspaceSource: planPanelPresentationSource,
            onClose: {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    showPlanPanel = false
                }
            },
            onSelectOption: { option, _ in
                selectPlanChoice(
                    option.fullText,
                    fromPlanConversationId: planPanelConversationId
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
            },
            onHistoryEntrySelectedForBuild: {
                if planFlowPhase == .idle, planningState == .idle {
                    planFlowPhase = .readyToBuild
                }
            }
        )
        .frame(width: CGFloat(planPanelWidthStorage))
        .transition(.move(edge: .trailing).combined(with: .opacity))
    }

    @ViewBuilder
    private var debugPanelSidebar: some View {
        DebugPanelView(
            debugStore: debugStore,
            taskActivityStore: taskActivityStore,
            todoStore: todoStore,
            onClose: {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    debugToggleEnabled = false
                    showDebugPanel = false
                }
            },
            onSubmitQuestion: { question in
                let debugPrompt = "[DEBUG] \(question)"
                inputText = debugPrompt
                sendMessage()
            },
            onStop: {
                debugStore.resetSession()
            },
            onProceed: {
                debugStore.confirmReproduced()
                // Tell the agent to proceed with investigation
                inputText = "[DEBUG] Bug reproduced. Proceed with investigation."
                sendMessage()
            },
            onFixed: {
                let result = debugStore.markFixed(summary: debugStore.resolutionSummary)
                // Tell agent to clean up debug artifacts from files
                let allFiles = Set(
                    result.markers.map(\.filePath)
                    + result.instrumentation.map(\.filePath)
                )
                if !allFiles.isEmpty {
                    let fileList = allFiles.sorted().joined(separator: ", ")
                    inputText = "[DEBUG] Marked as fixed. Clean all debug markers and instrumentation from: \(fileList)"
                    sendMessage()
                }
            }
        )
        .frame(width: CGFloat(debugPanelWidthStorage))
        .transition(.move(edge: .trailing).combined(with: .opacity))
    }

    @ViewBuilder
    private var swarmPanelSidebar: some View {
        SwarmPanelView(
            taskActivityStore: taskActivityStore,
            swarmProgressStore: swarmProgressStore,
            todoStore: todoStore,
            chatStore: chatStore,
            conversationId: conversationId,
            isTaskRunning: isLoadingForCurrentConversation,
            swarmOrchestrator: $swarmOrchestrator,
            swarmWorkerBackend: $swarmWorkerBackend,
            onClose: {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    showSwarmPanel = false
                }
            },
            onOpenFile: { openFilesStore.openFile($0) },
            onSyncSwarmProvider: syncSwarmProvider
        )
        .frame(width: CGFloat(swarmPanelWidthStorage))
        .transition(.move(edge: .trailing).combined(with: .opacity))
    }

    private var codeReviewPanelSidebar: some View {
        CodeReviewPanelView(
            chatStore: chatStore,
            taskActivityStore: taskActivityStore,
            swarmProgressStore: swarmProgressStore,
            todoStore: todoStore,
            conversationId: conversationId,
            isTaskRunning: isLoadingForCurrentConversation,
            coderMode: coderMode,
            codeReviewPartitions: $codeReviewPartitions,
            codeReviewAnalysisOnly: $codeReviewAnalysisOnly,
            codeReviewMaxRounds: $codeReviewMaxRounds,
            codeReviewAnalysisBackend: $codeReviewAnalysisBackend,
            codeReviewExecutionBackend: $codeReviewExecutionBackend,
            onClose: {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    showCodeReviewPanel = false
                }
            },
            onOpenFile: { openFilesStore.openFile($0) },
            onRunSlashCommand: { command in
                inputText = command
                isInputFocused = true
                sendMessage()
            },
            onSelectMode: { mode in
                withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
                    selectMode(mode)
                }
            }
        )
        .frame(width: CGFloat(codeReviewPanelWidthStorage))
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
                            conversationId: conversationId,
                            coderMode: coderMode,
                            onOpenFile: { openFilesStore.openFile($0) },
                            effectivePrimaryPath: effectiveContext.primaryPath,
                            showTodoSection: shouldShowTaskPanelTodoSection
                        )
                    } else {
                        Text("No swarm activity available.")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.secondary)
                            .padding(16)
                    }
                } else {
                    Text("Swarm activity panel hidden.")
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

    private func appendComposerAttachments(_ incoming: [ComposerAttachment]) {
        guard !incoming.isEmpty else { return }
        var current = attachedComposerAttachments
        var seenPaths = Set(current.map { $0.url.standardizedFileURL.path })

        for item in incoming {
            guard current.count < AttachmentIntakeService.maxAttachmentsPerMessage else { break }
            if let size = item.sizeBytes, size > AttachmentIntakeService.maxAttachmentSizeBytes {
                continue
            }
            let path = item.url.standardizedFileURL.path
            if seenPaths.insert(path).inserted {
                current.append(item)
            }
        }
        attachedComposerAttachments = current
    }

    private func handleAttachmentSelection(result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            let hasHeic = urls.contains { ImageAttachmentHelper.isHeic(url: $0) }
            if hasHeic { isConvertingHeic = true }
            let imported = AttachmentIntakeService.importURLs(
                urls,
                existingCount: attachedComposerAttachments.count
            )
            appendComposerAttachments(imported.accepted)
            if hasHeic { isConvertingHeic = false }
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
            if showPlanPanel && event.modifierFlags.contains(.command) && event.keyCode == 36 {
                NotificationCenter.default.post(name: Self.planBuildShortcutNotification, object: nil)
                return nil
            }
            // Cmd+Shift+D toggles debug panel
            if event.modifierFlags.contains([.command, .shift]),
               event.charactersIgnoringModifiers?.lowercased() == "d" {
                DispatchQueue.main.async {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        debugToggleEnabled.toggle()
                    }
                }
                return nil
            }
            guard event.modifierFlags.contains(.command), event.charactersIgnoringModifiers == "v"
            else {
                return event
            }
            let attachments = AttachmentIntakeService.attachmentsFromPasteboard()
            if !attachments.isEmpty {
                DispatchQueue.main.async {
                    NotificationCenter.default.post(
                        name: Self.attachmentPastedNotification,
                        object: nil,
                        userInfo: ["attachments": attachments]
                    )
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

    private func restorePlanStateIfNeeded(for conversationId: UUID?) {
        guard let conversationId else {
            planningState = .idle
            planFlowPhase = .idle
            return
        }
        guard let board = chatStore.planBoard(for: conversationId) else {
            planningState = .idle
            planFlowPhase = .idle
            return
        }
        let chosenPath = board.chosenPath?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !chosenPath.isEmpty,
           PlanOptionsParser.hasRequiredTodoHeader(chosenPath),
           !PlanOptionsParser.extractTodosFromOptionText(chosenPath).isEmpty {
            planFlowPhase = .readyToBuild
            planningState = .idle
            return
        }
        if !board.options.isEmpty {
            planFlowPhase = .proposalReady
            planningState = .awaitingChoice(planContent: board.goal, options: board.options)
            return
        }
        planningState = .idle
        planFlowPhase = .idle
    }

    private func openPlanPanelForCurrentContext(
        preserveHistorySelection: Bool = false,
        source: PlanPanelPresentationSource = .manualDeepLink
    ) {
        planPanelPresentationSource = source
        if source == .automaticFlow || !preserveHistorySelection {
            planHistoryStore.setSelectedEntry(id: nil)
        }
        planShortcutPrimedUntil = nil
        showPlanPanel = true
    }

    private func cyclePlanShortcutState() {
        // Debounce: skip if called again within 300ms
        let now = Date()
        if let last = lastPlanShortcutCycleAt, now.timeIntervalSince(last) < 0.3 { return }
        lastPlanShortcutCycleAt = now

        let transition = evaluateCmdShiftPPlanShortcut(
            currentPlanToggleEnabled: planToggleEnabled,
            currentShowPlanPanel: showPlanPanel
        )
        withAnimation(.easeInOut(duration: 0.2)) {
            planToggleEnabled = transition.nextPlanToggleEnabled
            if transition.nextShowPlanPanel {
                openPlanPanelForCurrentContext(source: .manualShortcut)
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
        // Shift+Tab toggles plan mode on/off directly
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            planToggleEnabled.toggle()
            if planToggleEnabled {
                // Plan mode activated — show visual feedback
                isPlanTabHovered = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    isPlanTabHovered = false
                }
            } else {
                // Plan mode deactivated — reset state
                isPlanTabHovered = false
                planningState = .idle
                planFlowPhase = .idle
            }
        }
        isInputFocused = true
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

    private func copyWholeChatToClipboard() {
        guard let markdown = chatStore.exportConversationMarkdown(conversationId: conversationId) else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(markdown, forType: .string)
        didCopyAllChat = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            didCopyAllChat = false
        }
    }

    private func downloadCurrentConversationMarkdown() {
        guard let markdown = chatStore.exportConversationMarkdown(conversationId: conversationId) else { return }
        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [Self.markdownExportContentType]
        savePanel.canCreateDirectories = true
        savePanel.nameFieldStringValue = chatStore.defaultMarkdownFilename(for: conversationId)
        savePanel.begin { response in
            guard response == .OK, let url = savePanel.url else { return }
            do {
                try markdown.write(to: url, atomically: true, encoding: .utf8)
            } catch {
            }
        }
    }

    private func forkCurrentConversation() {
        guard let newConversationId = chatStore.forkConversation(from: conversationId) else { return }
        selectedConversationId = newConversationId
    }

    private func shouldHideBuildKickoffMessage(_ message: ChatMessage) -> Bool {
        guard message.role == .assistant else { return false }
        guard suppressedEmptyBuildAssistantMessageIds.contains(message.id) else { return false }
        return message.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }


    private var chatHeader: some View {
        GeometryReader { geo in
            ZStack {
                // Center: Mode tabs — Agent / IDE
                modeTabBar

                // Leading: project + (optional) title, Trailing: rewind button
                HStack(spacing: 8) {
                    projectButton
                    if shouldShowConversationTitle(headerWidth: geo.size.width) {
                        conversationTitleLabel
                    }
                    Spacer(minLength: 0)
                    rewindButton
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .frame(height: 32)
    }

    @ViewBuilder
    private var projectButton: some View {
        if let path = effectiveContext.primaryPath {
            Button {
                NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: path)
            } label: {
                Text(effectiveContext.displayLabel)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .fixedSize()
            }
            .buttonStyle(.plain)
            .help("Open folder \(path)")
        }
    }

    private var conversationTitleLabel: some View {
        Text(chatStore.conversation(for: conversationId)?.title ?? "New conversation")
            .font(.system(size: 12.5, weight: .medium))
            .foregroundStyle(.primary.opacity(0.7))
            .lineLimit(1)
            .fixedSize()
    }

    private func shouldShowConversationTitle(headerWidth: CGFloat) -> Bool {
        // Hide thread title aggressively in narrow layouts to avoid overlap with centered mode tabs.
        headerWidth >= 720
    }

    private var rewindButton: some View {
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
        .help("Rewind to previous checkpoint (restore chat and files)")
        .accessibilityLabel("Rewind checkpoint chat")
    }

    // MARK: - Mode Tab Bar (Agent / IDE)

    private var modeTabBar: some View {
        HStack(spacing: 2) {
            modeTabButton("Agent", icon: "brain", mode: .agent, color: DesignSystem.Colors.agentColor)
            modeTabButton("IDE", icon: "sparkles", mode: .ide, color: DesignSystem.Colors.ideColor)
        }
    }

    private func modeTabButton(_ title: String, icon: String, mode: CoderMode, color: Color) -> some View {
        let isSelected = coderMode == mode || (mode == .agent && (coderMode == .agentSwarm || coderMode == .codeReviewMultiSwarm))
        return Button {
            withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
                selectMode(mode)
            }
        } label: {
            HStack(spacing: 3) {
                Image(systemName: icon)
                    .font(.caption2)
                Text(title)
                    .font(.system(size: 11, weight: .medium))
            }
            .foregroundStyle(isSelected ? color : .secondary.opacity(0.6))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(isSelected ? color.opacity(0.12) : Color.clear)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Messages Area
    private var messagesArea: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: 22) {
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
                            let canRewindFromMessage = message.role == .user && !isRewinding
                            let needsDivider = message.role == .user && index > 0

                            if shouldHideBuildKickoffMessage(message) {
                                EmptyView()
                                    .id(message.id)
                            } else {
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
                                                    preserveHistorySelection: true,
                                                    source: .manualDeepLink
                                                )
                                            },
                                            onRemove: { planHistoryStore.deleteEntry(id: entry.id) },
                                            onExpandPlan: {
                                                planHistoryStore.setSelectedEntry(id: entry.id)
                                                openPlanPanelForCurrentContext(
                                                    preserveHistorySelection: true,
                                                    source: .manualDeepLink
                                                )
                                            }
                                        )
                                    } else {
                                        let effectiveReasoning = (conv.id == streamingReasoningConversationId
                                            && isLastAssistant
                                            && message.isStreaming)
                                            ? streamingReasoningText
                                            : nil
                                        let shouldHideStreamingBarOnPreviousAssistant =
                                            message.role == .assistant
                                            && !isLastAssistant
                                            && lastMsg?.role == .assistant
                                            && (lastMsg?.isStreaming ?? false)
                                            && isLoadingForCurrentConversation
                                        VStack(alignment: .leading, spacing: 10) {
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
                                                hasCheckpointForRestore: hasCheckpointForMessage,
                                                showTopDivider: needsDivider
                                            )
                                            if message.role == .assistant {
                                                let traceEvents = toolTraceStore.events(
                                                    conversationId: conv.id,
                                                    assistantMessageId: message.id
                                                )
                                                if !traceEvents.isEmpty {
                                                    messageTraceView(
                                                        traceEvents: traceEvents,
                                                        effectiveContext: effectiveContext
                                                    )
                                                }
                                            }
                                        }
                                    }
                                    if message.role == .assistant { Spacer(minLength: 0) }
                                }
                                .id(message.id)
                            }
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
                                                openPlanPanelForCurrentContext(source: .manualDeepLink)
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
                                onSelectOption: { selectPlanChoice($0.fullText) }
                            )
                            .padding(.horizontal, 16)
                            .padding(.bottom, 8)
                            .id("plan-board")
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
                    VStack(spacing: 20) {
                        if let url = Bundle.module.url(forResource: "AppLogo", withExtension: "png"),
                           let icon = NSImage(contentsOf: url) {
                            Image(nsImage: icon)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 56, height: 56)
                                .cornerRadius(13)
                                .saturation(0)
                                .opacity(0.3)
                        }
                        VStack(spacing: 6) {
                            Text("codigo")
                                .font(.system(size: 20, weight: .semibold, design: .rounded))
                                .foregroundStyle(.secondary.opacity(0.45))
                            Text("Ask anything, build anything")
                                .font(.system(size: 13, weight: .regular))
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .offset(y: -40)
                    .allowsHitTesting(false)
                }
            }
            .onChange(of: streamContentVersion) { _, _ in
                if let last = chatStore.conversation(for: conversationId)?.messages.last,
                    isFollowingLive
                {
                    scheduleAutoScroll(proxy: proxy, target: last.id, delay: 0.03)
                }
            }
            .onChange(of: liveTraceEventCount) { _, _ in
                guard isLoadingForCurrentConversation, isFollowingLive else { return }
                if let target = liveScrollTarget() {
                    scheduleAutoScroll(proxy: proxy, target: target, delay: 0.02)
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
            .onChange(of: chatStore.activeTaskConversationIds) { oldSet, newSet in
                guard let cid = conversationId else { return }
                let isActive = newSet.contains(cid)
                let wasActive = oldSet.contains(cid)
                if !wasActive && isActive {
                    isFollowingLive = true
                    newEventsWhileDetached = 0
                    if let target = liveScrollTarget() {
                        scheduleAutoScroll(proxy: proxy, target: target, delay: 0)
                    }
                } else if wasActive && !isActive {
                    cancelFallbackTurnStartEvent()
                    isFollowingLive = true
                    newEventsWhileDetached = 0
                    if let target = latestMessageScrollTarget() {
                        scheduleAutoScroll(proxy: proxy, target: target, animated: true, delay: 0)
                        scheduleAutoScroll(proxy: proxy, target: target, animated: true, delay: 0.16)
                    }
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
                },
                including: isLoadingForCurrentConversation ? .gesture : .subviews
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
                            Text("Back to live")
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

    @ViewBuilder
    private var finalChatActionsBar: some View {
        HStack(spacing: 8) {
            finalChatActionButton(
                icon: didCopyAllChat ? "checkmark" : "doc.on.doc",
                title: didCopyAllChat ? "Copied" : "Copy all",
                help: didCopyAllChat ? "Copied" : "Copy entire chat as Markdown",
                foreground: didCopyAllChat ? DesignSystem.Colors.success : .secondary,
                action: copyWholeChatToClipboard
            )
            finalChatActionButton(
                icon: "arrow.down.to.line",
                title: "Download .md",
                help: "Download chat as Markdown",
                foreground: .secondary,
                action: downloadCurrentConversationMarkdown
            )
            finalChatActionButton(
                icon: "square.on.square",
                title: "Fork chat",
                help: "Fork this chat into a new thread",
                foreground: .secondary,
                action: forkCurrentConversation
            )
            Spacer(minLength: 0)
        }
        .frame(maxWidth: chatColumnMaxWidth)
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.horizontal, 20)
        .padding(.top, 4)
        .padding(.bottom, 8)
    }

    private func finalChatActionButton(
        icon: String,
        title: String,
        help: String,
        foreground: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 10.5, weight: .semibold))
                Text(title)
                    .font(.system(size: 10.5, weight: .semibold))
            }
            .foregroundStyle(foreground)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(Color(nsColor: .controlBackgroundColor).opacity(0.55))
            )
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(title)
    }

    private func enableTaskPanelIfNeeded() {
        guard shouldEnableTaskPanelForMode(coderMode) else { return }
        if !taskPanelEnabled {
            taskPanelEnabled = true
        }
    }

    private func scheduleFallbackTurnStartEvent(conversationId: UUID, providerId: String) {
        fallbackTurnStartWorkItem?.cancel()
        let work = DispatchWorkItem {
            Task { @MainActor in
                guard chatStore.isTaskActive(for: conversationId) else { return }
                guard taskActivityStore.activities.isEmpty else { return }
                recordTaskActivity(
                    type: "turn_started",
                    payload: [
                        "title": "Turn started",
                        "detail": "Request execution in progress",
                        "status": "started",
                        "group_id": "ui-fallback-\(conversationId.uuidString)",
                    ],
                    providerId: providerId,
                    conversationId: conversationId
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

    private var liveTraceEventCount: Int {
        guard let conv = chatStore.conversation(for: conversationId),
              let lastAssistant = conv.messages.last(where: { $0.role == .assistant }) else {
            return 0
        }
        return toolTraceStore.events(
            conversationId: conv.id,
            assistantMessageId: lastAssistant.id
        ).count
    }

    @ViewBuilder
    private func messageTraceView(
        traceEvents: [ToolTraceEvent],
        effectiveContext: EffectiveContext
    ) -> some View {
        MessageToolTraceView(
            events: traceEvents,
            workspaceHints: traceWorkspaceHints(for: effectiveContext),
            onOpenFile: { openFilesStore.openFile($0) }
        )
    }

    private func traceWorkspaceHints(for effectiveContext: EffectiveContext) -> [String] {
        let fromContext = effectiveContext.context?.folderPaths
            .filter { !$0.isEmpty } ?? []
        if !fromContext.isEmpty {
            return fromContext
        }
        if let primary = effectiveContext.primaryPath, !primary.isEmpty {
            return [primary]
        }
        return []
    }

    private func latestMessageScrollTarget() -> AnyHashable? {
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
        let now = Date()
        if lastAutoScrollTarget == target,
           now.timeIntervalSince(lastAutoScrollAt) < 0.06 {
            return
        }
        lastAutoScrollTarget = target
        lastAutoScrollAt = now
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
        taskFlushTask?.cancel()
        taskFlushTask = nil
        flushPendingTaskActivities()
        if let cid = targetConversationId {
            let cur =
                chatStore.conversation(for: cid)?.messages.last(where: {
                    $0.role == .assistant
                })?.content ?? ""
            chatStore.updateLastAssistantMessage(
                content: cur.isEmpty
                    ? "[Interrupted by user]"
                    : cur + "\n\n[Interrupted by user]", in: cid)
            chatStore.setLastAssistantStreaming(false, in: cid)
            clearStreamingReasoning(for: cid)
        }
        finalizeToolTraceTurn(conversationId: targetConversationId, outcome: .aborted)
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
                    title: "Process resumed",
                    detail: "Execution resumed by user",
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
                title: "Process paused",
                detail: "Execution paused by user",
                payload: [:],
                phase: .planning,
                isRunning: false
            )
        )
    }

    private func handleVoiceAction() {
        if isLoadingForCurrentConversation {
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

    private func currentInstructionPolicyBundle() -> InstructionPolicyBundle {
        let hints = traceWorkspaceHints(for: effectiveContext)
        return InstructionPolicyBundle.load(workspacePaths: hints)
    }

    private func expectedPolicyAckHash() -> String? {
        guard agentsHardBlockEnabled else { return nil }
        let bundle = currentInstructionPolicyBundle()
        let hash = bundle.policyHash.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !hash.isEmpty else { return nil }
        return hash
    }

    private func initializePolicyAckStateIfNeeded(for assistantMessageId: UUID) {
        guard let expectedHash = expectedPolicyAckHash() else {
            policyAckStateByMessage.removeValue(forKey: assistantMessageId)
            return
        }
        if policyAckStateByMessage[assistantMessageId] == nil {
            policyAckStateByMessage[assistantMessageId] = PolicyAckState(expectedHash: expectedHash)
        }
    }

    @MainActor
    private func startToolTraceTurn(conversationId: UUID, assistantMessageId: UUID, providerId: String) {
        if let previous = activeToolTraceTurn,
           previous.assistantMessageId != assistantMessageId {
            let previousEvents = toolTraceStore.events(
                conversationId: previous.conversationId,
                assistantMessageId: previous.assistantMessageId
            )
            let hasRunningOperations = previousEvents.contains(where: \.isRunning)
            let rolloverOutcome = rolloverAutoTodoOutcome(
                for: flowCoordinator.state,
                hasRunningOperations: hasRunningOperations
            )
            finalizeAutoTodoIfNeeded(messageId: previous.assistantMessageId, outcome: rolloverOutcome)
            toolTraceStore.finalizeTurn(
                conversationId: previous.conversationId,
                assistantMessageId: previous.assistantMessageId
            )
            toolTraceNextSequenceByMessage.removeValue(forKey: previous.assistantMessageId)
            toolTraceOperationalSeenByMessage.removeValue(forKey: previous.assistantMessageId)
            toolTraceOperationalCountByMessage.removeValue(forKey: previous.assistantMessageId)
            policyAckStateByMessage.removeValue(forKey: previous.assistantMessageId)
            autoTodoIdByMessage.removeValue(forKey: previous.assistantMessageId)
            didReceiveExplicitTodoByMessage.remove(previous.assistantMessageId)
        }
        let turn = ToolTraceTurnContext(
            conversationId: conversationId,
            assistantMessageId: assistantMessageId,
            providerId: providerId
        )
        activeToolTraceTurn = turn
        toolTraceNextSequenceByMessage[assistantMessageId] = 1
        toolTraceOperationalSeenByMessage[assistantMessageId] = false
        toolTraceOperationalCountByMessage[assistantMessageId] = 0
        autoTodoIdByMessage.removeValue(forKey: assistantMessageId)
        didReceiveExplicitTodoByMessage.remove(assistantMessageId)
        initializePolicyAckStateIfNeeded(for: assistantMessageId)
        toolTraceStore.startTurn(
            conversationId: conversationId,
            assistantMessageId: assistantMessageId,
            providerId: providerId
        )
    }

    @MainActor
    private func finalizeToolTraceTurn(conversationId: UUID?, outcome: ToolTraceTurnOutcome? = nil) {
        guard let active = activeToolTraceTurn else { return }
        guard conversationId == nil || active.conversationId == conversationId else { return }
        let finalOutcome = outcome ?? toolTraceTurnOutcome(for: flowCoordinator.state)
        finalizeAutoTodoIfNeeded(messageId: active.assistantMessageId, outcome: finalOutcome)
        toolTraceStore.finalizeTurn(
            conversationId: active.conversationId,
            assistantMessageId: active.assistantMessageId
        )
        toolTraceNextSequenceByMessage.removeValue(forKey: active.assistantMessageId)
        toolTraceOperationalSeenByMessage.removeValue(forKey: active.assistantMessageId)
        toolTraceOperationalCountByMessage.removeValue(forKey: active.assistantMessageId)
        policyAckStateByMessage.removeValue(forKey: active.assistantMessageId)
        autoTodoIdByMessage.removeValue(forKey: active.assistantMessageId)
        didReceiveExplicitTodoByMessage.remove(active.assistantMessageId)
        activeToolTraceTurn = nil
    }

    @MainActor
    private func finalizeAutoTodoIfNeeded(messageId: UUID, outcome: ToolTraceTurnOutcome) {
        if let autoTodoId = autoTodoIdByMessage[messageId],
           !didReceiveExplicitTodoByMessage.contains(messageId) {
            todoStore.setStatus(id: autoTodoId, status: autoTodoFinalStatus(for: outcome))
        }
    }

    @MainActor
    private func resolveToolTraceTurn(conversationId: UUID?, providerId: String) -> ToolTraceTurnContext? {
        let activeTarget = activeToolTraceTurn.map {
            ToolTraceBindingTarget(
                conversationId: $0.conversationId,
                assistantMessageId: $0.assistantMessageId
            )
        }
        let fallbackAssistantMessageId = conversationId.flatMap { id in
            chatStore.conversation(for: id)?
                .messages
                .last(where: { $0.role == .assistant })?
                .id
        }
        guard let target = ToolTraceBindingResolver.resolve(
            activeTurn: activeTarget,
            requestedConversationId: conversationId,
            fallbackAssistantMessageId: fallbackAssistantMessageId
        ) else {
            return nil
        }
        let fallbackTurn = ToolTraceTurnContext(
            conversationId: target.conversationId,
            assistantMessageId: target.assistantMessageId,
            providerId: providerId
        )
        if toolTraceNextSequenceByMessage[target.assistantMessageId] == nil {
            let existing = toolTraceStore.events(
                conversationId: target.conversationId,
                assistantMessageId: target.assistantMessageId
            )
            let next = (existing.last?.sequence ?? 0) + 1
            toolTraceNextSequenceByMessage[target.assistantMessageId] = max(1, next)
        }
        if toolTraceOperationalSeenByMessage[target.assistantMessageId] == nil {
            let existing = toolTraceStore.events(
                conversationId: target.conversationId,
                assistantMessageId: target.assistantMessageId
            )
            toolTraceOperationalSeenByMessage[target.assistantMessageId] = existing.contains {
                ToolTraceVisibility.shouldDisplay(event: $0)
            }
        }
        if toolTraceOperationalCountByMessage[target.assistantMessageId] == nil {
            let existing = toolTraceStore.events(
                conversationId: target.conversationId,
                assistantMessageId: target.assistantMessageId
            )
            toolTraceOperationalCountByMessage[target.assistantMessageId] = existing.reduce(into: 0) { partial, event in
                if ToolTraceVisibility.shouldDisplay(event: event) {
                    partial += 1
                }
            }
        }
        initializePolicyAckStateIfNeeded(for: target.assistantMessageId)
        toolTraceStore.startTurn(
            conversationId: target.conversationId,
            assistantMessageId: target.assistantMessageId,
            providerId: providerId
        )
        activeToolTraceTurn = fallbackTurn
        return fallbackTurn
    }

    @MainActor
    private func appendToolTraceEvent(
        activity: TaskActivity,
        rawKind: EventKind,
        providerId: String,
        conversationId: UUID?
    ) {
        guard ToolTraceVisibility.shouldInclude(activity: activity) else { return }
        guard let turn = resolveToolTraceTurn(conversationId: conversationId, providerId: providerId) else {
            return
        }
        let sequence = toolTraceNextSequenceByMessage[turn.assistantMessageId] ?? 1
        let event = ToolTraceEvent(
            sequence: sequence,
            timestamp: activity.timestamp,
            providerId: providerId,
            conversationId: turn.conversationId,
            assistantMessageId: turn.assistantMessageId,
            type: activity.type,
            title: activity.title,
            detail: activity.detail,
            payload: activity.payload,
            phase: activity.phase,
            isRunning: activity.isRunning,
            groupId: activity.groupId,
            rawKind: rawKind.rawValue
        )
        toolTraceStore.append(event: event)
        toolTraceNextSequenceByMessage[turn.assistantMessageId] = sequence + 1
        if ToolTraceVisibility.shouldDisplay(activity: activity) {
            toolTraceOperationalSeenByMessage[turn.assistantMessageId] = true
            let current = toolTraceOperationalCountByMessage[turn.assistantMessageId] ?? 0
            toolTraceOperationalCountByMessage[turn.assistantMessageId] = current + 1
        }
    }

    @MainActor
    private func recordTaskActivity(
        type: String,
        payload: [String: String],
        providerId: String,
        conversationId: UUID?
    ) {
        cancelFallbackTurnStartEvent()
        let envelope = flowCoordinator.normalizeRawEvent(
            providerId: providerId, type: type, payload: payload)
        taskActivityStore.addEnvelope(envelope)

        for event in envelope.events {
            switch event {
            case .taskActivity(let activity):
                enqueueTaskActivity(activity)
                appendToolTraceEvent(
                    activity: activity,
                    rawKind: envelope.kind,
                    providerId: providerId,
                    conversationId: conversationId
                )
                ensureTodoCoverageForMultiStep(
                    activity: activity,
                    providerId: providerId,
                    conversationId: conversationId
                )
            case .instantGrep(let grep):
                enableTaskPanelIfNeeded()
                pendingInstantGreps.append(grep)
                logTaskBacklogIfNeeded(context: "enqueue_grep")
                scheduleTaskActivityFlush()
            case .todoWrite(let todo):
                guard shouldAcceptTodoWrite(todo, conversationId: conversationId) else { break }
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
                recordExplicitTodoWrite(providerId: providerId, conversationId: conversationId)
            case .todoRead:
                guard shouldAcceptTodoRead(conversationId: conversationId) else { break }
                enableTaskPanelIfNeeded()
                break
            case .planStepUpdate(let stepId, let status, let stepTitle):
                let targetId = chatStore.activeTaskConversationId ?? conversationId
                chatStore.upsertPlanStep(stepId: stepId, status: status, title: stepTitle, in: targetId)
                if let sourcePlanId = activeBuildPlanConversationId, sourcePlanId != targetId {
                    chatStore.upsertPlanStep(stepId: stepId, status: status, title: stepTitle, in: sourcePlanId)
                }
            case .debugPanelUpdate(let action, let phase):
                handleDebugPanelUpdate(action: action, phase: phase)
            case .activatePlanMode(let reason):
                handleAutoActivatePlanMode(reason: reason)
            case .activateDebugMode(let reason):
                handleAutoActivateDebugMode(reason: reason)
            }
        }
    }

    private func recordExplicitTodoWrite(providerId: String, conversationId: UUID?) {
        guard let turn = resolveToolTraceTurn(conversationId: conversationId, providerId: providerId) else {
            return
        }
        let messageId = turn.assistantMessageId
        didReceiveExplicitTodoByMessage.insert(messageId)
        if let autoTodoId = autoTodoIdByMessage[messageId] {
            todoStore.remove(id: autoTodoId)
            autoTodoIdByMessage.removeValue(forKey: messageId)
        }
    }

    private func ensureTodoCoverageForMultiStep(
        activity: TaskActivity,
        providerId: String,
        conversationId: UUID?
    ) {
        guard planFlowPhase != .building else { return }
        guard ToolTraceVisibility.shouldDisplay(activity: activity) else { return }
        guard let turn = resolveToolTraceTurn(conversationId: conversationId, providerId: providerId) else {
            return
        }

        let messageId = turn.assistantMessageId
        guard !didReceiveExplicitTodoByMessage.contains(messageId) else { return }
        guard autoTodoIdByMessage[messageId] == nil else { return }

        let operationalCount = toolTraceOperationalCountByMessage[messageId] ?? 0
        guard operationalCount >= 2 else { return }

        let hasAgentTodo = todoStore.todos.contains { $0.source == .agent && !$0.isPlanCanonical }
        guard !hasAgentTodo else { return }

        let autoTodoId = UUID()
        todoStore.upsertFromAgent(
            id: autoTodoId,
            title: autoTodoTitle(for: activity),
            status: .inProgress,
            priority: .medium,
            notes: "Auto-generated: multi-step execution detected without explicit TODO markers.",
            linkedFiles: autoTodoLinkedFiles(from: activity.payload)
        )
        autoTodoIdByMessage[messageId] = autoTodoId
        enableTaskPanelIfNeeded()
    }

    private func autoTodoTitle(for activity: TaskActivity) -> String {
        let normalizedTitle = activity.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !normalizedTitle.isEmpty, !isPlaceholderTodoTitle(normalizedTitle) {
            return normalizedTitle
        }
        if let path = activity.payload["path"] ?? activity.payload["file"],
           !path.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let base = (path as NSString).lastPathComponent
            return "Completare modifiche su \(base)"
        }
        if let query = activity.payload["query"], !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "Completare analisi: \(String(query.prefix(80)))"
        }
        if let command = activity.payload["command"], !command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "Completare esecuzione: \(String(command.prefix(80)))"
        }
        return "Completare i passaggi operativi richiesti"
    }

    private func autoTodoLinkedFiles(from payload: [String: String]) -> [String] {
        var files = Set<String>()
        for candidate in [payload["path"], payload["file"], payload["files"]] {
            let raw = candidate?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !raw.isEmpty else { continue }
            let splitItems = raw
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            if splitItems.isEmpty {
                files.insert(raw)
            } else {
                splitItems.forEach { files.insert($0) }
            }
        }
        return files.sorted()
    }

    private func shouldAcceptTodoWrite(_ todo: TodoWritePayload, conversationId: UUID?) -> Bool {
        if planFlowPhase == .building {
            return true
        }
        if isPlaceholderTodoTitle(todo.title) {
            return false
        }
        let hasExistingAgentTodo = todoStore.todos.contains {
            $0.source == .agent && !$0.isPlanCanonical
        }
        if hasExistingAgentTodo {
            return true
        }
        if hasOperationalActivityInCurrentTurn(conversationId: conversationId) {
            return true
        }
        guard let conversationId,
              let assistantMessageId = currentAssistantMessageIdForTrace(conversationId: conversationId) else {
            return false
        }
        return !didReceiveExplicitTodoByMessage.contains(assistantMessageId)
    }

    private func shouldAcceptTodoRead(conversationId: UUID?) -> Bool {
        if planFlowPhase == .building {
            return true
        }
        guard todoStore.todos.contains(where: { $0.source == .agent || $0.isPlanCanonical }) else {
            return false
        }
        return hasOperationalActivityInCurrentTurn(conversationId: conversationId)
    }

    private func hasOperationalActivityInCurrentTurn(conversationId: UUID?) -> Bool {
        guard let conversationId,
              let assistantMessageId = currentAssistantMessageIdForTrace(conversationId: conversationId) else {
            return false
        }
        if let cached = toolTraceOperationalSeenByMessage[assistantMessageId] {
            return cached
        }
        let existing = toolTraceStore.events(
            conversationId: conversationId,
            assistantMessageId: assistantMessageId
        )
        let hasOperational = existing.contains { ToolTraceVisibility.shouldDisplay(event: $0) }
        toolTraceOperationalSeenByMessage[assistantMessageId] = hasOperational
        return hasOperational
    }

    private func currentAssistantMessageIdForTrace(conversationId: UUID) -> UUID? {
        if let active = activeToolTraceTurn, active.conversationId == conversationId {
            return active.assistantMessageId
        }
        return chatStore.conversation(for: conversationId)?
            .messages
            .last(where: { $0.role == .assistant })?
            .id
    }

    private func isPlaceholderTodoTitle(_ rawTitle: String) -> Bool {
        let normalized = rawTitle
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard !normalized.isEmpty else { return true }
        let genericTitles: Set<String> = [
            "task",
            "tasks",
            "todo",
            "todos",
            "step",
            "steps",
            "analysis",
            "workflow",
            "execution",
            "plan",
        ]
        if genericTitles.contains(normalized) {
            return true
        }
        if normalized.range(of: #"^(task|step)\s*\d*$"#, options: .regularExpression) != nil {
            return true
        }
        if normalized.contains("task panel")
            || normalized.contains("todo update")
            || normalized.contains("turn started")
        {
            return true
        }
        return false
    }

    @MainActor
    private func handleDebugPanelUpdate(action: String, phase: String?) {
        switch action.lowercased() {
        case "open":
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                debugToggleEnabled = true
                showDebugPanel = true
            }
            if let debugPhase = resolveDebugFlowPhaseAlias(phase) {
                debugStore.phase = debugPhase
            }
        case "close":
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                debugToggleEnabled = false
                showDebugPanel = false
            }
            debugStore.phase = .idle
        case "phase":
            if let debugPhase = resolveDebugFlowPhaseAlias(phase) {
                debugStore.setPhase(debugPhase)
            }
        case "stream":
            // Append streaming content from agent
            if let phaseStr = phase {
                debugStore.streamingContent += phaseStr
            }
        case "question":
            if let phaseStr = phase {
                debugStore.clarificationQuestions = phaseStr
                debugStore.phase = .describing
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    debugToggleEnabled = true
                    showDebugPanel = true
                }
            }
        case "reproduce":
            debugStore.setPhase(.reproducing)
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                debugToggleEnabled = true
                showDebugPanel = true
            }
        case "resolve":
            debugStore.phase = .resolved
            if let phaseStr = phase {
                debugStore.resolutionSummary = phaseStr
            }
        case "marker":
            // Agent inserted a debug marker — track it
            if let phaseStr = phase {
                // Format: "filePath|lineNumber|comment"
                let parts = phaseStr.split(separator: "|", maxSplits: 2).map(String.init)
                if parts.count >= 2, let line = Int(parts[1]) {
                    let comment = parts.count >= 3 ? parts[2] : "debug marker"
                    debugStore.addDebugMarker(DebugMarker(
                        filePath: parts[0],
                        lineNumber: line,
                        markerComment: comment
                    ))
                }
            }
        case "instrument":
            // Agent inserted instrumentation — track it
            // Format: "filePath|lineNumber|type|code|hypothesisId"
            if let phaseStr = phase {
                let parts = phaseStr.split(separator: "|", maxSplits: 4).map(String.init)
                if parts.count >= 4, let line = Int(parts[1]) {
                    let typeStr = parts[2].lowercased()
                    let instrumentType: InstrumentationPoint.InstrumentationType
                    switch typeStr {
                    case "assertion":  instrumentType = .assertion
                    case "timing":     instrumentType = .timing
                    case "variable":   instrumentType = .variable
                    default:           instrumentType = .logging
                    }
                    let code = parts[3]
                    let hypothesisId = parts.count >= 5 ? parts[4] : nil
                    debugStore.addInstrumentation(
                        filePath: parts[0],
                        lineNumber: line,
                        type: instrumentType,
                        code: code,
                        hypothesisId: hypothesisId
                    )
                    // Also transition to instrumenting sub-phase if in fixing
                    if debugStore.phase == .fixing {
                        debugStore.phase = .instrumenting
                    }
                }
            }
        case "runtime_log":
            // Agent reports a runtime log entry
            // Format: "location|message|key1=val1,key2=val2|hypothesisId"
            if let phaseStr = phase {
                let parts = phaseStr.split(separator: "|", maxSplits: 3).map(String.init)
                if parts.count >= 2 {
                    let location = parts[0]
                    let message = parts[1]
                    var data: [String: String] = [:]
                    if parts.count >= 3 {
                        for pair in parts[2].split(separator: ",") {
                            let kv = pair.split(separator: "=", maxSplits: 1).map(String.init)
                            if kv.count == 2 {
                                data[kv[0].trimmingCharacters(in: .whitespaces)] = kv[1].trimmingCharacters(in: .whitespaces)
                            }
                        }
                    }
                    let hypothesisId = parts.count >= 4 ? parts[3] : nil
                    debugStore.addRuntimeLog(
                        location: location,
                        message: message,
                        data: data,
                        hypothesisId: hypothesisId
                    )
                }
            }
        case "loop_back":
            // Verify failed → loop back to instrument phase
            let reason = phase ?? "Verification failed"
            debugStore.loopBackToInstrument(reason: reason)
        case "new_run":
            // Start a new reproduce run
            debugStore.startNewRun()
        case "hypothesize":
            // Agent proposes a hypothesis
            // Format: "title|description"
            if let phaseStr = phase {
                let parts = phaseStr.split(separator: "|", maxSplits: 1).map(String.init)
                if parts.count >= 2 {
                    _ = debugStore.addHypothesis(title: parts[0], description: parts[1])
                } else if !phaseStr.isEmpty {
                    _ = debugStore.addHypothesis(title: phaseStr, description: "")
                }
            }
        case "hypothesis_update":
            // Update hypothesis status
            // Format: "hypothesisId|status|evidence"
            if let phaseStr = phase {
                let parts = phaseStr.split(separator: "|", maxSplits: 2).map(String.init)
                if parts.count >= 2, let uuid = UUID(uuidString: parts[0]) {
                    let status: DebugHypothesis.HypothesisStatus
                    switch parts[1].lowercased() {
                    case "investigating": status = .investigating
                    case "confirmed":    status = .confirmed
                    case "rejected":     status = .rejected
                    default:             status = .proposed
                    }
                    let evidence = parts.count >= 3 ? parts[2] : nil
                    debugStore.updateHypothesis(id: uuid, status: status, evidence: evidence)
                }
            }
        case "diagram":
            // Agent sends a custom mermaid diagram for the debug flow
            if let phaseStr = phase, !phaseStr.isEmpty {
                debugStore.debugFlowDiagram = phaseStr
            }
        default:
            break
        }
    }

    // MARK: - LLM Auto-Activation Handlers

    @MainActor
    private func handleAutoActivatePlanMode(reason: String?) {
        guard !showPlanPanel else { return }
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            planToggleEnabled = true
        }
        openPlanPanelForCurrentContext(
            preserveHistorySelection: false,
            source: .automaticFlow
        )
    }

    @MainActor
    private func handleAutoActivateDebugMode(reason: String?) {
        guard !showDebugPanel else { return }
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            debugToggleEnabled = true
            showDebugPanel = true
        }
        if let reason = reason, !reason.isEmpty {
            debugStore.startDebugSession(errorContext: reason)
        } else {
            debugStore.startDebugSession()
        }
    }

    @MainActor
    private func enqueueTaskActivity(_ activity: TaskActivity) {
        pendingTaskActivities.append(activity)
        logTaskBacklogIfNeeded(context: "enqueue_activity")
        scheduleTaskActivityFlush()
    }

    @MainActor
    private func scheduleTaskActivityFlush() {
        if taskFlushTask != nil { return }
        taskFlushTask = Task {
            let delay = UInt64(taskActivityFlushInterval * 1_000_000_000)
            try? await Task.sleep(nanoseconds: delay)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                taskFlushTask = nil
                flushPendingTaskActivities()
            }
        }
    }

    @MainActor
    private func flushPendingTaskActivities() {
        let backlogBefore = pendingTaskActivities.count + pendingInstantGreps.count
        guard backlogBefore > 0 else { return }
        logTaskBacklogIfNeeded(context: "flush_start")

        let activities = pendingTaskActivities
        let greps = pendingInstantGreps
        pendingTaskActivities.removeAll(keepingCapacity: true)
        pendingInstantGreps.removeAll(keepingCapacity: true)

        for activity in activities {
            if activity.type == "read_batch_started" || activity.type == "read_batch_completed"
                || activity.type == "web_search_started"
                || activity.type == "web_search_completed"
                || activity.type == "web_search_failed"
                || activity.type == "web_fetch_started"
                || activity.type == "web_fetch_completed"
                || activity.type == "web_fetch_failed"
                || activity.type == "command_execution"
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

        let backlogAfter = pendingTaskActivities.count + pendingInstantGreps.count
        if backlogAfter > 0 {
            logTaskBacklogIfNeeded(context: "flush_reschedule")
            scheduleTaskActivityFlush()
        }
    }

    @MainActor
    private func logTaskBacklogIfNeeded(context: String) {
        let backlog = pendingTaskActivities.count + pendingInstantGreps.count
        guard backlog >= taskBacklogDiagnosticThreshold else { return }
        NSLog("[StreamDiag] task_backlog_high count=%d context=%@", backlog, context)
    }

    // MARK: - Composer
    @ViewBuilder
    private var composerArea: some View {
        VStack(spacing: 0) {
            ChatComposerView(
                inputText: $inputText,
                attachedAttachments: $attachedComposerAttachments,
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
                onInputTextChanged: { _ in },
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
        .alert("Rate Limit Reached", isPresented: $showRateLimitAlert) {
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
            onSyncCodexProvider: syncCodexProvider,
            onSyncClaudeProvider: syncClaudeProvider,
            onSyncGeminiProvider: syncGeminiProvider,
            onSyncSwarmProvider: syncSwarmProvider,
            onSyncPlanProvider: syncPlanProvider,
            onSyncOpenRouterProvider: syncOpenRouterProvider,
            onSyncToolRuntimePolicy: syncToolRuntimePolicy,
            onUserSelectedProvider: { suppressModeSyncForNextProviderChange = true },
            onDelegateToAgent: delegateToAgent,
            attachedImageURLs: attachedComposerAttachments
                .filter { $0.kind == .image }
                .map(\.url),
            planToggleEnabled: $planToggleEnabled,
            debugToggleEnabled: $debugToggleEnabled,
            swarmToggleEnabled: Binding(
                get: { showSwarmPanel },
                set: { newValue in
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        showSwarmPanel = newValue
                    }
                }
            ),
            codeReviewToggleEnabled: Binding(
                get: { showCodeReviewPanel },
                set: { newValue in
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        showCodeReviewPanel = newValue
                    }
                }
            ),
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
            claudeModel: claudeModel,
            contextRefreshTick: streamContentVersion
        )
        .frame(maxWidth: chatColumnMaxWidth)
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.horizontal, 20)
    }

    private var providerNotReadyMessage: String {
        guard let id = providerRegistry.selectedProviderId else {
            return "No provider selected. Go to Settings to configure."
        }
        switch id {
        case "openai-api": return "OpenAI API Key missing. Configure it in Settings."
        case "anthropic-api": return "Anthropic API Key missing. Configure it in Settings."
        case "google-api": return "Google Gemini API Key missing. Configure it in Settings."
        case "codex-cli":
            return "Codex CLI not connected. Configure it in Settings → Codex CLI."
        case "claude-cli":
            return "Claude Code not found. Configure it in Settings → Claude Code."
        case "gemini-cli":
            return "Gemini CLI not found/not authenticated. Configure it in Settings."
        case "openrouter-api": return "OpenRouter API Key missing. Configure it in Settings."
        case "minimax-api": return "MiniMax API Key missing. Configure it in Settings."
        default:
            return "Provider \"\(id)\" not authenticated. Go to Settings to configure."
        }
    }


    private var inputHint: String {
        switch coderMode {
        case .agent: return "Agent can modify files and run commands"
        case .agentSwarm: return "Swarm of specialized agents"
        case .codeReviewMultiSwarm:
            return
                "Using Code Review Multi-Swarm: the request will be split into partitions."
        case .plan: return "Plan with options + custom response"
        case .ide: return "IDE mode: API chat + manual editing in the editor"
        case .mcpServer: return "Send to configured MCP server"
        }
    }

    private var composerQuickCommandPresets: [ChatComposerView.QuickCommandPreset] {
        guard coderMode == .codeReviewMultiSwarm else { return [] }
        let defaults: [ChatComposerView.QuickCommandPreset] = [
            .init(
                id: "review-uncommitted",
                slash: "/review-uncommitted",
                label: "Full uncommitted audit",
                prompt:
                    """
                    Run ultra-deep code review on all uncommitted changes (staged, unstaged, untracked).
                    Required output:
                    1) prioritized findings (P0-P3),
                    2) impacted areas file-by-file,
                    3) regression risks,
                    4) final verdict on patch correctness.
                    """
            ),
            .init(
                id: "review-staged-only",
                slash: "/review-staged-only",
                label: "Staged diff only",
                prompt:
                    """
                    Review ONLY staged changes.
                    Ignore unstaged and untracked.
                    Return severe and actionable findings with priority/confidence.
                    """
            ),
            .init(
                id: "review-autofix",
                slash: "/review-autofix",
                label: "Review + auto fix",
                prompt:
                    """
                    Deep review uncommitted changes and directly fix all confirmed bugs.
                    After fixes, run relevant build/tests and report the technical changelog.
                    """
            ),
            .init(
                id: "review-autofix-commit",
                slash: "/review-autofix-commit",
                label: "Review + fix + commit",
                prompt:
                    """
                    Run full review on staged/unstaged/untracked, apply necessary fixes and create final atomic commit.
                    Requirements: no superfluous changes, green build/tests, specific commit message.
                    """
            ),
            .init(
                id: "review-ui-realtime",
                slash: "/review-ui-realtime",
                label: "Focus UI realtime",
                prompt:
                    """
                    Focus on review realtime flows:
                    - visible step-by-step stream,
                    - live updated read/tool/terminal cards,
                    - consistent todos without layout glitches.
                    Fix any issues found and validate with tests/build.
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
        // One thread per context: conversation does not change on tab switch.
        // selectedConversationId stays, only coderMode and provider are updated.
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
                // Keep current provider if already valid for Agent
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
        case .agent: return "brain"
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
                    // Avoid re-entrant mutations during SwiftUI/AppKit transactions (Picker/Menu).
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
            config: providerFactoryConfig(),
            executionController: executionController,
            codebaseIndex: workspaceStore.codebaseIndex,
            workspacePaths: workspaceStore.activeWorkspacePaths
        )
        reregisterProviderPreservingSelection(id: "codex-cli", provider: p)
        syncSwarmProvider()
        syncPlanProvider()
        checkProviderAuth()
        persistCodexConfigToToml()
    }

    private func syncClaudeProvider() {
        let p = ProviderFactory.claudeProvider(
            config: providerFactoryConfig(),
            executionController: executionController,
            codebaseIndex: workspaceStore.codebaseIndex,
            workspacePaths: workspaceStore.activeWorkspacePaths
        )
        reregisterProviderPreservingSelection(id: "claude-cli", provider: p)
        syncSwarmProvider()
        syncPlanProvider()
        checkProviderAuth()
    }

    private func syncGeminiProvider() {
        let p = ProviderFactory.geminiProvider(
            config: providerFactoryConfig(),
            executionController: executionController,
            codebaseIndex: workspaceStore.codebaseIndex,
            workspacePaths: workspaceStore.activeWorkspacePaths
        )
        reregisterProviderPreservingSelection(id: "gemini-cli", provider: p)
        checkProviderAuth()
    }

    private func syncOpenRouterProvider() {
        let p = ProviderFactory.openRouterAPIProvider(
            config: providerFactoryConfig(),
            executionController: executionController,
            codebaseIndex: workspaceStore.codebaseIndex,
            workspacePaths: workspaceStore.activeWorkspacePaths
        )
        reregisterProviderPreservingSelection(id: "openrouter-api", provider: p)
        checkProviderAuth()
    }

    private func syncToolRuntimePolicy() {
        let cfg = providerFactoryConfig()
        let codex = ProviderFactory.codexProvider(
            config: cfg,
            executionController: executionController,
            codebaseIndex: workspaceStore.codebaseIndex,
            workspacePaths: workspaceStore.activeWorkspacePaths
        )
        reregisterProviderPreservingSelection(id: "codex-cli", provider: codex)
        let claude = ProviderFactory.claudeProvider(
            config: cfg,
            executionController: executionController,
            codebaseIndex: workspaceStore.codebaseIndex,
            workspacePaths: workspaceStore.activeWorkspacePaths
        )
        reregisterProviderPreservingSelection(id: "claude-cli", provider: claude)
        let gemini = ProviderFactory.geminiProvider(
            config: cfg,
            executionController: executionController,
            codebaseIndex: workspaceStore.codebaseIndex,
            workspacePaths: workspaceStore.activeWorkspacePaths
        )
        reregisterProviderPreservingSelection(id: "gemini-cli", provider: gemini)

        if !cfg.openrouterApiKey.isEmpty {
            let p = ProviderFactory.openRouterAPIProvider(
                config: cfg,
                executionController: executionController,
                codebaseIndex: workspaceStore.codebaseIndex,
                workspacePaths: workspaceStore.activeWorkspacePaths
            )
            reregisterProviderPreservingSelection(id: "openrouter-api", provider: p)
        }
        if !cfg.openaiApiKey.isEmpty {
            let p = ProviderFactory.openAIAPIProvider(
                config: cfg,
                executionController: executionController,
                codebaseIndex: workspaceStore.codebaseIndex,
                workspacePaths: workspaceStore.activeWorkspacePaths
            )
            reregisterProviderPreservingSelection(id: "openai-api", provider: p)
        }
        if !cfg.anthropicApiKey.isEmpty {
            let p = ProviderFactory.anthropicAPIProvider(
                config: cfg,
                executionController: executionController,
                codebaseIndex: workspaceStore.codebaseIndex,
                workspacePaths: workspaceStore.activeWorkspacePaths
            )
            reregisterProviderPreservingSelection(id: "anthropic-api", provider: p)
        }
        if !cfg.googleApiKey.isEmpty {
            let p = ProviderFactory.googleAPIProvider(
                config: cfg,
                executionController: executionController,
                codebaseIndex: workspaceStore.codebaseIndex,
                workspacePaths: workspaceStore.activeWorkspacePaths
            )
            reregisterProviderPreservingSelection(id: "google-api", provider: p)
        }
        if !cfg.minimaxApiKey.isEmpty {
            let p = ProviderFactory.miniMaxAPIProvider(
                config: cfg,
                executionController: executionController,
                codebaseIndex: workspaceStore.codebaseIndex,
                workspacePaths: workspaceStore.activeWorkspacePaths
            )
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

    private func migrateSwarmProviderDefaultsIfNeeded() {
        guard !swarmProviderAutoMigrated else { return }
        if swarmOrchestrator == "openai" && swarmWorkerBackend == "codex" {
            swarmOrchestrator = "auto"
            swarmWorkerBackend = "auto"
        }
        swarmProviderAutoMigrated = true
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
                // Keep current provider if already valid for Agent
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
        let parsedClaudeTools = ProviderFactory.normalizedToolList(from: claudeAllowedTools)
        return ProviderFactoryConfig(
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
            grokApiKey: "",
            grokModel: "",
            codexPath: codexPath,
            codexSandbox: effectiveSandbox,
            codexSessionFullAccess: false,
            codexAskForApproval: codexAskForApproval,
            codexModelOverride: codexModelOverride,
            codexReasoningEffort: codexReasoningEffort,
            codexModelProvider: codexModelProvider,
            codexPreferResponsesWireAPI: codexPreferResponsesWireAPI,
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
            claudeAllowedTools: parsedClaudeTools,
            geminiCliPath: geminiCliPath,
            geminiModelOverride: geminiModelOverride,
            unifiedToolRuntimeEnabled: unifiedToolRuntimeEnabled,
            agentsHardBlockEnabled: agentsHardBlockEnabled,
            webSearchProvider: webSearchProvider,
            braveSearchApiKey: braveSearchApiKey,
            tavilyApiKey: tavilyApiKey,
            serperApiKey: serperApiKey
        )
    }

    private func trySummarizeIfNeeded(ctx: WorkspaceContext) async {
        // With Codex CLI we prefer the native compact from the provider over the custom summary.
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
            // Do not block on error
        }
    }

    // MARK: - Delegate to Agent (from IDE)
    private func delegateToAgent() {
        var msg = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        if msg.isEmpty {
            msg =
                chatStore.conversation(for: conversationId)?.messages.last(where: {
                    $0.role == .user
                })?.content ?? ""
        }
        guard !msg.isEmpty || !attachedComposerAttachments.isEmpty else { return }
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
            "[Provider] No authenticated execution-capable provider available.",
            in: conversationId
        )
        return nil
    }

    @MainActor
    private func submitPlanClarificationAnswers(_ submission: PlanClarificationSubmission) {
        let orderedAnswers = submission.answers.sorted(by: { $0.questionId < $1.questionId })
        guard !orderedAnswers.isEmpty else { return }
        let finalNote = submission.finalNote.trimmingCharacters(in: .whitespacesAndNewlines)
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
                finalNote: finalNote
            )
        )

        // Store answers and continue to Phase 3 (don't restart full flow via sendMessage)
        planClarificationAnswers = prompt
        planningState = .idle

        if coderMode == .agent {
            planToggleEnabled = true
        }
        recordTaskActivity(
            type: "plan_answers_submitted",
            payload: [
                "title": "Plan answers submitted",
                "detail": "Clarification answers were confirmed in the Plan Panel.",
                "status": "completed",
            ],
            providerId: providerRegistry.selectedProviderId ?? "plan-ui",
            conversationId: conversationId
        )

        continuePlanFlowPhase3()
    }

    @MainActor
    private func selectPlanChoice(
        _ choice: String,
        fromPlanConversationId explicitPlanConversationId: UUID? = nil
    ) {
        let normalized = choice.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return }
        let planConversationId = explicitPlanConversationId ?? conversationId
        chatStore.choosePlanPath(normalized, for: planConversationId)
        if let selected = planHistoryStore.selectedEntryId {
            planHistoryStore.updateChosenPath(id: selected, chosenPath: normalized)
        }
        if planFlowPhase == .proposalReady || planFlowPhase == .idle {
            planFlowPhase = .readyToBuild
        }
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
                "[Plan] Build not available: complete discovery/clarifications and generate a valid plan before executing.",
                in: conversationId
            )
            return
        }
        let hasRequiredTodoHeader = PlanOptionsParser.hasRequiredTodoHeader(choice)
        let planTodos = PlanOptionsParser.extractTodosFromOptionText(choice)
        guard hasRequiredTodoHeader, !planTodos.isEmpty else {
            appendTechnicalErrorMessage(
                "[Plan] Build blocked: the selected option must include an explicit `## Todo` section with checklist items.",
                in: conversationId
            )
            if !showPlanPanel {
                openPlanPanelForCurrentContext(
                    preserveHistorySelection: true,
                    source: .manualDeepLink
                )
            }
            return
        }
        let planConversationId = explicitPlanConversationId ?? conversationId
        let provider: any LLMProvider
        let normalizedOverride = providerOverrideId?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let overrideId = normalizedOverride, !overrideId.isEmpty {
            guard isPlanExecutionProviderIdAllowed(overrideId) else {
                appendTechnicalErrorMessage(
                    "[Plan] Invalid provider for build (\(overrideId)).",
                    in: conversationId
                )
                return
            }
            guard isPlanBuildExecutionCapableProvider(overrideId, registry: providerRegistry) else {
                appendTechnicalErrorMessage(
                    "[Plan] Provider not suitable for operational build (\(overrideId)). Select an execution-capable provider.",
                    in: conversationId
                )
                return
            }
            if let overrideProvider = providerRegistry.provider(for: overrideId) {
                if overrideProvider.isAuthenticated() {
                    provider = overrideProvider
                } else {
                    appendTechnicalErrorMessage(
                        "[Plan] Selected panel provider not authenticated (\(overrideProvider.displayName)). Using fallback real provider.",
                        in: conversationId
                    )
                    guard let backendProvider = resolvePreferredRealProvider() else {
                        return
                    }
                    provider = backendProvider
                }
            } else {
                appendTechnicalErrorMessage(
                    "[Plan] Selected panel provider not available (\(overrideId)). Using fallback real provider.",
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
                "[Checkpoint error: \(error.localizedDescription)]", in: conversationId)
            return
        }

        planningState = .idle
        planFlowPhase = .readyToBuild
        chatStore.choosePlanPath(choice, for: planConversationId)

        todoStore.upsertCanonicalPlanTodos(planTodos)
        let canonicalTodos = todoStore.todos.filter { $0.isPlanCanonical }

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

        let planBuildAssistantMessageId = UUID()
        chatStore.addMessage(
            ChatMessage(
                id: planBuildAssistantMessageId,
                role: .assistant,
                content: "",
                isStreaming: true
            ),
            to: agentConvId
        )
        suppressedEmptyBuildAssistantMessageIds.insert(planBuildAssistantMessageId)
        startToolTraceTurn(
            conversationId: agentConvId,
            assistantMessageId: planBuildAssistantMessageId,
            providerId: provider.id
        )
        chatStore.beginTask(conversationId: agentConvId)
        taskActivityStore.clear()
        scheduleFallbackTurnStartEvent(conversationId: agentConvId, providerId: provider.id)

        let planExecutionWorkflow = """
            **FUNDAMENTAL RULE: The plan TODOs are your BIBLE. Follow them EXACTLY in the order listed.**

            **Todo Workflow (strict, no noise):**
            1. The canonical plan TODOs are IMMUTABLE: do NOT create new TODOs, do NOT modify titles, do NOT reorder. Execute EXACTLY those present in the given order.
            2. For each TODO: set status=in_progress BEFORE starting, then status=done AFTER completion. Use \(CoderIDEMarkers.todoWritePrefix) to update the status.
            3. Emit \(CoderIDEMarkers.showTaskPanel) only if useful to visualize a real multi-step execution. Never emit it as a placeholder.
            4. Do NOT skip any TODO. Do NOT proceed to the next TODO until the current one is done.
            5. If a TODO is blocked, explain why and try to resolve it before moving on.
            6. Before finishing: ALL canonical TODOs MUST be done. If any is not done, do NOT terminate.
            7. Do not repeat the plan in chat: execute, update status, provide minimal operational feedback.
            8. Do NOT post kickoff fillers like "starting build/execution": begin directly from concrete execution updates.
            """

        let executionPlanBase: String
        if let board = chatStore.planBoard(for: planConversationId), !board.goal.isEmpty {
            executionPlanBase = """
            **Objective:** \(board.goal)

            **Plan (selected option):**
            \(choice)
            """
        } else {
            executionPlanBase = "**Plan to implement:**\n\(choice)"
        }

        let prompt = buildPlanExecutionPrompt(
            workflowInstructions: planExecutionWorkflow,
            executionPlanBase: executionPlanBase,
            planTodos: planTodos,
            canonicalTodos: canonicalTodos
        ).prompt

        Task {
            var traceOutcome: ToolTraceTurnOutcome = .success
            do {
                _ = try await flowCoordinator.runStream(
                    provider: provider,
                    prompt: prompt,
                    context: ctx,
                    attachments: nil,
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
                    onSignal: nil
                )
                chatStore.setLastAssistantStreaming(false, in: agentConvId)
                clearStreamingReasoning(for: agentConvId)
                chatStore.updatePlanStepStatus(stepId: "1", status: .done, in: planConversationId)
                await MainActor.run { planFlowPhase = .readyToBuild }
            } catch {
                chatStore.setLastAssistantStreaming(false, in: agentConvId)
                clearStreamingReasoning(for: agentConvId)
                if isInterruptedStreamError(error) {
                    traceOutcome = .aborted
                    chatStore.updatePlanStepStatus(stepId: "1", status: .failed, in: planConversationId)
                    await MainActor.run {
                        flowCoordinator.interrupt()
                        planFlowPhase = .proposalReady
                    }
                } else {
                    traceOutcome = .failed
                    chatStore.updatePlanStepStatus(stepId: "1", status: .failed, in: planConversationId)
                    chatStore.updateLastAssistantMessage(
                        content: userFacingStreamError(error), in: agentConvId)
                    await MainActor.run {
                        flowCoordinator.fail()
                        planFlowPhase = .proposalReady
                    }
                }
            }
            finalizeToolTraceTurn(conversationId: agentConvId, outcome: traceOutcome)
            chatStore.endTask(conversationId: agentConvId)
            await MainActor.run {
                chatStore.removeAssistantMessageIfEmpty(
                    messageId: planBuildAssistantMessageId,
                    in: agentConvId
                )
                suppressedEmptyBuildAssistantMessageIds.remove(planBuildAssistantMessageId)
                activeBuildPlanConversationId = nil
            }
        }
    }

    // MARK: - Send Message
    // MARK: - Send Message (orchestrator)

    private func mapAttachmentKindToLLM(_ kind: ChatAttachmentKind) -> LLMAttachmentKind {
        switch kind {
        case .image: return .image
        case .document: return .document
        case .file: return .file
        }
    }

    private func prepareRuntimeAttachmentURL(
        sourceURL: URL,
        workspaceURL: URL,
        turnId: UUID
    ) -> URL {
        let standardizedSource = sourceURL.standardizedFileURL
        let standardizedWorkspace = workspaceURL.standardizedFileURL
        if standardizedSource.path.hasPrefix(standardizedWorkspace.path) {
            return standardizedSource
        }

        let runtimeDir = standardizedWorkspace
            .appendingPathComponent(".codigo_attachments", isDirectory: true)
            .appendingPathComponent(turnId.uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: runtimeDir, withIntermediateDirectories: true)

        let ext = standardizedSource.pathExtension
        let baseName = standardizedSource.deletingPathExtension().lastPathComponent
            .replacingOccurrences(of: " ", with: "_")
            .prefix(40)
        let runtimeFileName = ext.isEmpty
            ? "\(UUID().uuidString)_\(baseName)"
            : "\(UUID().uuidString)_\(baseName).\(ext)"
        let runtimeURL = runtimeDir.appendingPathComponent(String(runtimeFileName))
        if !FileManager.default.fileExists(atPath: runtimeURL.path) {
            try? FileManager.default.copyItem(at: standardizedSource, to: runtimeURL)
        }
        return runtimeURL
    }

    private func buildAttachmentBundle(
        attachments: [ComposerAttachment],
        workspaceURL: URL,
        turnId: UUID,
        capabilities: ProviderAttachmentCapabilities
    ) -> (chat: [ChatAttachment], llm: [LLMAttachment], fallbackPreamble: String) {
        guard !attachments.isEmpty else { return ([], [], "") }

        var chatAttachments: [ChatAttachment] = []
        var llmAttachments: [LLMAttachment] = []
        var fallbackLines: [String] = []

        for item in attachments {
            let runtimeURL = prepareRuntimeAttachmentURL(
                sourceURL: item.url,
                workspaceURL: workspaceURL,
                turnId: turnId
            )
            let chatAttachment = ChatAttachment(
                kind: item.kind,
                originalName: item.originalName,
                mimeType: item.mimeType,
                localPath: item.url.path,
                sizeBytes: item.sizeBytes
            )
            chatAttachments.append(chatAttachment)
            llmAttachments.append(
                LLMAttachment(
                    kind: mapAttachmentKindToLLM(item.kind),
                    url: runtimeURL,
                    mimeType: item.mimeType,
                    filename: item.originalName,
                    sizeBytes: item.sizeBytes
                )
            )

            let isNativeSupported: Bool
            switch item.kind {
            case .image:
                isNativeSupported = capabilities.nativeImage
            case .document:
                isNativeSupported = capabilities.nativeDocument
            case .file:
                isNativeSupported = capabilities.nativeFile
            }
            if !isNativeSupported {
                let sizeText = item.sizeBytes.map { ByteCountFormatter.string(fromByteCount: $0, countStyle: .file) } ?? "n/a"
                fallbackLines.append("- \(item.originalName) [\(item.kind.rawValue)] path=\(runtimeURL.path) size=\(sizeText)")
            }
        }

        let preamble: String
        if fallbackLines.isEmpty {
            preamble = ""
        } else {
            preamble = """
            ## Allegati disponibili per questa richiesta
            I seguenti file NON sono supportati nativamente dal provider e sono disponibili via path locale:
            \(fallbackLines.joined(separator: "\n"))

            Se necessario, usa i tool di lettura file per analizzarli.
            """
        }

        return (chatAttachments, llmAttachments, preamble)
    }

    private func sendMessage() {
        let parsedInput = parsePlanCommandInput(inputText)
        let text = parsedInput.llmPromptInput
        let displayedInput = parsedInput.displayedInput
        let forcePlanInline = parsedInput.forcePlanInline
        if forcePlanInline {
            // /plan should only guide the LLM prompt, without opening the panel.
            showPlanPanel = false
        }
        guard !text.isEmpty || !attachedComposerAttachments.isEmpty else { return }
        guard let targetConversationId = conversationId else {
            appendTechnicalErrorMessage(
                "[Error] No conversation selected. Create or select a thread and try again.",
                in: nil
            )
            return
        }
        guard let selectedProvider = providerRegistry.selectedProvider else {
            appendTechnicalErrorMessage(
                "[Error] No provider selected. Configure a provider in Settings.",
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

        // Opening the plan panel should not automatically activate planning.
        let shouldRunPlanInline = resolveShouldRunPlanInline(
            forcePlanInline: forcePlanInline,
            coderMode: coderMode,
            planToggleEnabled: planToggleEnabled
        )
        if coderMode == .plan || shouldRunPlanInline {
            planFlowPhase = .analyzing
            planAnalysisContext = ""
            planUserRequest = text
            planClarificationAnswers = ""
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
                "[Error] Unable to resolve runtime provider for this mode.",
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
                "[Provider] \(runtimeProvider.displayName) not authenticated. Using fallback: \(fallbackProvider.displayName).",
                in: targetConversationId
            )
        } else if !selectedProviderAuthenticated {
            let providerName = runtimeProvider.displayName
            appendTechnicalErrorMessage(
                "[Error] Provider \(providerName) not authenticated and no fallback available. Open Settings and authenticate an execution-capable provider.",
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
                "[Checkpoint error: \(error.localizedDescription)]", in: targetConversationId)
            return
        }

        // 3. Prepare messages in chat store
        let turnId = UUID()
        let attachmentBundle = buildAttachmentBundle(
            attachments: attachedComposerAttachments,
            workspaceURL: ctx.workspacePath,
            turnId: turnId,
            capabilities: effectiveRuntimeProvider.attachmentCapabilities
        )
        let imagePathsToStore = attachmentBundle.chat
            .filter { $0.kind == .image }
            .map(\.localPath)
        inputText = ""
        let userVisibleText = displayedInput
        let contentToStore =
            userVisibleText.isEmpty ? (attachmentBundle.chat.isEmpty ? "" : "[Attached files]") : userVisibleText
        chatStore.addMessage(
            ChatMessage(
                role: .user, content: contentToStore, isStreaming: false,
                imagePaths: imagePathsToStore.isEmpty ? nil : imagePathsToStore,
                attachments: attachmentBundle.chat.isEmpty ? nil : attachmentBundle.chat
            ),
            to: targetConversationId
        )
        let standardAssistantMessageId = UUID()
        chatStore.addMessage(
            ChatMessage(
                id: standardAssistantMessageId,
                role: .assistant,
                content: "",
                isStreaming: true
            ),
            to: targetConversationId
        )
        startToolTraceTurn(
            conversationId: targetConversationId,
            assistantMessageId: standardAssistantMessageId,
            providerId: effectiveRuntimeProvider.id
        )
        if let conv = chatStore.conversation(for: targetConversationId), let ctxId = conv.contextId {
            projectContextStore.setLastActiveConversation(
                contextId: ctxId, folderPath: conv.contextFolderPath, conversationId: conv.id)
        }
        chatStore.beginTask(conversationId: targetConversationId)
        taskActivityStore.clear()
        // Preserve manual todos across turns; for a new standard turn reset all agent todos,
        // including stale canonical plan tasks from previous plans/conversations.
        todoStore.clearAgentTodos(includePlanCanonical: true)
        scheduleFallbackTurnStartEvent(
            conversationId: targetConversationId,
            providerId: effectiveRuntimeProvider.id
        )
        if coderMode == .agentSwarm { swarmProgressStore.clear() }

        let attachmentsToSend = attachmentBundle.llm.isEmpty ? nil : attachmentBundle.llm
        attachedComposerAttachments = []

        // 4. Build the prompt with mode-specific instructions
        let basePrompt = buildPrompt(userText: text, shouldRunPlanInline: shouldRunPlanInline)
        let prompt = attachmentBundle.fallbackPreamble.isEmpty
            ? basePrompt
            : "\(attachmentBundle.fallbackPreamble)\n\n\(basePrompt)"

        // 5. Execute async stream
        let isPlanMultiTurnFlow = (coderMode == .plan || shouldRunPlanInline) && planFlowPhase == .analyzing
        Task {
            var traceOutcome: ToolTraceTurnOutcome = .success
            do {
                if isPlanMultiTurnFlow {
                    // Multi-turn forced sequential plan flow
                    try await runMultiTurnPlanFlow(
                        provider: effectiveRuntimeProvider,
                        ctx: ctx,
                        attachmentsToSend: attachmentsToSend,
                        conversationId: targetConversationId,
                        shouldRunPlanInline: shouldRunPlanInline
                    )
                } else {
                    // Standard single-stream flow (non-plan modes + plan build)
                    let streamResult = try await flowCoordinator.runStream(
                        provider: effectiveRuntimeProvider,
                        prompt: prompt,
                        context: ctx,
                        attachments: attachmentsToSend,
                        onText: { content in
                            applyStreamingUpdate(
                                content: content,
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
                        onSignal: nil
                    )

                    let finalizedResult = try await continueIfPrematureStub(
                        initial: streamResult,
                        provider: effectiveRuntimeProvider,
                        originalPrompt: prompt,
                        context: ctx,
                        conversationId: targetConversationId,
                        hideContentDuringPlanDiscovery: false
                    )

                    // 6. Handle stream completion (plan options, swarm delegation)
                    await handleStreamResult(
                        conversationId: targetConversationId,
                        finalizedResult, shouldRunPlanInline: shouldRunPlanInline,
                        ctx: ctx, attachmentsToSend: attachmentsToSend, prompt: prompt
                    )
                }
            } catch {
                chatStore.setLastAssistantStreaming(false, in: targetConversationId)
                clearStreamingReasoning(for: targetConversationId)
                if isInterruptedStreamError(error) {
                    traceOutcome = .aborted
                    await MainActor.run {
                        flowCoordinator.interrupt()
                    }
                } else {
                    traceOutcome = .failed
                    chatStore.updateLastAssistantMessage(
                        content: userFacingStreamError(error), in: targetConversationId)
                    await MainActor.run {
                        flowCoordinator.fail()
                    }
                }
            }
            finalizeToolTraceTurn(conversationId: targetConversationId, outcome: traceOutcome)
            chatStore.endTask(conversationId: targetConversationId)
        }
    }

    // MARK: - Multi-Turn Plan Flow

    private func runMultiTurnPlanFlow(
        provider: any LLMProvider,
        ctx: WorkspaceContext,
        attachmentsToSend: [LLMAttachment]?,
        conversationId: UUID,
        shouldRunPlanInline: Bool
    ) async throws {
        // ========================
        // PHASE 1: Codebase Analysis
        // ========================
        await MainActor.run {
            planFlowPhase = .analyzing
            planStreamingContent = ""
        }

        let analysisPrompt = buildPhase1AnalysisPrompt(userRequest: planUserRequest)
        let analysisResult = try await flowCoordinator.runStream(
            provider: provider,
            prompt: analysisPrompt,
            context: ctx,
            attachments: attachmentsToSend,
            onText: { [self] content in
                planStreamingContent = content
                applyStreamingUpdate(
                    content: content,
                    conversationId: conversationId
                )
            },
            onRaw: { [self] t, p, pid in
                handleRawStreamEvent(type: t, payload: p, providerId: pid, conversationId: conversationId)
            },
            onError: { [self] content in
                DispatchQueue.main.async {
                    chatStore.updateLastAssistantMessage(content: content, in: conversationId)
                }
            },
            onSignal: nil
        )

        await MainActor.run {
            planAnalysisContext = analysisResult.fullText
            planStreamingContent = analysisResult.fullText
            chatStore.updateLastAssistantMessage(
                content: "✅ **Phase 1/3 — Analysis complete.** Generating questions…",
                in: conversationId,
                persistImmediately: true
            )
            chatStore.setLastAssistantStreaming(false, in: conversationId)
        }

        // ========================
        // PHASE 2: Clarification Questions
        // ========================
        await MainActor.run {
            planFlowPhase = .questioning
            planStreamingContent = ""
            let questionAssistantMessageId = UUID()
            chatStore.addMessage(
                ChatMessage(id: questionAssistantMessageId, role: .assistant, content: "", isStreaming: true),
                to: conversationId
            )
            startToolTraceTurn(
                conversationId: conversationId,
                assistantMessageId: questionAssistantMessageId,
                providerId: provider.id
            )
        }

        let questionPrompt = buildPhase2QuestionPrompt(
            userRequest: planUserRequest,
            analysisContext: analysisResult.fullText
        )
        let questionResult = try await flowCoordinator.runStream(
            provider: provider,
            prompt: questionPrompt,
            context: ctx,
            attachments: nil,
            onText: { [self] content in
                planStreamingContent = content
                applyStreamingUpdate(
                    content: content,
                    conversationId: conversationId
                )
            },
            onRaw: { [self] t, p, pid in
                handleRawStreamEvent(type: t, payload: p, providerId: pid, conversationId: conversationId)
            },
            onError: { [self] content in
                DispatchQueue.main.async {
                    chatStore.updateLastAssistantMessage(content: content, in: conversationId)
                }
            },
            onSignal: nil
        )

        let questionText = questionResult.fullText.trimmingCharacters(in: .whitespacesAndNewlines)
        let needsQuestions = !questionText.contains("NO_QUESTIONS_NEEDED")

        if needsQuestions {
            // Parse questions and pause for user input
            let classification = PlanOutputClassifier.classify(
                fullText: questionText,
                current: .questioning,
                coderMode: coderMode,
                shouldRunPlanInline: shouldRunPlanInline
            )
            await MainActor.run {
                if case .awaitingClarification(let q) = classification.planningState {
                    planningState = .awaitingClarification(questions: q)
                } else {
                    // Fallback: treat entire text as questions
                    planningState = .awaitingClarification(questions: questionText)
                }
                planStreamingContent = questionText
                chatStore.updateLastAssistantMessage(
                    content: questionText, in: conversationId, persistImmediately: true
                )
                chatStore.setLastAssistantStreaming(false, in: conversationId)
                if shouldAutoOpenPlanPanel(trigger: .awaitingClarification), !showPlanPanel {
                    openPlanPanelForCurrentContext(
                        preserveHistorySelection: false,
                        source: .automaticFlow
                    )
                }
            }
            // STOP — Phase 3 will be triggered by submitPlanClarificationAnswers() → continuePlanFlowPhase3()
            return
        }

        // No questions needed — proceed directly to Phase 3
        await MainActor.run {
            chatStore.updateLastAssistantMessage(
                content: "✅ **Phase 2/3 — No questions needed.** Generating plan...",
                in: conversationId,
                persistImmediately: true
            )
            chatStore.setLastAssistantStreaming(false, in: conversationId)
            planStreamingContent = ""
        }
        try await runPlanFlowPhase3(
            provider: provider,
            ctx: ctx,
            conversationId: conversationId,
            shouldRunPlanInline: shouldRunPlanInline
        )
    }

    private func runPlanFlowPhase3(
        provider: any LLMProvider,
        ctx: WorkspaceContext,
        conversationId: UUID,
        shouldRunPlanInline: Bool
    ) async throws {
        // ========================
        // PHASE 3: Plan Generation
        // ========================
        await MainActor.run { planFlowPhase = .generating }

        // Create new assistant message for Phase 3 streaming
        await MainActor.run {
            let generationAssistantMessageId = UUID()
            chatStore.addMessage(
                ChatMessage(id: generationAssistantMessageId, role: .assistant, content: "", isStreaming: true),
                to: conversationId
            )
            startToolTraceTurn(
                conversationId: conversationId,
                assistantMessageId: generationAssistantMessageId,
                providerId: provider.id
            )
        }

        let generationPrompt = buildPhase3GenerationPrompt(
            userRequest: planUserRequest,
            analysisContext: planAnalysisContext,
            clarificationAnswers: planClarificationAnswers
        )

        let generationResult = try await flowCoordinator.runStream(
            provider: provider,
            prompt: generationPrompt,
            context: ctx,
            attachments: nil,
            onText: { [self] content in
                planStreamingContent = content
                applyStreamingUpdate(
                    content: content,
                    conversationId: conversationId
                )
            },
            onRaw: { [self] t, p, pid in
                handleRawStreamEvent(type: t, payload: p, providerId: pid, conversationId: conversationId)
            },
            onError: { [self] content in
                DispatchQueue.main.async {
                    chatStore.updateLastAssistantMessage(content: content, in: conversationId)
                }
            },
            onSignal: nil
        )

        func parsePlanOptions(_ text: String) -> [PlanOption] {
            let strict = PlanOptionsParser.parseStrict(from: text)
            if !strict.isEmpty { return strict }
            return PlanOptionsParser.parse(from: text)
        }

        func areAllOptionsTodoCompliant(_ options: [PlanOption]) -> Bool {
            guard !options.isEmpty else { return false }
            let compliant = PlanOptionsParser.todoCompliantOptions(from: options)
            return compliant.count == options.count
        }

        var full = generationResult.fullText
        var options = parsePlanOptions(full)

        // Hard enforcement: every option must contain an explicit `## Todo` section.
        let maxRepairAttempts = 2
        var repairAttempt = 0
        while !areAllOptionsTodoCompliant(options), repairAttempt < maxRepairAttempts {
            repairAttempt += 1

            await MainActor.run {
                planStreamingContent = ""
                chatStore.updateLastAssistantMessage(
                    content: "Plan format validation failed: every option must include `## Todo` with checklist items. Regenerating (attempt \(repairAttempt)/\(maxRepairAttempts))...",
                    in: conversationId,
                    persistImmediately: true
                )
                chatStore.setLastAssistantStreaming(true, in: conversationId)
            }

            let repairPrompt = buildPhase3TodoComplianceRepairPrompt(
                userRequest: planUserRequest,
                analysisContext: planAnalysisContext,
                clarificationAnswers: planClarificationAnswers,
                invalidPlanOutput: full
            )

            let repairedResult = try await flowCoordinator.runStream(
                provider: provider,
                prompt: repairPrompt,
                context: ctx,
                attachments: nil,
                onText: { [self] content in
                    planStreamingContent = content
                    applyStreamingUpdate(
                        content: content,
                        conversationId: conversationId
                    )
                },
                onRaw: { [self] t, p, pid in
                    handleRawStreamEvent(type: t, payload: p, providerId: pid, conversationId: conversationId)
                },
                onError: { [self] content in
                    DispatchQueue.main.async {
                        chatStore.updateLastAssistantMessage(content: content, in: conversationId)
                    }
                },
                onSignal: nil
            )

            full = repairedResult.fullText
            options = parsePlanOptions(full)
        }

        await MainActor.run { planStreamingContent = full }
        chatStore.updateLastAssistantMessage(content: full, in: conversationId, persistImmediately: true)
        chatStore.setLastAssistantStreaming(false, in: conversationId)
        clearStreamingReasoning(for: conversationId)

        if !options.isEmpty, areAllOptionsTodoCompliant(options) {
            let compliantOptions = PlanOptionsParser.todoCompliantOptions(from: options)
            let board = PlanBoard.build(from: full, options: compliantOptions)
            chatStore.setPlanBoard(board, for: conversationId)
            let currentConv = chatStore.conversation(for: conversationId)
            let parsedSummary = PlanOptionsParser.extractDisplaySummary(from: full)
            let summaryContent = "Plan ready: \(parsedSummary.title)\n\nOpen the Planning panel to select an option."
            chatStore.updateLastAssistantMessage(content: summaryContent, in: conversationId, persistImmediately: true)

            let entry = planHistoryStore.createEntry(
                conversationId: conversationId,
                contextId: currentConv?.contextId,
                contextFolderPath: currentConv?.contextFolderPath,
                title: parsedSummary.title,
                markdown: full,
                options: compliantOptions,
                chosenPath: board.chosenPath,
                tags: [],
                sourceMessageId: nil
            )
            let sourceMessageId = chatStore.attachPlanEntryToLastAssistant(
                conversationId: conversationId,
                entry: entry
            )
            planHistoryStore.updateSourceMessageId(id: entry.id, sourceMessageId: sourceMessageId)

            if shouldRunPlanInline {
                let cid = conversationId
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
                planFlowPhase = .proposalReady
                planningState = .awaitingChoice(planContent: full, options: compliantOptions)
                if shouldAutoOpenPlanPanel(trigger: .awaitingChoice), !showPlanPanel {
                    openPlanPanelForCurrentContext(
                        preserveHistorySelection: false,
                        source: .automaticFlow
                    )
                }
            }
        } else {
            // Invalid format: no executable options with mandatory `## Todo`.
            chatStore.updateLastAssistantMessage(
                content: "Plan format invalid after \(maxRepairAttempts) retries: every option must include `## Todo` with checklist items. Please run Plan again.",
                in: conversationId,
                persistImmediately: true
            )
            await MainActor.run {
                planFlowPhase = .idle
                planningState = .idle
            }
        }
    }

    @MainActor
    private func continuePlanFlowPhase3() {
        guard let targetConversationId = conversationId else { return }

        let effectiveProvider: any LLMProvider
        if let selected = providerRegistry.selectedProvider {
            if selected.isAuthenticated() {
                effectiveProvider = selected
            } else if let fallback = preferredRealProvider() {
                effectiveProvider = fallback
            } else {
                appendTechnicalErrorMessage(
                    "[Plan] No authenticated provider available to continue.",
                    in: targetConversationId
                )
                return
            }
        } else {
            appendTechnicalErrorMessage(
                "[Plan] No provider selected.",
                in: targetConversationId
            )
            return
        }

        let ctx = effectiveContext.toWorkspaceContext(
            openFiles: openFilesStore.openFilesForContext(linkedPaths: linkedContextPaths()),
            activeSelection: nil,
            activeFilePath: openFilesStore.openFilePath,
            scopeMode: ContextScopeMode(rawValue: contextScopeModeRaw) ?? .auto
        )

        let shouldRunPlanInline = (coderMode == .agent && planToggleEnabled)

        chatStore.beginTask(conversationId: targetConversationId)
        Task {
            var traceOutcome: ToolTraceTurnOutcome = .success
            do {
                try await runPostClarificationFlow(
                    provider: effectiveProvider,
                    ctx: ctx,
                    conversationId: targetConversationId,
                    shouldRunPlanInline: shouldRunPlanInline
                )
            } catch {
                chatStore.setLastAssistantStreaming(false, in: targetConversationId)
                clearStreamingReasoning(for: targetConversationId)
                if isInterruptedStreamError(error) {
                    traceOutcome = .aborted
                    flowCoordinator.interrupt()
                } else {
                    traceOutcome = .failed
                    chatStore.updateLastAssistantMessage(
                        content: userFacingStreamError(error), in: targetConversationId
                    )
                    flowCoordinator.fail()
                }
            }
            finalizeToolTraceTurn(conversationId: targetConversationId, outcome: traceOutcome)
            chatStore.endTask(conversationId: targetConversationId)
        }
    }

    /// After clarification answers, re-analyze and decide: ask more questions or proceed to plan generation.
    private func runPostClarificationFlow(
        provider: any LLMProvider,
        ctx: WorkspaceContext,
        conversationId: UUID,
        shouldRunPlanInline: Bool
    ) async throws {
        // Re-analysis phase: LLM analyzes based on the user's answers
        await MainActor.run {
            planFlowPhase = .analyzing
            planStreamingContent = ""
        }

        // Create new assistant message for re-analysis streaming
        await MainActor.run {
            let reanalysisAssistantMessageId = UUID()
            chatStore.addMessage(
                ChatMessage(id: reanalysisAssistantMessageId, role: .assistant, content: "", isStreaming: true),
                to: conversationId
            )
            startToolTraceTurn(
                conversationId: conversationId,
                assistantMessageId: reanalysisAssistantMessageId,
                providerId: provider.id
            )
        }

        let reAnalysisPrompt = buildPostClarificationAnalysisPrompt(
            userRequest: planUserRequest,
            analysisContext: planAnalysisContext,
            clarificationAnswers: planClarificationAnswers
        )

        let reAnalysisResult = try await flowCoordinator.runStream(
            provider: provider,
            prompt: reAnalysisPrompt,
            context: ctx,
            attachments: nil,
            onText: { [self] content in
                planStreamingContent = content
                applyStreamingUpdate(
                    content: content,
                    conversationId: conversationId
                )
            },
            onRaw: { [self] t, p, pid in
                handleRawStreamEvent(type: t, payload: p, providerId: pid, conversationId: conversationId)
            },
            onError: { [self] content in
                DispatchQueue.main.async {
                    chatStore.updateLastAssistantMessage(content: content, in: conversationId)
                }
            },
            onSignal: nil
        )

        let reAnalysisText = reAnalysisResult.fullText.trimmingCharacters(in: .whitespacesAndNewlines)

        // Check if the LLM produced more questions or is ready for plan generation
        let classification = PlanOutputClassifier.classify(
            fullText: reAnalysisText,
            current: .questioning,
            coderMode: coderMode,
            shouldRunPlanInline: shouldRunPlanInline
        )

        if case .awaitingClarification(let q) = classification.planningState {
            // LLM needs more answers — pause again for user input
            await MainActor.run {
                planAnalysisContext += "\n\n--- Follow-up analysis ---\n\(reAnalysisText)"
                planFlowPhase = .questioning
                planningState = .awaitingClarification(questions: q)
                planStreamingContent = reAnalysisText
                chatStore.updateLastAssistantMessage(
                    content: q,
                    in: conversationId,
                    persistImmediately: true
                )
                chatStore.setLastAssistantStreaming(false, in: conversationId)
                if shouldAutoOpenPlanPanel(trigger: .awaitingClarification), !showPlanPanel {
                    openPlanPanelForCurrentContext(
                        preserveHistorySelection: false,
                        source: .automaticFlow
                    )
                }
            }
            // STOP — will re-enter via submitPlanClarificationAnswers → continuePlanFlowPhase3
            return
        }

        // No more questions — update analysis context and proceed to Phase 3
        await MainActor.run {
            planAnalysisContext += "\n\n--- Post-clarification analysis ---\n\(reAnalysisText)"
            chatStore.updateLastAssistantMessage(
                content: "✅ **Analysis complete.** Generating plan…",
                in: conversationId,
                persistImmediately: true
            )
            chatStore.setLastAssistantStreaming(false, in: conversationId)
            planStreamingContent = ""
        }

        try await runPlanFlowPhase3(
            provider: provider,
            ctx: ctx,
            conversationId: conversationId,
            shouldRunPlanInline: shouldRunPlanInline
        )
    }

    private func continueIfPrematureStub(
        initial: (fullText: String, pendingSwarmTask: String?),
        provider: any LLMProvider,
        originalPrompt: String,
        context: WorkspaceContext,
        conversationId: UUID,
        hideContentDuringPlanDiscovery: Bool = false
    ) async throws -> (fullText: String, pendingSwarmTask: String?) {
        var combinedText = initial.fullText
        var combinedSwarmTask = initial.pendingSwarmTask
        let maxAutoContinuationRounds = 3
        var round = 0

        while combinedSwarmTask == nil,
              shouldAutoContinueStub(combinedText),
              round < maxAutoContinuationRounds {
            round += 1
            let continuationPrompt = """
            Immediately continue your previous response and complete the task to a concrete outcome.
            Execute needed steps autonomously (analyze, act, verify, fix if needed) and do not stop at intentions.

            Original request:
            \(originalPrompt)

            Text already sent:
            \(combinedText)
            """

            let prior = combinedText
            let followUp = try await flowCoordinator.runStream(
                provider: provider,
                prompt: continuationPrompt,
                context: context,
                attachments: nil,
                onText: { deltaFull in
                    let combined = prior + "\n" + deltaFull
                    let displayContent = hideContentDuringPlanDiscovery
                        ? "Planning in progress… Open the Planning panel to see the result."
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
                        let combined = prior + "\n" + content
                        chatStore.updateLastAssistantMessage(content: combined, in: conversationId)
                    }
                },
                onSignal: nil
            )

            combinedText = prior + "\n" + followUp.fullText
            combinedSwarmTask = combinedSwarmTask ?? followUp.pendingSwarmTask
        }

        return (fullText: combinedText, pendingSwarmTask: combinedSwarmTask)
    }

    private func shouldAutoContinueStub(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        let wordCount = trimmed.split(whereSeparator: \.isWhitespace).count
        guard wordCount <= 260 else { return false }
        let low = trimmed.lowercased()
        let stubSignals = [
            "i'll start",
            "i will start",
            "i'll begin",
            "i will begin",
            "first, i'll",
            "first i will",
            "let me start",
            "let me begin",
            "let me check",
            "i can continue",
            "would you like me to",
            "if you want i can",
            "next i'll",
            "next i will",
        ]
        if stubSignals.contains(where: { low.contains($0) }) {
            return true
        }
        if low.hasSuffix("...") || low.hasSuffix(":") {
            return true
        }
        return false
    }

    // MARK: - Resolve Runtime Provider

    private func resolveRuntimeProvider(
        selectedProvider: any LLMProvider,
        shouldRunPlanInline: Bool,
        forcePlanInline: Bool
    ) -> (any LLMProvider)? {
        // Plan/Swarm use real selected providers, without virtual providers.
        if forcePlanInline || shouldRunPlanInline || coderMode == .plan || coderMode == .agentSwarm {
            return selectedProvider
        }
        // Code Review Multi-Swarm: build dedicated multi-swarm provider
        if coderMode == .codeReviewMultiSwarm {
            let cfg = providerFactoryConfig()
            if let multiSwarm = ProviderFactory.codeReviewMultiSwarmProvider(
                config: cfg,
                executionController: executionController,
                agentProviderId: providerRegistry.selectedProviderId,
                codebaseIndex: workspaceStore.codebaseIndex,
                workspacePaths: workspaceStore.activeWorkspacePaths
            ) {
                return multiSwarm
            }
            // Fallback to selected provider if factory returns nil
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
                    "[Multi-account \(kind.displayName): \(reason). Configure accounts or reset limits in Settings.]",
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
                            codebaseIndex: workspaceStore.codebaseIndex,
                            workspacePaths: workspaceStore.activeWorkspacePaths,
                            environmentOverride: env)
                    case .claude:
                        return ProviderFactory.claudeProvider(
                            config: cfg,
                            executionController: executionController,
                            codebaseIndex: workspaceStore.codebaseIndex,
                            workspacePaths: workspaceStore.activeWorkspacePaths,
                            environmentOverride: env)
                    case .gemini:
                        return ProviderFactory.geminiProvider(
                            config: cfg,
                            executionController: executionController,
                            codebaseIndex: workspaceStore.codebaseIndex,
                            workspacePaths: workspaceStore.activeWorkspacePaths,
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
            ? "[The user attached an image. Analyze it and respond.]" : userText

        // Plan mode: response to clarification questions → include context to proceed
        if shouldUseClarificationPrompt(
            coderMode: coderMode,
            planningState: planningState,
            shouldRunPlanInline: shouldRunPlanInline
        ),
            case .awaitingClarification(let questions) = planningState
        {
            prompt = """
            The user has answered your clarification questions.

            User's answers:
            \(userText.isEmpty ? "[No text provided]" : userText)

            The original questions were:
            \(questions)

            Next steps:
            1. Perform ADDITIONAL codebase analysis based on these answers (use Read, Glob, Grep).
            2. If you need MORE information, output ANOTHER ## Questions section (same A/B/C/D format).
            3. If you have ALL information needed, proceed to propose 2-4 options with ## Option and ## Todo sections.
            CRITICAL: Do NOT skip additional analysis. You are ALLOWED to ask follow-up questions.
            """
        }

        if coderMode == .ide {
            prompt =
                "Reply with text only. Do not modify files or run commands.\n\n" + prompt
        }
        if coderMode == .mcpServer { prompt = "[MCP Server] " + prompt }
        let isPlanningDiscoveryFlow =
            (coderMode == .plan || shouldRunPlanInline)
            && planFlowPhase != .building

        if isPlanningDiscoveryFlow {
            let planningInstructions = """
            **MANDATORY Planning Workflow — Follow these phases in EXACT order:**

            ## PHASE 1: CODEBASE ANALYSIS (ALWAYS REQUIRED)
            Before producing ANY output, you MUST:
            - Use Read, Glob, and Grep to explore at least 3-5 relevant files
            - Understand the project structure, dependencies, and constraints
            - DO NOT skip this phase. DO NOT produce questions or options without reading files first.

            ## PHASE 2: CLARIFICATION QUESTIONS (MANDATORY if ANY ambiguity exists)
            After analysis, if there is ANY uncertainty about scope, approach, or user preference:
            - Output ONLY a section with this EXACT format:

            ## Questions
            1. Question text?
            A) Option A text
            B) Option B text
            C) Option C text (optional)
            D) Other (specify)

            Rules: 1-4 questions max, each with 2-4 options A) B) C) D), mutually exclusive.
            Include "Other (specify)" ONLY for genuinely open-ended questions.
            DO NOT output anything else besides the ## Questions section.
            NEVER include ## Option or ## Todo in a response with ## Questions.

            ## PHASE 3: PLAN PROPOSAL (ONLY after Phases 1+2 resolved)
            Propose 2-4 concrete options:
            ## Option 1: Title
            Description, pros/cons.
            ## Todo
            - [ ] Step 1
            - [ ] Step 2

            CRITICAL: NEVER combine ## Questions and ## Option in the same response.
            Do not emit \(CoderIDEMarkers.todoWritePrefix) or \(CoderIDEMarkers.todoRead) during planning.
            """
            prompt = planningInstructions + "\n\n" + prompt
        } else if ProviderSupport.isAgentCompatibleProvider(id: providerRegistry.selectedProviderId) {
                let baseInstructions = """
                    **Todo Workflow (use only when truly needed):**
                    1. Start with analysis (read/search) first. Do NOT create todos before understanding the task.
                    2. If the task is simple (single action or <=2 concrete operations), do NOT emit todo markers.
                    3. If the task is genuinely multi-step, create ONE coherent todo list after analysis with only concrete, executable steps.
                    3b. For multi-step execution, emit the first \(CoderIDEMarkers.todoWritePrefix) update BEFORE the first command/edit/tool action.
                    4. Never create placeholder todos (forbidden examples: "Task", "Analysis", "Step 1", "Setup task panel", "Todo update").
                    5. Emit \(CoderIDEMarkers.showTaskPanel) only when a real todo list exists or when the user explicitly asks.
                    6. During execution, update status only for real todos: in_progress before work, done after completion.
                    7. Emit \(CoderIDEMarkers.todoRead) only for resume/reconciliation when needed, never as a default first action.
                    8. If MCP is available and external/domain capabilities are needed, verify MCP availability first with `mcp_list_servers`, then `mcp_list_tools`, and run calls with `mcp_call`.
                    9. When MCP is used, explicitly report which MCP servers and MCP tools were used.
                    10. If context contains a required marker `[CODERIDE:policy_ack|hash=...]`, emit it once before any operational tool action.
                    To update plan steps use marker:
                    \(CoderIDEMarkers.planStepPrefix)step_id=1|status=running]
                    For code searches with rg, you can emit markers with results:
                    \(CoderIDEMarkers.instantGrepPrefix)query=foo|pathScope=Sources|matchesCount=3|previewLines=Sources/A.swift:12:line]
                    Read files in parallel batches (max 8 per batch) when broad context is needed. To track the batch you can emit:
                    \(CoderIDEMarkers.readBatchPrefix)count=8|files=FileA.swift,FileB.swift|group_id=batch-1]
                    For concurrent web searches (max 4 queries in parallel), emit status markers:
                    \(CoderIDEMarkers.webSearchPrefix)queryId=q1|query=swift concurrency|status=started|group_id=web-1]
                    """
                if agentAutoDelegateSwarm {
                    let swarmInstructions =
                        """
                        Swarm delegation is optional and must be conservative.
                        - Do NOT delegate if you can complete the task yourself in one linear flow (roughly <=2 concrete operations).
                        - Delegate only when there are independent workstreams or clearly different specialist roles that benefit from parallel execution.
                        - Do not delegate for basic read/search/edit/command sequences that a single agent can handle.
                        - If you delegate, provide a precise objective with concrete workstreams using:
                        \(CoderIDEMarkers.invokeSwarmPrefix)TASK_DESCRIPTION\(CoderIDEMarkers.invokeSwarmSuffix)

                        """
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
                    prompt += "\n\n## Current todos\n\(todoSection)"
                }
            }

        let convoContext = recentConversationContextForPrompt()
        if !convoContext.isEmpty {
            prompt += "\n\n## Conversation context (recent)\n\(convoContext)\nUse this context to answer follow-ups consistently."
        }
        return prompt
    }

    private func recentConversationContextForPrompt(maxMessages: Int = 8, maxCharsPerMessage: Int = 700) -> String {
        guard let conv = chatStore.conversation(for: conversationId) else { return "" }
        let cleaned = conv.messages
            .filter { !$0.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .suffix(maxMessages)

        guard !cleaned.isEmpty else { return "" }
        var lines: [String] = []
        for msg in cleaned {
            let roleLabel = msg.role == .user ? "User" : "Assistant"
            let normalized = ChatStore.stripCoderideMarkers(msg.content)
                .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !normalized.isEmpty else { continue }
            let excerpt = normalized.count > maxCharsPerMessage
                ? String(normalized.prefix(maxCharsPerMessage)) + "…"
                : normalized
            lines.append("- \(roleLabel): \(excerpt)")
        }
        return lines.joined(separator: "\n")
    }

    // MARK: - Phase-Specific Plan Prompts

    private func buildPhase1AnalysisPrompt(userRequest: String) -> String {
        """
        **Phase: Codebase Analysis (ANALYSIS ONLY)**

        You are analyzing a codebase to prepare a plan. Your ONLY task is to explore and understand the codebase.

        User request: \(userRequest)

        Instructions:
        1. Use Read, Glob, and Grep to explore files relevant to this request.
        2. Identify key files, dependencies, current architecture, and constraints.
        3. Report your findings as structured analysis text.
        4. Do NOT propose solutions, options, or clarification questions.
        5. Do NOT generate ## Todo sections or ## Option headers.
        6. Focus on WHAT EXISTS, not what should change.
        7. Do not emit \(CoderIDEMarkers.todoWritePrefix) or \(CoderIDEMarkers.todoRead) markers.

        Output format: A structured analysis report of your findings.
        """
    }

    private func buildPostClarificationAnalysisPrompt(
        userRequest: String,
        analysisContext: String,
        clarificationAnswers: String
    ) -> String {
        """
        **Phase: Post-clarification Analysis**

        The user answered your clarification questions. Based on the answers, perform ADDITIONAL codebase analysis.

        User request: \(userRequest)

        Previous codebase analysis:
        \(analysisContext)

        User clarification answers:
        \(clarificationAnswers)

        Instructions:
        1. Use Read, Glob, and Grep to explore specific files relevant based on the user's answers.
        2. Deep-dive into the areas indicated by the user's choices.
        3. If after this analysis you have NEW uncertainties, generate additional questions using the format:

        ## Questions
        1. Question?
        A) Option A
        B) Option B
        C) Other (specify)

        4. If you have SUFFICIENT information, provide an analysis report without questions.
        5. Do NOT generate ## Option, ## Todo or plan proposals in this phase.
        6. Do NOT emit \(CoderIDEMarkers.todoWritePrefix) or \(CoderIDEMarkers.todoRead) markers.
        """
    }

    private func buildPhase2QuestionPrompt(userRequest: String, analysisContext: String) -> String {
        """
        **Phase: Clarification Questions**

        Based on the codebase analysis below, determine if you need clarifications from the user.

        User request: \(userRequest)

        Codebase analysis:
        \(analysisContext)

        Instructions:
        - If you have sufficient information to propose concrete implementation options, respond ONLY with: NO_QUESTIONS_NEEDED
        - If you need clarifications, generate 1-4 structured questions in this EXACT format:

        ## Questions
        1. Question text?
        A) First concrete option
        B) Second concrete option
        C) Third option (optional, only if useful)
        D) Other (specify)

        2. Second question?
        A) First option
        B) Second option

        STRICT rules for questions:
        - Minimum 1, maximum 4 questions
        - Each question MUST have 2-4 options labeled A) B) C) D)
        - Options must be mutually exclusive and concrete (not vague)
        - Include "D) Other (specify)" ONLY for genuinely open-ended questions
        - The header MUST be exactly "## Questions" (no localized alternatives)
        - Do NOT include ## Option, ## Todo or plan proposals
        - Do NOT emit \(CoderIDEMarkers.todoWritePrefix) or \(CoderIDEMarkers.todoRead) markers
        - The format must be EXACTLY as above: number + text + options A) B) C) on separate lines
        """
    }

    private func buildPhase3GenerationPrompt(
        userRequest: String,
        analysisContext: String,
        clarificationAnswers: String
    ) -> String {
        var prompt = """
        **Phase: Plan Generation**

        Generate 2-4 concrete implementation options based on the analysis and context below.

        User request: \(userRequest)

        Codebase analysis:
        \(analysisContext)
        """

        if !clarificationAnswers.isEmpty {
            prompt += """

            User clarification answers:
            \(clarificationAnswers)
            """
        }

        prompt += """

        Instructions:
        - Propose 2-4 concrete options using this EXACT format for each:

        ## Option 1: Title
        Description of the approach...

        **Pros:** ...
        **Cons:** ...
        **Complexity:** Low/Medium/High

        ## Todo
        - [ ] Step 1
        - [ ] Step 2
        - [ ] Step 3

        ## Option 2: Title
        ...

        Rules:
        - Each option MUST include a section header exactly `## Todo` (double hash).
        - Under each `## Todo`, include 3-8 checklist items using `- [ ] ...`.
        - Do NOT use alternative headers like "Tasks", "Steps", or "Checklist".
        - Steps must be concrete and directly implementable.
        - Do NOT ask questions or request clarifications
        - Do NOT emit \(CoderIDEMarkers.todoWritePrefix) or \(CoderIDEMarkers.todoRead) markers
        """

        return prompt
    }

    private func buildPhase3TodoComplianceRepairPrompt(
        userRequest: String,
        analysisContext: String,
        clarificationAnswers: String,
        invalidPlanOutput: String
    ) -> String {
        let clippedInvalidOutput = String(invalidPlanOutput.prefix(8_000))
        var prompt = """
        **Phase: Plan Format Repair**

        Your previous output is INVALID because one or more options are missing the required `## Todo` section.
        Rewrite the plan from scratch.

        User request: \(userRequest)

        Codebase analysis:
        \(analysisContext)
        """

        if !clarificationAnswers.isEmpty {
            prompt += """

            User clarification answers:
            \(clarificationAnswers)
            """
        }

        prompt += """

        Invalid previous output (for reference):
        \(clippedInvalidOutput)

        Hard constraints (MANDATORY):
        - Output 2-4 options using headers like `## Option 1: ...`
        - Every option MUST contain the exact header `## Todo`
        - Under every `## Todo`, include 3-8 checklist items using `- [ ]`
        - Do NOT use alternative headers like Tasks/Steps/Checklist
        - Output only the final markdown plan (no commentary)
        - Do NOT emit \(CoderIDEMarkers.todoWritePrefix) or \(CoderIDEMarkers.todoRead) markers
        """

        return prompt
    }

    // MARK: - Handle Raw Stream Events

    private func handleRawStreamEvent(
        type t: String, payload p: [String: String], providerId pid: String,
        conversationId convId: UUID?
    ) {
        if t == "policy_ack" {
            let enriched = processPolicyAckEvent(payload: p, providerId: pid, conversationId: convId)
            recordTaskActivity(type: t, payload: enriched, providerId: pid, conversationId: convId)
            return
        }
        if shouldHardBlockForMissingPolicyAck(
            type: t,
            payload: p,
            providerId: pid,
            conversationId: convId
        ) {
            return
        }
        if t == "reasoning", let output = p["output"], !output.isEmpty {
            let existing =
                streamingReasoningConversationId == convId
                ? streamingReasoningText
                : nil
            streamingReasoningText = Self.mergeReasoningText(
                existing: existing,
                incoming: output
            )
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
        recordTaskActivity(type: t, payload: p, providerId: pid, conversationId: convId)
    }

    @MainActor
    private func processPolicyAckEvent(
        payload: [String: String],
        providerId: String,
        conversationId: UUID?
    ) -> [String: String] {
        guard let turn = resolveToolTraceTurn(conversationId: conversationId, providerId: providerId) else {
            return payload
        }
        guard var state = policyAckStateByMessage[turn.assistantMessageId] else {
            return payload
        }

        let receivedHash = (payload["hash"] ?? payload["policy_hash"] ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        var enriched = payload
        enriched["expected_hash"] = state.expectedHash

        if receivedHash == state.expectedHash {
            state.acknowledgedHash = receivedHash
            enriched["status"] = "acknowledged"
            enriched["title"] = payload["title"] ?? "Policy acknowledged"
            enriched["detail"] = payload["detail"] ?? "Policy hash accepted"
        } else {
            enriched["status"] = "invalid"
            enriched["title"] = payload["title"] ?? "Policy acknowledgment invalid"
            enriched["detail"] = payload["detail"] ?? "Expected hash \(state.expectedHash)"
        }
        policyAckStateByMessage[turn.assistantMessageId] = state
        return enriched
    }

    @MainActor
    private func shouldHardBlockForMissingPolicyAck(
        type: String,
        payload: [String: String],
        providerId: String,
        conversationId: UUID?
    ) -> Bool {
        guard agentsHardBlockEnabled else { return false }
        guard ToolTraceVisibility.requiresPolicyAck(type: type, payload: payload) else { return false }
        guard let turn = resolveToolTraceTurn(conversationId: conversationId, providerId: providerId) else {
            return false
        }
        guard var state = policyAckStateByMessage[turn.assistantMessageId] else {
            return false
        }
        if state.isSatisfied { return false }
        if state.violationEmitted { return true }

        state.violationEmitted = true
        policyAckStateByMessage[turn.assistantMessageId] = state
        emitPolicyAckViolation(
            expectedHash: state.expectedHash,
            incomingType: type,
            providerId: providerId,
            conversationId: conversationId
        )
        return true
    }

    @MainActor
    private func emitPolicyAckViolation(
        expectedHash: String,
        incomingType: String,
        providerId: String,
        conversationId: UUID?
    ) {
        let detail =
            "Missing required marker [CODERIDE:policy_ack|hash=\(expectedHash)] before event '\(incomingType)'."
        recordTaskActivity(
            type: "tool_execution_error",
            payload: [
                "title": "Policy acknowledgment required",
                "detail": detail,
                "status": "failed",
                "error_code": "policy_ack_missing",
                "expected_hash": expectedHash,
            ],
            providerId: providerId,
            conversationId: conversationId
        )
        appendTechnicalErrorMessage(
            "[Policy error] Mandatory AGENTS/SKILL acknowledgment missing. Emit [CODERIDE:policy_ack|hash=\(expectedHash)] before using tools.",
            in: conversationId
        )
        stopTaskForPolicyViolation(conversationId: conversationId)
    }

    @MainActor
    private func stopTaskForPolicyViolation(conversationId: UUID?) {
        let scope = executionScopeForCurrentMode()
        executionController.terminate(scope: scope)
        flowCoordinator.interrupt()
        taskFlushTask?.cancel()
        taskFlushTask = nil
        flushPendingTaskActivities()
        if let conversationId {
            chatStore.setLastAssistantStreaming(false, in: conversationId)
            clearStreamingReasoning(for: conversationId)
        }
        finalizeToolTraceTurn(conversationId: conversationId, outcome: .failed)
        cancelFallbackTurnStartEvent()
        chatStore.endTask(conversationId: conversationId)
        activeBuildPlanConversationId = nil
        if planFlowPhase == .building {
            planFlowPhase = .proposalReady
        }
    }

    static func shouldShowFinalChatActions(
        conversation: Conversation?,
        isLoadingForCurrentConversation: Bool
    ) -> Bool {
        guard !isLoadingForCurrentConversation else { return false }
        guard let conversation else { return false }
        guard conversation.messages.contains(where: { $0.role == .assistant }) else { return false }
        guard let lastMessage = conversation.messages.last else { return false }
        return lastMessage.role == .assistant && !lastMessage.isStreaming
    }

    static func mergeReasoningText(existing: String?, incoming: String) -> String {
        let incomingTrimmed = incoming.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !incomingTrimmed.isEmpty else { return existing ?? "" }
        guard let existing, !existing.isEmpty else {
            return String(incoming.prefix(24_000))
        }

        if incoming == existing { return existing }
        if incoming.hasPrefix(existing) {
            return String(incoming.prefix(24_000))
        }
        if existing.hasPrefix(incoming) || existing.contains(incoming) {
            return existing
        }
        if incoming.contains(existing) {
            return String(incoming.prefix(24_000))
        }

        let overlap = reasoningSuffixPrefixOverlapLength(lhs: existing, rhs: incoming)
        if overlap > 0 {
            let suffixStart = incoming.index(incoming.startIndex, offsetBy: overlap)
            let merged = existing + String(incoming[suffixStart...])
            return String(merged.suffix(24_000))
        }

        let separator =
            existing.hasSuffix("\n") || incoming.hasPrefix("\n")
            ? "\n"
            : "\n\n"
        let merged = existing + separator + incoming
        return String(merged.suffix(24_000))
    }

    private static func reasoningSuffixPrefixOverlapLength(lhs: String, rhs: String) -> Int {
        let maxOverlap = min(lhs.count, rhs.count, 1_024)
        guard maxOverlap > 0 else { return 0 }
        for size in stride(from: maxOverlap, through: 1, by: -1) {
            if lhs.suffix(size) == rhs.prefix(size) {
                return size
            }
        }
        return 0
    }

    private func clearStreamingReasoning(for conversationId: UUID?) {
        // Flush any pending throttled content before switching away from streaming mode.
        flushStreamingContent()
        guard let id = conversationId, streamingReasoningConversationId == id else { return }
        streamingReasoningText = nil
        streamingReasoningConversationId = nil
    }

    private func applyStreamingUpdate(
        content: String,
        conversationId: UUID?
    ) {
        // Always store the latest content so we never lose data.
        pendingStreamContent = content
        pendingStreamConversationId = conversationId

        // If a throttle is already scheduled, let it pick up the latest content.
        if streamThrottleTask != nil { return }

        // Flush immediately for the first update (so the user sees something right away).
        flushStreamingContent()

        // Schedule the next flush after the throttle interval.
        streamThrottleTask = Task {
            let delay = UInt64(streamThrottleInterval * 1_000_000_000)
            try? await Task.sleep(nanoseconds: delay)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                streamThrottleTask = nil
                if let pending = pendingStreamContent {
                    pendingStreamContent = nil
                    chatStore.updateLastAssistantMessage(
                        content: pending,
                        in: pendingStreamConversationId,
                        persistImmediately: false
                    )
                    streamContentVersion &+= 1
                }
            }
        }
    }

    private func flushStreamingContent() {
        streamThrottleTask?.cancel()
        streamThrottleTask = nil
        guard let content = pendingStreamContent else { return }
        pendingStreamContent = nil
        chatStore.updateLastAssistantMessage(
            content: content,
            in: pendingStreamConversationId,
            persistImmediately: false
        )
        streamContentVersion &+= 1
    }

    // MARK: - Handle Stream Result (plan options + swarm delegation)

    private func handleStreamResult(
        conversationId streamConversationId: UUID,
        _ streamResult: (fullText: String, pendingSwarmTask: String?),
        shouldRunPlanInline: Bool,
        ctx: WorkspaceContext,
        attachmentsToSend: [LLMAttachment]?,
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

        // Handle plan options parsing (safety net — multi-turn flow handles its own classification)
        if (coderMode == .plan || shouldRunPlanInline)
            && planFlowPhase != .analyzing
            && planFlowPhase != .questioning
            && planFlowPhase != .generating
        {
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
                let summaryContent = "Clarifications needed to proceed with the plan. Open the Planning panel to answer the questions."
                chatStore.updateLastAssistantMessage(content: summaryContent, in: streamConversationId, persistImmediately: true)
                await MainActor.run {
                    if shouldAutoOpenPlanPanel(trigger: .awaitingClarification), !showPlanPanel {
                        openPlanPanelForCurrentContext(
                            preserveHistorySelection: false,
                            source: .automaticFlow
                        )
                    }
                }
            }
            if case .awaitingChoice(_, let opts) = classification.planningState {
                let board = PlanBoard.build(from: full, options: opts)
                chatStore.setPlanBoard(board, for: streamConversationId)
                let currentConv = chatStore.conversation(for: streamConversationId)
                let parsedSummary = PlanOptionsParser.extractDisplaySummary(from: full)
                let summaryContent = "Plan ready: \(parsedSummary.title)\n\nOpen the Planning panel to select an option."
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
                    if shouldAutoOpenPlanPanel(trigger: .awaitingChoice), !showPlanPanel {
                        openPlanPanelForCurrentContext(
                            preserveHistorySelection: false,
                            source: .automaticFlow
                        )
                    }
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
                let imageURLsToSend = attachmentsToSend?
                    .filter { $0.kind == .image }
                    .map(\.url)
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
        let agentProviderIdBeforeSwarm = providerRegistry.selectedProviderId
        guard let swarm = ProviderFactory.swarmProvider(
            config: providerFactoryConfig(),
            executionController: executionController,
            agentProviderId: agentProviderIdBeforeSwarm,
            codebaseIndex: workspaceStore.codebaseIndex,
            workspacePaths: workspaceStore.activeWorkspacePaths
        ), swarm.isAuthenticated() else { return }

        chatStore.addMessage(
            ChatMessage(
                role: .user, content: "[Delegated to swarm] \(task)",
                isStreaming: false), to: conversationId)
        let swarmAssistantMessageId = UUID()
        chatStore.addMessage(
            ChatMessage(id: swarmAssistantMessageId, role: .assistant, content: "", isStreaming: true),
            to: conversationId)
        if let conversationId {
            startToolTraceTurn(
                conversationId: conversationId,
                assistantMessageId: swarmAssistantMessageId,
                providerId: swarm.id
            )
        }
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
                    role: .user, content: "[Agent follow-up after swarm]",
                    isStreaming: false), to: conversationId)
            let followUpAssistantMessageId = UUID()
            chatStore.addMessage(
                ChatMessage(id: followUpAssistantMessageId, role: .assistant, content: "", isStreaming: true),
                to: conversationId)
            if let conversationId {
                startToolTraceTurn(
                    conversationId: conversationId,
                    assistantMessageId: followUpAssistantMessageId,
                    providerId: agentProvider.id
                )
            }
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
        let traceOutcome = toolTraceTurnOutcome(for: flowCoordinator.state)
        finalizeToolTraceTurn(conversationId: conversationId, outcome: traceOutcome)
        chatStore.endTask(conversationId: conversationId)
        await trySummarizeIfNeeded(ctx: ctx)
    }

    private func createCheckpointBeforeTurn(
        conversationId: UUID?, workspaceContext: WorkspaceContext
    ) throws {
        guard let conversationId else { return }
        let pathStrings = workspaceContext.workspacePaths.map(\.path)
        do {
            let states = try checkpointGitStore.captureSnapshots(
                conversationId: conversationId, workspacePaths: pathStrings)
            chatStore.createCheckpoint(for: conversationId, gitStates: states)
        } catch {
            // Cursor-style fallback: valid chat checkpoint even outside a Git repository.
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
            return "[Error] Operation not completed. Try again."
        }
        let lower = raw.lowercased()
        if lower.contains("coderengine.coderengineerror error 0")
            || (lower.contains("operation couldn") && lower.contains("coderengine"))
        {
            return
                "[Runtime error] Operation not completed by CLI provider. Check authentication and usage limits, then try again."
        }
        return raw
    }

    private func userFacingStreamError(_ error: Error) -> String {
        let detail = String(describing: error)
        let normalized = normalizeTechnicalErrorMessage(detail)
        if normalized == detail.trimmingCharacters(in: .whitespacesAndNewlines) {
            return "[Error] \(error.localizedDescription)"
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
                    finalizeToolTraceTurn(conversationId: convId, outcome: .aborted)
                    chatStore.endTask(conversationId: convId)
                }
            }

            // Try file restore only if we have git snapshots; on error continue
            // with chat-only rewind anyway (always-available behavior).
            if let checkpoint {
                for state in checkpoint.gitStates {
                    do {
                        try checkpointGitStore.restoreSnapshot(
                            ref: state.gitSnapshotRef, gitRoot: state.gitRootPath)
                    } catch {
                        await MainActor.run {
                            appendTechnicalErrorMessage(
                                "[Partial file rewind] \(error.localizedDescription)",
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
                        // Make sure the user message is removed from the chat
                        // (it remains only in the input for editing).
                        rewound = chatStore.rewindConversationToMessageCount(
                            lastUserIndex, conversationId: convId)
                    }
                } else {
                    // Fallback without checkpoint: remove last user turn + response.
                    rewound = chatStore.rewindConversationToMessageCount(
                        lastUserIndex, conversationId: convId)
                }
                guard rewound else {
                    appendTechnicalErrorMessage(
                        "[Rewind error: unable to restore chat state.]", in: convId)
                    isRewinding = false
                    return
                }

                // Cursor-style: bring the last user prompt back into the composer for editing.
                let placeholderImageOnly = "[Attached files]"
                inputText =
                    (lastUserMessage.content == placeholderImageOnly) ? "" : lastUserMessage.content
                attachedComposerAttachments = composerAttachments(from: lastUserMessage)
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

    private func composerAttachments(from message: ChatMessage) -> [ComposerAttachment] {
        let baseAttachments: [ChatAttachment]
        if let attachments = message.attachments, !attachments.isEmpty {
            baseAttachments = attachments
        } else if let imagePaths = message.imagePaths, !imagePaths.isEmpty {
            baseAttachments = imagePaths.map { path in
                ChatAttachment(
                    kind: .image,
                    originalName: URL(fileURLWithPath: path).lastPathComponent,
                    mimeType: nil,
                    localPath: path
                )
            }
        } else {
            return []
        }

        return baseAttachments.compactMap { item in
            let url = URL(fileURLWithPath: item.localPath)
            guard FileManager.default.fileExists(atPath: url.path) else { return nil }
            return ComposerAttachment(
                kind: item.kind,
                url: url,
                originalName: item.originalName,
                mimeType: item.mimeType,
                sizeBytes: item.sizeBytes
            )
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
                    finalizeToolTraceTurn(conversationId: conversationId, outcome: .aborted)
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
                                "[Partial file rewind] \(error.localizedDescription)",
                                in: conversationId
                            )
                        }
                    }
                }
            }

            await MainActor.run {
                // Remove the user message from the chat (and everything after it) so it can be
                // edited in the input and resent without duplicates.
                let rewound = chatStore.rewindConversationToMessageCount(
                    messageIndex, conversationId: conversationId)
                guard rewound else {
                    appendTechnicalErrorMessage(
                        "[Rewind error: unable to restore chat state.]", in: conversationId)
                    isRewinding = false
                    return
                }

                let placeholderImageOnly = "[Attached files]"
                inputText =
                    (userMessage.content == placeholderImageOnly) ? "" : userMessage.content
                attachedComposerAttachments = composerAttachments(from: userMessage)
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

    private func streamingStatusText(for message: ChatMessage) -> String {
        guard message.isStreaming, message.role == .assistant else { return "" }
        return TaskActivityStore.streamingStatusText(
            isPaused: executionController.runState == .paused,
            activities: taskActivityStore.activities
        )
    }

    @MainActor
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
                .trimmingCharacters(in: CharacterSet.whitespaces) ?? ""
            if !lastLine.isEmpty {
                return lastLine.count > 80 ? String(lastLine.prefix(77)) + "…" : lastLine
            }
        }
        return nil
    }
}
