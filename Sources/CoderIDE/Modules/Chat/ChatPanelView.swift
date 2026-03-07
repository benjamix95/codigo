import AppKit
import CoderEngine
import SwiftUI
import UniformTypeIdentifiers

struct ChatPanelView: View {
    @EnvironmentObject var providerRegistry: ProviderRegistry
    @EnvironmentObject var chatStore: ChatStore
    @EnvironmentObject var workspaceStore: WorkspaceStore
    @EnvironmentObject var projectContextStore: ProjectContextStore
    @EnvironmentObject var openFilesStore: OpenFilesStore
    @EnvironmentObject var editorNavigationDispatchStore: EditorNavigationDispatchStore
    @EnvironmentObject var taskActivityStore: TaskActivityStore
    @EnvironmentObject var toolTraceStore: ToolTraceStore
    @EnvironmentObject var todoStore: TodoStore
    @EnvironmentObject var swarmProgressStore: SwarmProgressStore
    @EnvironmentObject var executionController: ExecutionController
    @EnvironmentObject var providerUsageStore: ProviderUsageStore
    @EnvironmentObject var gitPanelStore: GitPanelStore
    @EnvironmentObject var planHistoryStore: PlanHistoryStore
    @EnvironmentObject var browserTabManager: BrowserTabManager
    @EnvironmentObject var pipelineIntegrationService: PipelineIntegrationService
    @Binding var selectedConversationId: UUID?
    let effectiveContext: EffectiveContext

     var conversationId: UUID? { selectedConversationId }

    /// Loading state only for the currently displayed thread (avoids showing loading for other threads).
     var isLoadingForCurrentConversation: Bool {
        chatStore.isTaskActive(for: conversationId)
            || pipelineIntegrationService.isRunning(for: conversationId)
            || (planFlowPhase == .building && activeBuildPlanConversationId == conversationId)
    }

    @Binding var coderMode: CoderMode
    @State  var inputText = ""
    @State  var isInputFocused: Bool = false
    @State  var didAutoFocusComposerOnLaunch: Bool = false
    @State  var composerAutoFocusTask: Task<Void, Never>?
    @State  var draftSaveTask: Task<Void, Never>?
    @AppStorage("codex_path")  var codexPath = ""
    @AppStorage("codex_sandbox")  var codexSandbox = ""
    @AppStorage("codex_session_full_access")  var codexSessionFullAccess = false
    @AppStorage("codex_ask_for_approval")  var codexAskForApproval = "never"
    @AppStorage("codex_model_override")  var codexModelOverride = ""
    @AppStorage("codex_reasoning_effort")  var codexReasoningEffort = "low"
    @AppStorage("codex_model_provider")  var codexModelProvider = ""
    @AppStorage("codex_prefer_responses_wire_api")
     var codexPreferResponsesWireAPI = false
    @AppStorage("swarm_orchestrator")  var swarmOrchestrator = "auto"
    @AppStorage("swarm_worker_backend")  var swarmWorkerBackend = "auto"
    @AppStorage("swarm_provider_auto_migrated_v1")  var swarmProviderAutoMigrated = false
    @AppStorage("swarm_enabled_roles")  var swarmEnabledRoles =
        "explorer,coder,debugger,reviewer,testWriter"
    @AppStorage("global_yolo")  var globalYolo = false
    @AppStorage("code_review_partitions")  var codeReviewPartitions = 3
    @AppStorage("code_review_analysis_only")  var codeReviewAnalysisOnly = false
    @AppStorage("code_review_max_rounds")  var codeReviewMaxRounds = 3
    @AppStorage("code_review_analysis_backend")  var codeReviewAnalysisBackend = "auto"
    @AppStorage("code_review_execution_backend")  var codeReviewExecutionBackend = "auto"
    @AppStorage("code_review_quick_commands_custom_json")
     var codeReviewQuickCommandsCustomJSON = ""
    @State  var pendingCodeReviewSessionConfigOverride: SessionConfig?
    @AppStorage("openai_api_key")  var openaiApiKey = ""
    @AppStorage("openai_model")  var openaiModel = "gpt-4o-mini"
    @AppStorage("anthropic_api_key")  var anthropicApiKey = ""
    @AppStorage("anthropic_model")  var anthropicModel = "claude-sonnet-4-6"
    @AppStorage("google_api_key")  var googleApiKey = ""
    @AppStorage("google_model")  var googleModel = "gemini-2.5-pro"
    @AppStorage("openrouter_api_key")  var openrouterApiKey = ""
    @AppStorage("openrouter_model")  var openrouterModel = "anthropic/claude-sonnet-4-6"
    @State  var codexModels: [CodexModel] = []
    @State  var geminiModels: [GeminiModel] = []
    @State  var showSwarmHelp = false
    @AppStorage("task_panel_enabled")  var taskPanelEnabled = false
    @AppStorage("plan_mode_backend")  var planModeBackend = "codex"
    @AppStorage("claude_path")  var claudePath = ""
    @AppStorage("claude_model")  var claudeModel = "claude-sonnet-4-6"
    @AppStorage("claude_allowed_tools")  var claudeAllowedTools = "Read,Edit,Bash,Write,Search,Task"
    @AppStorage("gemini_cli_path")  var geminiCliPath = ""
    @AppStorage("gemini_model_override")  var geminiModelOverride = ""
    @AppStorage("unified_tool_runtime_enabled")  var unifiedToolRuntimeEnabled = true
    @AppStorage("agents_hard_block_enabled")  var agentsHardBlockEnabled = true
    @AppStorage("mcp_edit_enforcement_enabled")  var mcpEditEnforcementEnabled = true
    @AppStorage("web_search_provider")  var webSearchProvider = "duckduckgo"
    @AppStorage("brave_search_api_key")  var braveSearchApiKey = ""
    @AppStorage("tavily_api_key")  var tavilyApiKey = ""
    @AppStorage("serper_api_key")  var serperApiKey = ""
    @AppStorage("multi_cli_account_enabled")  var multiCLIAccountEnabled = false
    @AppStorage("summarize_threshold")  var summarizeThreshold = 0.8
    @AppStorage("summarize_keep_last")  var summarizeKeepLast = 6
    @AppStorage("summarize_provider")  var summarizeProvider = "openai-api"
    @AppStorage("context_scope_mode")  var contextScopeModeRaw = "auto"
    @AppStorage("plan_panel_width")  var planPanelWidthStorage: Double = 320
    @AppStorage("debug_panel_width")  var debugPanelWidthStorage: Double = 340
    @AppStorage("swarm_panel_width")  var swarmPanelWidthStorage: Double = 360
    @AppStorage("code_review_panel_width")  var codeReviewPanelWidthStorage: Double = 380
    @AppStorage("git_panel_width")  var gitPanelWidthStorage: Double = 380
    @AppStorage("auto_resize_side_panels")  var autoResizeSidePanels = false
    @State  var planToggleEnabled = false
    @State  var debugToggleEnabled = false
    @Binding var showPlanPanel: Bool
    @Binding var showDebugPanel: Bool
    @Binding var showSwarmPanel: Bool
    @Binding var showCodeReviewPanel: Bool
    @Binding var showBrowserPanel: Bool
    @State  var selectedSwarmId: String?
    @State  var planPanelPresentationSource: PlanPanelPresentationSource = .manualDeepLink
    @ObservedObject var debugStore: DebugStore
    @State  var planningState: PlanningState = .idle
    @State  var planFlowPhase: PlanFlowPhase = .idle
    @State  var planAnalysisContext: String = ""
    @State  var planUserRequest: String = ""
    @State  var planClarificationAnswers: String = ""
    @State  var planClarificationCycles: Int = 0
    @State  var planStreamingContent: String = ""
    @State  var planStreamingContentByConversation: [UUID: String] = [:]
    /// Incremented whenever plan_request_user_input emits a new clarification round.
    @State  var planQuestionToolRequestEpoch: Int = 0
    @State  var planShouldRunInline: Bool = false
    @State  var activeBuildPlanConversationId: UUID?
    @State  var activeBuildAgentConversationId: UUID?
    @State  var suppressedEmptyBuildAssistantMessageIds: Set<UUID> = []
    @State  var isProviderReady = false
    @State  var attachedComposerAttachments: [ComposerAttachment] = []
    @State  var isSelectingImage = false
    @State  var isComposerDropTargeted = false
    @State  var isConvertingHeic = false
    @State  var pasteMonitor: Any?
    @State  var isSummarizing = false
    @State  var isRewinding = false
    @State  var isPlanSummaryCollapsed = false
    @State  var isPlanTabHovered = false
    @State  var isPlanShortcutCycling = false
    @State  var inlinePlanSummaries: [UUID: InlinePlanSummary] = [:]
    @State  var threadUIStateByConversation: [UUID: ChatThreadUIState] = [:]
    @State  var isRestoringThreadUIState = false
    @State  var hasJustCompletedTask = false
    @State  var showRateLimitAlert = false
    @State  var rateLimitAlertText = ""
    @State  var didCopyAllChat = false
    @State  var isFollowingLive = true
    @State  var newEventsWhileDetached = 0
    @State  var chatHeaderWidth: CGFloat = 800
    @StateObject  var voiceInputController = VoiceInputController()
    @State  var composerFrozenTimerState: ComposerFrozenTimerState?
    @State  var composerTimerAutoHideTask: Task<Void, Never>?
    @State  var composerTaskStartDate: Date?
    @State  var lastTaskEndedByManualStop = false

    // MARK: - Prompt Optimizer State
    @State  var isOptimizingPrompt = false
    @State  var showPromptOptimizerPopup = false
    @State  var optimizedPromptResult = ""
    @State  var promptOptimizerTask: Task<Void, Never>?

    @State  var isAnyAgentProviderReady = false
    @State  var checkProviderAuthGeneration = 0
    @State  var userModeOverrideUntilConversationChange = false
    @State  var suppressModeSyncForNextProviderChange = false
    @State  var ignoreNextConversationChangeReset = false
    @State  var skipNextLoadingCompletedHandling = false
    @StateObject  var flowCoordinator = ConversationFlowCoordinator()
    @StateObject  var networkMonitor = NetworkMonitor.shared
    @State  var pendingTaskActivities: [TaskActivity] = []
    @State  var pendingInstantGreps: [InstantGrepResult] = []
    @State  var taskFlushTask: Task<Void, Never>?
    @State  var autoScrollWorkItem: DispatchWorkItem?
    @State  var lastAutoScrollTarget: AnyHashable?
    @State  var lastAutoScrollAt: Date = .distantPast
    @State  var fallbackTurnStartWorkItemsByConversation: [UUID: DispatchWorkItem] = [:]
    @State  var streamContentVersion: Int = 0
    @State  var activeTurnStateByConversation: [UUID: ChatTurnState] = [:]
    @State  var renderSnapshotByConversation: [UUID: ChatTurnState] = [:]
    @State  var collapsedArtifactsByTurn: [String: Set<String>] = [:]
    @State  var pipelineEventSequenceByConversation: [UUID: Int] = [:]
    @State  var streamingReasoningText: String?
    @State  var streamingReasoningConversationId: UUID?
    @State  var streamingReasoningBlocks: [ReasoningBlock] = []
    @State  var streamingSegments: [MessageSegment] = []
    @State  var streamingSegmentTurnIndex: Int = 0
    @State  var reasoningMessageIdByConversationAndGroup: [UUID: [String: UUID]] = [:]
    /// Last reasoning line from Codex (shown as streaming detail text only, never in thinking box)
    @State  var codexLastReasoningLine: String?
    /// Keep chat rendering linear (one assistant response bubble per turn)
    /// and avoid segmented interleaving that causes jittery layout updates.
     let sequentialStreamingLayoutEnabled = false
     let separateCodexThinkingMessagesEnabled = false
    /// When true, Codex CLI turns are split into separate assistant messages
    /// so the chat reads linearly. Reasoning events are suppressed from the
    /// thinking box and shown only as streaming status text.
     let codexLinearChatEnabled = true
    /// Pending streaming content waiting to be flushed to ChatStore.
    @State  var pendingStreamContent: String?
    @State  var pendingStreamConversationId: UUID?
    @State  var streamThrottleTask: Task<Void, Never>?
    /// Pending plan-streaming content while the flow is rendering in the panel.
    @State  var pendingPlanStreamingContent: String?
    @State  var pendingPlanStreamConversationId: UUID?
    @State  var planStreamThrottleTask: Task<Void, Never>?
    @State  var toolRuntimeSyncTask: Task<Void, Never>?
    @State  var activeRunTaskByConversation: [UUID: Task<Void, Never>] = [:]
    @State  var activeRunTokenByConversation: [UUID: UUID] = [:]
    @State  var activeToolTraceTurnsByConversation: [UUID: ToolTraceTurnContext] = [:]
    @State  var toolTraceNextSequenceByMessage: [UUID: Int] = [:]
    @State  var toolTraceOperationalSeenByMessage: [UUID: Bool] = [:]
    @State  var toolTraceOperationalCountByMessage: [UUID: Int] = [:]
    @State  var policyAckStateByMessage: [UUID: PolicyAckState] = [:]
    /// Assistant message ids that already triggered a policy-ack violation.
    @State  var policyAckFailedMessages: Set<UUID> = []
    /// Events queued while waiting for policy_ack, keyed by assistant message id.
    @State  var policyAckBlockedQueue: [UUID: [(type: String, payload: [String: String], providerId: String, conversationId: UUID?, shouldApplyPipelineArtifacts: Bool)]] = [:]
    /// Per-conversation debug state snapshots (prevents cross-thread contamination).
    @State  var debugStateByConversation: [UUID: DebugStore.SessionSnapshot] = [:]
    /// Debug events received while another conversation is selected.
    @State  var pendingDebugEventsByConversation: [UUID: [NormalizedEvent]] = [:]
    @State  var autoTodoIdByMessage: [UUID: UUID] = [:]
    @State  var autoTodoCompletedOperationsByMessage: [UUID: Int] = [:]
    @State  var didReceiveExplicitTodoByMessage: Set<UUID> = []
    /// Minimum interval between streaming content updates.
    /// Adaptive: starts at ~60fps (0.016s) for fast LLMs, scales to ~30fps if needed.
     let streamThrottleInterval: TimeInterval = 0.020
    /// Minimum interval for plan-streaming updates routed to the Plan Panel.
     let planStreamThrottleInterval: TimeInterval = 0.066
    /// Coalescing flush interval for task activity feed.
     let taskActivityFlushInterval: TimeInterval = 0.1
    /// Backlog threshold used only for lightweight stream diagnostics.
     let taskBacklogDiagnosticThreshold = 40
     let checkpointGitStore = ConversationCheckpointGitStore()
     let cliAccountsStore = CLIAccountsStore.shared
     let cliAccountRouter = CLIAccountRouter.shared

     static let attachmentPastedNotification = Notification.Name("CoderIDE.AttachmentPasted")
    static let planBuildShortcutNotification = Notification.Name("CoderIDE.PlanBuildShortcutPressed")
    static let debugPanelToggleNotification = Notification.Name("CoderIDE.DebugPanelToggle")
    static let threadDeletionRequestedNotification = Notification.Name("CoderIDE.ThreadDeletionRequested")
     static let threadSearchAskAINotification = Notification.Name(
        "CoderIDE.ThreadSearchAskAI")
     static let markdownExportContentType = UTType(filenameExtension: "md") ?? .plainText
     let topInteractiveInset: CGFloat = 30
     let chatColumnMaxWidth: CGFloat = 960
    /// Stable scroll anchor placed at the very bottom of the messages LazyVStack.
    /// Scrolling to this instead of individual message IDs avoids LazyVStack
    /// height-estimation thrashing that causes an infinite scroll-up loop
    /// when the conversation has more than one exchange.
     let chatScrollTopAnchorId = "chat-scroll-top-anchor"
     let chatScrollBottomAnchorId = "chat-scroll-bottom-anchor"

     var activeModeColor: Color { modeColor(for: coderMode) }
     var activeModeGradient: LinearGradient { modeGradient(for: coderMode) }
     var showPlanRequestIndicator: Bool {
        let trimmed = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        return planToggleEnabled || hasStrictPlanCommandPrefix(trimmed)
    }
     var composerRuntimeStartDate: Date? {
        guard isLoadingForCurrentConversation else { return nil }
        return pipelineIntegrationService.snapshot(for: conversationId)?.jobStartTime
            ?? chatStore.taskStartDate(for: conversationId)
            ?? composerTaskStartDate
    }
     var composerFrozenTimerText: String? { composerFrozenTimerState?.text }
     var composerFrozenTimerDismissible: Bool { composerFrozenTimerState?.dismissible == true }
     var shouldShowTaskPanelTodoSection: Bool {
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
     var isPlanPreChoiceState: Bool {
        if planningState != .idle {
            return true
        }
        switch planFlowPhase {
        case .analyzing, .questioning, .generating, .proposalReady:
            return true
        case .idle, .readyToBuild, .building:
            return false
        }
    }
     var hasInlinePlanSession: Bool {
        coderMode == .plan || (coderMode == .agent && planToggleEnabled)
    }
     var hasActivePlanContext: Bool {
        hasActivePlanContext(for: conversationId)
    }
    var planPanelConversationId: UUID? { conversationId }

    var body: some View {
        applyNotificationAndImporterModifiers(
            to: applyRuntimeLifecycleModifiers(
                to: applyProviderSelectionModifiers(to: rootLayout)
            )
        )
    }

}
