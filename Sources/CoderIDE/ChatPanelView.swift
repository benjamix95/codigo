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
    case awaitingChoice(planContent: String, options: [PlanOption])
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
    @EnvironmentObject var flowDiagnosticsStore: FlowDiagnosticsStore
    @EnvironmentObject var changedFilesStore: ChangedFilesStore
    @Binding var selectedConversationId: UUID?
    let effectiveContext: EffectiveContext

    private var conversationId: UUID? { selectedConversationId }
    @State private var coderMode: CoderMode = .agent
    @State private var inputText = ""
    @State private var isInputFocused: Bool = false
    @AppStorage("codex_path") private var codexPath = ""
    @AppStorage("codex_sandbox") private var codexSandbox = ""
    @AppStorage("codex_ask_for_approval") private var codexAskForApproval = "never"
    @AppStorage("codex_model_override") private var codexModelOverride = ""
    @AppStorage("codex_reasoning_effort") private var codexReasoningEffort = "xhigh"
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
    @AppStorage("code_review_analysis_backend") private var codeReviewAnalysisBackend = "codex"
    @AppStorage("code_review_execution_backend") private var codeReviewExecutionBackend = "codex"
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
    @AppStorage("task_panel_enabled") private var taskPanelEnabled = false
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
    @State private var planningState: PlanningState = .idle
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
    @State private var inlinePlanSummaries: [UUID: InlinePlanSummary] = [:]
    @State private var hasJustCompletedTask = false
    @State private var showRateLimitAlert = false
    @State private var rateLimitAlertText = ""
    @State private var isFollowingLive = true
    @State private var newEventsWhileDetached = 0

    @State private var isAnyAgentProviderReady = false
    @State private var userModeOverrideUntilConversationChange = false
    @State private var ignoreNextConversationChangeReset = false
    @StateObject private var flowCoordinator = ConversationFlowCoordinator()
    @StateObject private var turnTimelineStore = TurnTimelineStore()
    @State private var timelineConversationId: UUID?
    @AppStorage("flow_diagnostics_enabled") private var flowDiagnosticsEnabled = false
    private let checkpointGitStore = ConversationCheckpointGitStore()
    private let cliAccountsStore = CLIAccountsStore.shared
    private let cliAccountRouter = CLIAccountRouter.shared

    private static let imagePastedNotification = Notification.Name("CoderIDE.ImagePasted")
    private static let threadSearchAskAINotification = Notification.Name(
        "CoderIDE.ThreadSearchAskAI")
    private let topInteractiveInset: CGFloat = 22
    private let chatColumnMaxWidth: CGFloat = 980

    private var activeModeColor: Color { modeColor(for: coderMode) }
    private var activeModeGradient: LinearGradient { modeGradient(for: coderMode) }

    var body: some View {
        VStack(spacing: 0) {
            // Keep tabs out of macOS titlebar hit-test zone while still using full-height content.
            Color.clear
                .frame(height: topInteractiveInset)
                .allowsHitTesting(false)
            modeTabBar
            separator
            chatHeader
            if changedFilesStore.isVisiblePanel {
                ChangedFilesPanelView(
                    onOpenFile: { path in
                        openChangedFile(path)
                    },
                    onClose: {
                        changedFilesStore.isVisiblePanel = false
                    }
                )
                .environmentObject(changedFilesStore)
                .padding(.horizontal, 12)
                .padding(.top, 8)
                .padding(.bottom, 6)
            }

            if coderMode == .agentSwarm
                && (!swarmProgressStore.steps.isEmpty
                    || !TaskActivityStore.laneStates(from: taskActivityStore.activities).isEmpty)
            {
                SwarmProgressView(
                    store: swarmProgressStore,
                    activities: taskActivityStore.activities,
                    isTaskRunning: chatStore.isLoading
                )
            }

            messagesArea

            // Task control bar — FIXED above composer (not in scroll)
            if chatStore.isLoading || isSummarizing {
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

            composerArea
        }
        .onChange(of: providerRegistry.selectedProviderId) { _, newId in
            syncCoderModeToProvider(newId)
            checkProviderAuth()
        }
        .onChange(of: selectedConversationId) { _, _ in
            if ignoreNextConversationChangeReset {
                ignoreNextConversationChangeReset = false
            } else {
                userModeOverrideUntilConversationChange = false
            }
            syncProviderFromConversation()
        }
        .onAppear {
            syncProviderFromConversation()
            codexModels = CodexModelsCache.loadModels()
            geminiModels = GeminiModelsCache.loadModels()
            syncSwarmProvider()
            syncMultiSwarmReviewProvider()
            syncPlanProvider()
            checkProviderAuth()
            changedFilesStore.refresh(workingDirectory: effectiveContext.primaryPath)
        }
        .onChange(of: effectiveContext.primaryPath) { _, newPath in
            changedFilesStore.refresh(workingDirectory: newPath)
        }
        .onChange(of: selectedConversationId) { _, _ in
            changedFilesStore.refresh(workingDirectory: effectiveContext.primaryPath)
        }
        .onChange(of: chatStore.isLoading) { oldValue, newValue in
            if oldValue && !newValue {
                hasJustCompletedTask = true
                changedFilesStore.refresh(workingDirectory: effectiveContext.primaryPath)
                isFollowingLive = true
                newEventsWhileDetached = 0
            }
        }
        .onChange(of: swarmOrchestrator) { _, _ in syncSwarmProvider() }
        .onChange(of: swarmWorkerBackend) { _, _ in syncSwarmProvider() }
        .onChange(of: swarmAutoPostCodePipeline) { _, _ in syncSwarmProvider() }
        .onChange(of: swarmMaxPostCodeRetries) { _, _ in syncSwarmProvider() }
        .onChange(of: globalYolo) { _, _ in
            syncCodexProvider()
            syncMultiSwarmReviewProvider()
            syncPlanProvider()
        }
        .onChange(of: codeReviewPartitions) { _, _ in syncMultiSwarmReviewProvider() }
        .onChange(of: codeReviewAnalysisOnly) { _, _ in syncMultiSwarmReviewProvider() }
        .onChange(of: codeReviewAnalysisBackend) { _, _ in syncMultiSwarmReviewProvider() }
        .onChange(of: codeReviewExecutionBackend) { _, _ in syncMultiSwarmReviewProvider() }
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
            if isShiftTab(event), !isInputFocused {
                planToggleEnabled.toggle()
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
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let isBacktabChar = event.charactersIgnoringModifiers == "\u{19}"
        let isTabKeycode = event.keyCode == 48
        return (isBacktabChar || isTabKeycode)
            && flags.contains(.shift)
            && !flags.contains(.command)
            && !flags.contains(.option)
            && !flags.contains(.control)
    }

    private func removePasteMonitor() {
        if let m = pasteMonitor {
            NSEvent.removeMonitor(m)
            pasteMonitor = nil
        }
    }

    private var separator: some View {
        Rectangle()
            .fill(DesignSystem.Colors.border)
            .frame(height: 0.5)
    }

    private var chatHeader: some View {
        HStack(spacing: 8) {
            Text(chatStore.conversation(for: conversationId)?.title ?? "Nuova conversazione")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
            Spacer()
            Button {
                rewindConversation()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.uturn.backward")
                        .font(.system(size: 12, weight: .semibold))
                    if isRewinding {
                        ProgressView()
                            .controlSize(.small)
                    }
                }
                .foregroundStyle(
                    (chatStore.canRewind(conversationId: conversationId) && !chatStore.isLoading
                        && !isRewinding) ? .primary : .tertiary)
            }
            .buttonStyle(.plain)
            .disabled(
                !chatStore.canRewind(conversationId: conversationId) || chatStore.isLoading
                    || isRewinding
            )
            .help("Torna al checkpoint precedente (ripristina chat e file)")
            .accessibilityLabel("Rewind checkpoint chat")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: - Mode Tab Bar
    private var modeTabBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 3) {
                ForEach(CoderMode.allCases, id: \.self) { mode in
                    modeTabButton(for: mode)
                }
                changedFilesButton
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
    }

    private var changedFilesButton: some View {
        Button {
            changedFilesStore.isVisiblePanel = true
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "doc.badge.gearshape")
                    .font(.system(size: 10, weight: .semibold))
                Text("Changed files")
                    .font(.system(size: 11.5, weight: .medium))
                Text("\(changedFilesStore.files.count)")
                    .font(.system(size: 10, weight: .semibold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.primary.opacity(0.08), in: Capsule())
            }
            .foregroundStyle(changedFilesStore.gitRoot == nil ? .tertiary : .secondary)
            .padding(.horizontal, 11)
            .padding(.vertical, 5.5)
            .background(
                Capsule()
                    .fill(DesignSystem.Colors.backgroundSecondary.opacity(0.45))
            )
            .overlay(
                Capsule()
                    .strokeBorder(DesignSystem.Colors.border, lineWidth: 0.6)
            )
        }
        .buttonStyle(.plain)
        .disabled(changedFilesStore.gitRoot == nil)
        .help(
            changedFilesStore.gitRoot == nil
                ? "Nessuna repository Git nel contesto attivo"
                : "Apri elenco completo file modificati")
    }

    @ViewBuilder
    private func modeTabButton(for mode: CoderMode) -> some View {
        let isSelected = coderMode == mode
        let isPlanMode = mode == .plan
        let isPlanActive = isPlanMode && planToggleEnabled
        let color = modeColor(for: mode)
        let gradient = modeGradient(for: mode)
        Button {
            withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
                if isPlanMode {
                    planToggleEnabled.toggle()
                    if planToggleEnabled {
                        self.selectMode(.plan)
                    } else if coderMode == .plan {
                        self.selectMode(.agent)
                    }
                    return
                }
                self.selectMode(mode)
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: modeIcon(for: mode))
                    .font(.system(size: 10, weight: .semibold))
                Text(mode.rawValue)
                    .font(.system(size: 11.5, weight: isSelected ? .semibold : .medium))
                if isPlanMode && isPlanTabHovered {
                    Text("Shift+Tab")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            Color(nsColor: .controlBackgroundColor).opacity(0.7), in: Capsule())
                }
            }
            .foregroundStyle((isSelected || isPlanActive) ? .white : .secondary)
            .padding(.horizontal, 11)
            .padding(.vertical, 5.5)
            .background {
                if isSelected || isPlanActive {
                    Capsule()
                        .fill(
                            isPlanMode && isPlanActive && !isSelected
                                ? DesignSystem.Colors.planGradient : gradient
                        )
                        .shadow(color: color.opacity(0.35), radius: 8, y: 2)
                }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            if isPlanMode {
                isPlanTabHovered = hovering
            }
        }
        .help(isPlanMode ? "Toggle Plan (Shift+Tab)" : "")
    }

    @ViewBuilder
    private func assistantTimelineView(
        fallbackContent: String,
        streamingStatusText: String,
        streamingReasoningText: String?
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(turnTimelineStore.segments) { segment in
                switch segment {
                case .assistantText(let text, _):
                    AssistantTextChunkView(
                        text: text,
                        modeColor: activeModeColor,
                        context: effectiveContext.context,
                        onFileClicked: { openFilesStore.openFile($0) }
                    )
                case .thinking(let activity):
                    ThinkingCardView(activity: activity, modeColor: activeModeColor)
                case .tool(let activity):
                    ToolExecutionCardView(activity: activity, modeColor: activeModeColor)
                case .todoSnapshot:
                    TodoTimelineCardView(
                        todoStore: todoStore,
                        modeColor: activeModeColor,
                        onOpenFile: { openFilesStore.openFile($0) }
                    )
                }
            }
            if let pending = turnTimelineStore.pendingStreamingChunk {
                AssistantTextChunkView(
                    text: pending,
                    modeColor: activeModeColor,
                    context: effectiveContext.context,
                    onFileClicked: { openFilesStore.openFile($0) }
                )
            } else if turnTimelineStore.segments.isEmpty {
                let fallback = fallbackContent.trimmingCharacters(in: .whitespacesAndNewlines)
                if !fallback.isEmpty {
                    AssistantTextChunkView(
                        text: fallback,
                        modeColor: activeModeColor,
                        context: effectiveContext.context,
                        onFileClicked: { openFilesStore.openFile($0) }
                    )
                } else {
                    timelineStreamingPlaceholder(statusText: streamingStatusText)
                }
            }
            if let reasoning = streamingReasoningText, !reasoning.isEmpty {
                timelineReasoningStream(reasoning: reasoning)
            }
        }
    }

    private func timelineReasoningStream(reasoning: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "brain")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(activeModeColor.opacity(0.8))
                Text("Ragionamento")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            ScrollView(.vertical, showsIndicators: true) {
                Text(reasoning)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
            .frame(maxHeight: 200)
            .padding(8)
            .background(
                Color.primary.opacity(0.06),
                in: RoundedRectangle(cornerRadius: 8)
            )
        }
        .frame(maxWidth: 760, alignment: .leading)
    }

    private func timelineStreamingPlaceholder(statusText: String) -> some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: "brain")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(activeModeColor.opacity(0.8))
            StreamingDots(color: activeModeColor)
            Text(statusText)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .frame(maxWidth: 760, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.5))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(activeModeColor.opacity(0.25), lineWidth: 0.6)
        )
    }

    // MARK: - Messages Area
    private var messagesArea: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 24) {
                    if let conv = chatStore.conversation(for: conversationId) {
                        let messages = conv.messages
                        let lastMsg = messages.last
                        let taskDone = !chatStore.isLoading
                        let hasTodoItems = !todoStore.todos.isEmpty
                        let showPanelBeforeLast =
                            coderMode == .agent
                            && taskDone
                            && lastMsg?.role == .assistant
                            && taskPanelEnabled
                            && (!taskActivityStore.activities.isEmpty || hasTodoItems)

                        ForEach(Array(messages.enumerated()), id: \.element.id) { item in
                            let index = item.offset
                            let message = item.element
                            let isLast = message.id == lastMsg?.id
                            let isLastAssistant = lastMsg?.role == .assistant && isLast
                            let useTimeline =
                                isLastAssistant
                                && chatStore.isLoading
                                && coderMode == .agent
                                && conv.id == timelineConversationId
                            let userMessageCheckpoint = message.role == .user
                                ? chatStore.checkpoint(forMessageIndex: index, conversationId: conv.id)
                                : nil
                            let canRestoreFromMessage = userMessageCheckpoint != nil

                            if isLast && showPanelBeforeLast {
                                TaskActivityPanel(
                                    chatStore: chatStore,
                                    taskActivityStore: taskActivityStore,
                                    todoStore: todoStore,
                                    coderMode: coderMode,
                                    onOpenFile: { openFilesStore.openFile($0) },
                                    effectivePrimaryPath: effectiveContext.primaryPath
                                )
                                .id("chat-task-status-pre")
                            }

                            HStack(alignment: .top, spacing: 0) {
                                if message.role == .user { Spacer(minLength: 0) }
                                if useTimeline {
                                    assistantTimelineView(
                                        fallbackContent: message.content,
                                        streamingStatusText: streamingStatusText(for: message),
                                        streamingReasoningText: streamingReasoningText(for: message)
                                    )
                                } else {
                                    MessageRow(
                                        message: message,
                                        context: effectiveContext.context,
                                        modeColor: activeModeColor,
                                        isActuallyLoading: chatStore.isLoading,
                                        streamingStatusText: streamingStatusText(for: message),
                                        streamingDetailText: streamingDetailText(for: message),
                                        streamingReasoningText: streamingReasoningText(for: message),
                                        onFileClicked: { openFilesStore.openFile($0) },
                                        onRestoreCheckpoint: message.role == .user
                                            ? { rewindToMessage(at: index, conversationId: conv.id) }
                                            : nil,
                                        canRestoreCheckpoint: canRestoreFromMessage
                                    )
                                }
                                if message.role == .assistant { Spacer(minLength: 0) }
                            }
                            .id(message.id)
                        }
                        if coderMode == .agent,
                            planToggleEnabled,
                            let cid = conversationId,
                            let summary = inlinePlanSummaries[cid]
                        {
                            PlanSummaryCardView(
                                title: summary.title,
                                summaryMarkdown: summary.body,
                                isCollapsed: isPlanSummaryCollapsed,
                                onToggleCollapse: { isPlanSummaryCollapsed.toggle() },
                                onExpandPlan: {
                                    selectMode(.plan)
                                }
                            )
                            .padding(.horizontal, 16)
                            .padding(.bottom, 8)
                            .id("plan-summary-card")
                        }
                        if let board = chatStore.planBoard(for: conversationId) {
                            PlanBoardView(
                                board: board,
                                onSelectOption: { executeWithPlanChoice($0.fullText) }
                            )
                            .padding(.horizontal, 16)
                            .padding(.bottom, 8)
                            .id("plan-board")
                        }
                        if case .awaitingChoice(_, let options) = planningState {
                            PlanOptionsView(
                                options: options,
                                planColor: DesignSystem.Colors.planColor,
                                onSelectOption: { executeWithPlanChoice($0.fullText) },
                                onCustomResponse: { executeWithPlanChoice($0) }
                            )
                            .id("plan-options")
                        }
                        // Activity panel (expandable sections in scroll)
                        // Nascondi quando la timeline inline è attiva (agent mode, in streaming)
                        let timelineActive =
                            coderMode == .agent
                            && chatStore.isLoading
                            && conv.id == timelineConversationId
                        if !timelineActive
                            && !showPanelBeforeLast
                            && (chatStore.isLoading
                                || ((!taskActivityStore.activities.isEmpty || !todoStore.todos.isEmpty)
                                    && taskPanelEnabled))
                        {
                            TaskActivityPanel(
                                chatStore: chatStore,
                                taskActivityStore: taskActivityStore,
                                todoStore: todoStore,
                                coderMode: coderMode,
                                onOpenFile: { openFilesStore.openFile($0) },
                                effectivePrimaryPath: effectiveContext.primaryPath
                            )
                            .id("chat-task-status")
                        }
                        if flowDiagnosticsEnabled {
                            flowDiagnosticsCard
                                .padding(.horizontal, 16)
                                .padding(.bottom, 8)
                        }
                        // Changed files card with chevron
                        if hasJustCompletedTask, !changedFilesStore.files.isEmpty {
                            ChangedFilesSummaryCard(
                                changedFilesStore: changedFilesStore,
                                onOpenFile: { openChangedFile($0) },
                                onUndoAll: { changedFilesStore.undoAll() }
                            )
                            .padding(.horizontal, 16)
                            .padding(.bottom, 8)
                            .id("changed-files-card")
                        }
                    }
                }
                .padding(.top, 8).padding(.bottom, 16)
                .frame(maxWidth: chatColumnMaxWidth)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.horizontal, 16)
            }
            .onChange(of: chatStore.conversation(for: conversationId)?.messages.last?.content ?? "")
            { _, _ in
                if let last = chatStore.conversation(for: conversationId)?.messages.last,
                    isFollowingLive
                {
                    withAnimation(.easeOut(duration: 0.2)) {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
            .onChange(of: planningState) { _, new in
                if case .awaitingChoice = new {
                    withAnimation(.easeOut(duration: 0.2)) {
                        proxy.scrollTo("plan-options", anchor: .bottom)
                    }
                }
            }
            .onChange(of: chatStore.isLoading) { _, loading in
                if loading {
                    let timelineActive =
                        coderMode == .agent
                        && chatStore.isLoading
                        && conversationId == timelineConversationId
                    withAnimation(.easeOut(duration: 0.2)) {
                        if timelineActive, let last = chatStore.conversation(for: conversationId)?.messages.last {
                            proxy.scrollTo(last.id, anchor: .bottom)
                        } else {
                            proxy.scrollTo("chat-task-status", anchor: .bottom)
                        }
                    }
                } else {
                    timelineConversationId = nil
                }
            }
            .onChange(of: turnTimelineStore.segments.count) { _, _ in
                if chatStore.isLoading, coderMode == .agent, isFollowingLive,
                    let last = chatStore.conversation(for: conversationId)?.messages.last
                {
                    withAnimation(.easeOut(duration: 0.2)) {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
            .onChange(of: taskActivityStore.activities.count) { _, _ in
                if chatStore.isLoading {
                    if isFollowingLive {
                        let timelineActive =
                            coderMode == .agent
                            && chatStore.isLoading
                            && conversationId == timelineConversationId
                        withAnimation(.easeOut(duration: 0.2)) {
                            if timelineActive,
                                let last = chatStore.conversation(for: conversationId)?.messages.last
                            {
                                proxy.scrollTo(last.id, anchor: .bottom)
                            } else {
                                proxy.scrollTo("chat-task-status", anchor: .bottom)
                            }
                        }
                    } else {
                        newEventsWhileDetached += 1
                    }
                }
            }
            .simultaneousGesture(
                DragGesture(minimumDistance: 3).onChanged { _ in
                    if chatStore.isLoading {
                        isFollowingLive = false
                    }
                }
            )
            .overlay(alignment: .bottomTrailing) {
                if !isFollowingLive && chatStore.isLoading {
                    Button {
                        isFollowingLive = true
                        newEventsWhileDetached = 0
                        if let last = chatStore.conversation(for: conversationId)?.messages.last {
                            withAnimation(.easeOut(duration: 0.2)) {
                                proxy.scrollTo(last.id, anchor: .bottom)
                            }
                        } else {
                            withAnimation(.easeOut(duration: 0.2)) {
                                proxy.scrollTo("chat-task-status", anchor: .bottom)
                            }
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

    private func interruptTask() {
        let scope: ExecutionScope = {
            switch coderMode {
            case .agentSwarm: return .swarm
            case .codeReviewMultiSwarm: return .review
            case .plan: return .plan
            default: return .agent
            }
        }()
        executionController.terminate(scope: scope)
        flowCoordinator.interrupt()
        if let cid = (timelineConversationId ?? conversationId) {
            let cur =
                chatStore.conversation(for: cid)?.messages.last(where: {
                    $0.role == .assistant
                })?.content ?? ""
            if timelineConversationId == cid {
                turnTimelineStore.finalize(lastFullText: cur)
            }
            chatStore.updateLastAssistantMessage(
                content: cur.isEmpty
                    ? "[Interrotto dall'utente]"
                    : cur + "\n\n[Interrotto dall'utente]", in: cid)
            chatStore.setLastAssistantStreaming(false, in: cid)
        }
        chatStore.endTask()
    }

    @MainActor
    private func recordTaskActivity(type: String, payload: [String: String], providerId: String) {
        let envelope = flowCoordinator.normalizeRawEvent(
            providerId: providerId, type: type, payload: payload)
        taskActivityStore.addEnvelope(envelope)

        if let cid = timelineConversationId {
            let lastContent = chatStore.conversation(for: cid)?
                .messages.last(where: { $0.role == .assistant })?.content ?? ""
            turnTimelineStore.commitText(from: lastContent)
        }
        if flowDiagnosticsEnabled {
            flowDiagnosticsStore.push(
                providerId: providerId,
                eventType: "\(envelope.kind.rawValue):\(type)",
                summary: payload["title"] ?? payload["detail"] ?? type
            )
        }
        for event in envelope.events {
            switch event {
            case .taskActivity(let activity):
                // Usage è metadata (token), non va in timeline—creerebbe un card vuoto
                if timelineConversationId != nil, activity.type != "usage" {
                    turnTimelineStore.appendActivity(activity)
                }
                let shouldAutoShow =
                    activity.type == "command_execution" || activity.type == "bash"
                    || activity.type == "web_search_started"
                    || activity.type == "web_search_completed"
                    || activity.type == "web_search_failed"
                if shouldAutoShow {
                    taskPanelEnabled = true
                }
                if activity.type == "read_batch_started" || activity.type == "read_batch_completed"
                    || activity.type == "web_search_started"
                    || activity.type == "web_search_completed"
                    || activity.type == "web_search_failed" || activity.type == "command_execution"
                    || activity.type == "bash" || activity.type == "mcp_tool_call"
                    || activity.type == "reasoning"
                {
                    taskActivityStore.appendOrMergeBatchEvent(activity)
                } else {
                    taskActivityStore.addActivity(activity)
                }
            case .instantGrep(let grep):
                taskPanelEnabled = true
                taskActivityStore.addInstantGrep(grep)
            case .todoWrite(let todo):
                taskPanelEnabled = true
                if timelineConversationId != nil {
                    turnTimelineStore.appendTodoSnapshot()
                }
                todoStore.upsertFromAgent(
                    id: todo.id,
                    title: todo.title,
                    status: todo.status,
                    priority: todo.priority,
                    notes: todo.notes,
                    linkedFiles: todo.files
                )
            case .todoRead:
                taskPanelEnabled = true
                break
            case .planStepUpdate(let stepId, let status):
                let targetId = timelineConversationId ?? conversationId
                chatStore.updatePlanStepStatus(stepId: stepId, status: status, in: targetId)
            }
        }
    }

    @ViewBuilder
    private var flowDiagnosticsCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Flow Diagnostics")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(flowCoordinator.state.rawValue)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            Text("Provider selezionato: \(providerRegistry.selectedProviderId ?? "-")")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
            if let err = flowDiagnosticsStore.lastError, !err.isEmpty {
                Text("Errore: \(err)")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.red)
            }
            ForEach(flowDiagnosticsStore.entries.prefix(5)) { entry in
                Text("[\(entry.providerId)] \(entry.eventType) • \(entry.summary)")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(8)
        .background(
            Color(nsColor: .controlBackgroundColor).opacity(0.45),
            in: RoundedRectangle(cornerRadius: 8))
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
                isLoading: chatStore.isLoading,
                planningState: planningState,
                activeModeColor: activeModeColor,
                activeModeGradient: activeModeGradient,
                inputHint: inputHint,
                providerNotReadyMessage: providerNotReadyMessage,
                onSend: sendMessage
            )
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
                codexModels: codexModels,
                geminiModels: geminiModels,
                effectiveModeProviderLabel: effectiveModeProviderLabel,
                onSyncCodexProvider: syncCodexProvider,
                onSyncGeminiProvider: syncGeminiProvider,
                onSyncSwarmProvider: syncSwarmProvider,
                onSyncPlanProvider: syncPlanProvider,
                onDelegateToAgent: delegateToAgent,
                attachedImageURLs: attachedImageURLs
            )
            .padding(.horizontal, 12)
            .padding(.bottom, 4)
            .alert("Rate Limit Raggiunto", isPresented: $showRateLimitAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(rateLimitAlertText)
            }
            UsageFooterView(
                selectedConversationId: $selectedConversationId,
                effectiveContext: effectiveContext,
                planModeBackend: planModeBackend,
                swarmWorkerBackend: swarmWorkerBackend,
                openaiModel: openaiModel,
                claudeModel: claudeModel
            )
        }
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
        case "agent-swarm":
            return "Agent Swarm non configurato. Verifica provider nelle Impostazioni."
        case "plan-mode":
            return "Backend Plan Mode non disponibile. Verifica Codex o Claude nelle Impostazioni."
        case "multi-swarm-review":
            return "Code Review non configurato. Verifica Codex nelle Impostazioni."
        case "openrouter-api": return "API Key OpenRouter mancante. Configurala nelle Impostazioni."
        case "minimax-api": return "API Key MiniMax mancante. Configurala nelle Impostazioni."
        default:
            return "Provider \"\(id)\" non autenticato. Vai nelle Impostazioni per configurare."
        }
    }

    /// Provider effettivo usato dalla modalità corrente, mostrato come badge sotto al provider.
    private var effectiveModeProviderLabel: String? {
        switch providerRegistry.selectedProviderId {
        case "plan-mode":
            return "Plan → " + (planModeBackend == "claude" ? "Claude CLI" : "Codex CLI")
        case "agent-swarm":
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
        case "multi-swarm-review":
            let execLabel: String = {
                switch codeReviewExecutionBackend {
                case "claude": return "Claude CLI"
                case "anthropic-api": return "Anthropic API"
                case "openai-api": return "OpenAI API"
                case "google-api": return "Google API"
                case "openrouter-api": return "OpenRouter API"
                default: return "Codex CLI"
                }
            }()
            return "Review → esecuzione: \(execLabel)"
        default:
            if coderMode == .ide {
                guard let selected = providerRegistry.selectedProviderId,
                    ProviderSupport.isIDEProvider(id: selected),
                    let provider = providerRegistry.provider(for: selected)
                else {
                    return "IDE → Auto"
                }
                return "IDE → \(provider.displayName)"
            }
            if coderMode == .agent || coderMode == .agentSwarm || coderMode == .codeReviewMultiSwarm
                || coderMode == .plan
            {
                if let selected = providerRegistry.selectedProviderId,
                   let provider = providerRegistry.provider(for: selected),
                   ProviderSupport.isAgentCompatibleProvider(id: selected)
                {
                    return provider.displayName
                }
            }
            return nil
        }
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
        case .agentSwarm: providerRegistry.selectedProviderId = "agent-swarm"
        case .codeReviewMultiSwarm: providerRegistry.selectedProviderId = "multi-swarm-review"
        case .plan:
            providerRegistry.selectedProviderId = "plan-mode"
            planningState = .idle
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
                providerRegistry.selectedProviderId = preferred
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
        let provider = providerRegistry.selectedProvider
        let codexProvider = providerRegistry.provider(for: "codex-cli")
        let claudeProvider = providerRegistry.provider(for: "claude-cli")
        let geminiProvider = providerRegistry.provider(for: "gemini-cli")
        Task.detached {
            let ready = provider?.isAuthenticated() ?? false
            let anyAgentReady =
                (codexProvider?.isAuthenticated() ?? false)
                || (claudeProvider?.isAuthenticated() ?? false)
                || (geminiProvider?.isAuthenticated() ?? false)
            await MainActor.run {
                isProviderReady = ready
                isAnyAgentProviderReady = anyAgentReady
            }
        }
    }

    private func syncCodexProvider() {
        let p = ProviderFactory.codexProvider(
            config: providerFactoryConfig(), executionController: executionController)
        providerRegistry.unregister(id: "codex-cli")
        providerRegistry.register(p)
        syncSwarmProvider()
        syncPlanProvider()
        checkProviderAuth()
        persistCodexConfigToToml()
    }

    private func syncGeminiProvider() {
        let p = ProviderFactory.geminiProvider(
            config: providerFactoryConfig(), executionController: executionController)
        providerRegistry.unregister(id: "gemini-cli")
        providerRegistry.register(p)
        checkProviderAuth()
    }

    private func persistCodexConfigToToml() {
        var cfg = CodexConfigLoader.load()
        cfg.sandboxMode = codexSandbox.isEmpty ? nil : codexSandbox
        cfg.model = codexModelOverride.isEmpty ? nil : codexModelOverride
        cfg.modelReasoningEffort = codexReasoningEffort.isEmpty ? nil : codexReasoningEffort
        CodexConfigLoader.save(cfg)
    }
    private func syncSwarmProvider() {
        providerRegistry.unregister(id: "agent-swarm")
        if let swarm = ProviderFactory.swarmProvider(
            config: providerFactoryConfig(),
            executionController: executionController)
        {
            providerRegistry.register(swarm)
        }
        checkProviderAuth()
    }
    private func syncMultiSwarmReviewProvider() {
        providerRegistry.unregister(id: "multi-swarm-review")
        guard let codex = providerRegistry.provider(for: "codex-cli") as? CodexCLIProvider else {
            checkProviderAuth()
            return
        }
        let claude = providerRegistry.provider(for: "claude-cli") as? ClaudeCLIProvider
        providerRegistry.register(
            ProviderFactory.codeReviewProvider(
                config: providerFactoryConfig(), codex: codex, claude: claude))
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
        case .agentSwarm: providerRegistry.selectedProviderId = "agent-swarm"
        case .codeReviewMultiSwarm: providerRegistry.selectedProviderId = "multi-swarm-review"
        case .plan: providerRegistry.selectedProviderId = "plan-mode"
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
            return
        }
        if ProviderSupport.isIDEProvider(id: id) {
            coderMode = .ide
            planningState = .idle
            return
        }
        switch id {
        case "agent-swarm":
            coderMode = .agentSwarm
            planningState = .idle
        case "multi-swarm-review":
            coderMode = .codeReviewMultiSwarm
            planningState = .idle
        case "plan-mode": coderMode = .plan
        case "codex-cli", "claude-cli", "gemini-cli":
            coderMode = .agent
            planningState = .idle
        default: break
        }
    }
    private func syncPlanProvider() {
        let codex = providerRegistry.provider(for: "codex-cli") as? CodexCLIProvider
        let claude = providerRegistry.provider(for: "claude-cli") as? ClaudeCLIProvider
        providerRegistry.unregister(id: "plan-mode")
        guard codex != nil || claude != nil else {
            checkProviderAuth()
            return
        }
        providerRegistry.register(
            ProviderFactory.planProvider(
                config: providerFactoryConfig(), codex: codex, claude: claude,
                executionController: executionController))
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
    private func executeWithPlanChoice(_ choice: String) {
        let planConversationId = conversationId
        let planContent: String
        if case .awaitingChoice(let fullPlan, _) = planningState {
            planContent = fullPlan
        } else if let board = chatStore.planBoard(for: planConversationId) {
            let optionsBlock = board.options
                .sorted(by: { $0.id < $1.id })
                .map { "Opzione \($0.id): \($0.title)\n\($0.fullText)" }
                .joined(separator: "\n\n")
            planContent = """
            # \(board.goal)

            \(optionsBlock)
            """
        } else {
            appendTechnicalErrorMessage(
                "[Plan] Nessun piano disponibile da eseguire. Rigenera il piano e riprova.",
                in: conversationId
            )
            return
        }
        let useClaude = planModeBackend == "claude"
        let provider: any LLMProvider
        if useClaude {
            guard let c = providerRegistry.provider(for: "claude-cli") as? ClaudeCLIProvider else {
                appendTechnicalErrorMessage(
                    "[Plan] Backend Claude non disponibile. Verifica impostazioni/autenticazione Claude CLI.",
                    in: conversationId
                )
                flowDiagnosticsStore.setError("Plan backend Claude non disponibile")
                return
            }
            provider = c
        } else {
            guard let c = providerRegistry.provider(for: "codex-cli") as? CodexCLIProvider else {
                appendTechnicalErrorMessage(
                    "[Plan] Backend Codex non disponibile. Verifica impostazioni/autenticazione Codex CLI.",
                    in: conversationId
                )
                flowDiagnosticsStore.setError("Plan backend Codex non disponibile")
                return
            }
            provider = c
        }
        guard provider.isAuthenticated() else {
            appendTechnicalErrorMessage(
                "[Plan] Il backend selezionato non è autenticato. Esegui login e riprova.",
                in: conversationId
            )
            flowDiagnosticsStore.setError("Plan backend non autenticato")
            return
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
            flowDiagnosticsStore.setError(error.localizedDescription)
            return
        }

        planningState = .idle
        chatStore.choosePlanPath(choice, for: planConversationId)
        chatStore.updatePlanStepStatus(stepId: "1", status: .running, in: planConversationId)
        selectedConversationId = agentConvId
        providerRegistry.selectedProviderId =
            planModeBackend == "claude" ? "claude-cli" : "codex-cli"
        coderMode = .agent

        chatStore.addMessage(
            ChatMessage(role: .user, content: "Procedi con: \(choice)", isStreaming: false),
            to: agentConvId)
        chatStore.addMessage(
            ChatMessage(role: .assistant, content: "", isStreaming: true), to: agentConvId)
        chatStore.beginTask()
        taskActivityStore.clear()
        // Keep manual todos stable; reset only agent workflow todos for this new execution.
        todoStore.clearAgentTodos()
        turnTimelineStore.clear()
        timelineConversationId = agentConvId

        let planExecutionWorkflow = """
            **Workflow Todo (obbligatorio):** All'inizio di ogni task:
            1. Includi subito \(CoderIDEMarkers.showTaskPanel) per mostrare il pannello attività.
            2. PRIMA di leggere file, modificare o eseguire comandi, crea la lista di todo con marker:
            \(CoderIDEMarkers.todoWritePrefix)title=TASK|status=pending|priority=medium|notes=...|files=file1.swift]
            3. Durante l'esecuzione aggiorna lo status a in_progress e poi done.
            4. Prima di concludere verifica che tutti i todo siano done.
            """

        let prompt =
            "\(planExecutionWorkflow)\n\nL'utente ha scelto il seguente approccio dal piano precedentemente proposto. Implementalo.\n\nPiano di riferimento:\n\(planContent)\n\nScelta dell'utente:\n\(choice)"

        Task {
            do {
                _ = try await flowCoordinator.runStream(
                    provider: provider,
                    prompt: prompt,
                    context: ctx,
                    imageURLs: nil,
                    onText: { content in
                        chatStore.updateLastAssistantMessage(content: content, in: agentConvId)
                        turnTimelineStore.updateLastKnownText(content)
                    },
                    onRaw: { t, p, pid in
                        if t == "coderide_show_task_panel" { taskPanelEnabled = true }
                        recordTaskActivity(type: t, payload: p, providerId: pid)
                    },
                    onError: { content in
                        chatStore.updateLastAssistantMessage(content: content, in: agentConvId)
                    }
                )
                chatStore.setLastAssistantStreaming(false, in: agentConvId)
                chatStore.updatePlanStepStatus(stepId: "1", status: .done, in: planConversationId)
            } catch {
                let lastContent = chatStore.conversation(for: agentConvId)?
                    .messages.last(where: { $0.role == .assistant })?.content ?? ""
                turnTimelineStore.finalize(lastFullText: lastContent)
                chatStore.updatePlanStepStatus(stepId: "1", status: .failed, in: planConversationId)
                chatStore.updateLastAssistantMessage(
                    content: "[Errore: \(error.localizedDescription)]", in: agentConvId)
                chatStore.setLastAssistantStreaming(false, in: agentConvId)
                await MainActor.run {
                    flowDiagnosticsStore.setError(error.localizedDescription)
                    flowCoordinator.fail()
                }
            }
            chatStore.endTask()
        }
    }

    // MARK: - Send Message
    // MARK: - Send Message (orchestrator)

    private func sendMessage() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty || !attachedImageURLs.isEmpty else { return }
        guard let targetConversationId = conversationId else {
            appendTechnicalErrorMessage(
                "[Errore] Nessuna conversazione selezionata. Crea o seleziona un thread e riprova.",
                in: nil
            )
            flowDiagnosticsStore.setError("Nessuna conversazione selezionata")
            return
        }
        guard let selectedProvider = providerRegistry.selectedProvider else {
            appendTechnicalErrorMessage(
                "[Errore] Nessun provider selezionato. Configura un provider nelle Impostazioni.",
                in: targetConversationId
            )
            flowDiagnosticsStore.setError("Nessun provider selezionato")
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

        let shouldRunPlanInline = coderMode == .agent && planToggleEnabled

        // 1. Resolve the runtime provider (plan-mode, multi-account, or default)
        guard
            let runtimeProvider = resolveRuntimeProvider(
                selectedProvider: selectedProvider, shouldRunPlanInline: shouldRunPlanInline
            )
        else {
            appendTechnicalErrorMessage(
                "[Errore] Impossibile risolvere il provider runtime per questa modalità.",
                in: targetConversationId
            )
            flowDiagnosticsStore.setError("Provider runtime non risolto")
            return
        }

        guard runtimeProvider.isAuthenticated() else {
            let providerName = runtimeProvider.displayName
            appendTechnicalErrorMessage(
                "[Errore] Provider \(providerName) non autenticato. Esegui login e riprova.",
                in: targetConversationId
            )
            flowDiagnosticsStore.setError("Provider non autenticato: \(runtimeProvider.id)")
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
            flowDiagnosticsStore.setError(error.localizedDescription)
            return
        }

        // 3. Prepare messages in chat store
        let imagePathsToStore = attachedImageURLs.map { $0.path }
        inputText = ""
        let contentToStore =
            text.isEmpty ? (attachedImageURLs.isEmpty ? "" : "[Immagine allegata]") : text
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
        chatStore.beginTask()
        taskActivityStore.clear()
        // Preserve manual todos across turns; reset only agent-emitted workflow todos.
        todoStore.clearAgentTodos()
        turnTimelineStore.clear()
        timelineConversationId = targetConversationId
        if providerRegistry.selectedProviderId == "agent-swarm" { swarmProgressStore.clear() }

        let imageURLsToSend = attachedImageURLs.isEmpty ? nil : attachedImageURLs
        attachedImageURLs = []

        // 4. Build the prompt with mode-specific instructions
        let prompt = buildPrompt(userText: text)

        // 5. Execute async stream
        Task {
            await MainActor.run { flowDiagnosticsStore.selectedProviderId = runtimeProvider.id }
            do {
                let streamResult = try await flowCoordinator.runStream(
                    provider: runtimeProvider,
                    prompt: prompt,
                    context: ctx,
                    imageURLs: imageURLsToSend,
                    onText: { content in
                        chatStore.updateLastAssistantMessage(content: content, in: targetConversationId)
                        if timelineConversationId == targetConversationId {
                            turnTimelineStore.updateLastKnownText(content)
                        }
                    },
                    onRaw: { t, p, pid in
                        handleRawStreamEvent(type: t, payload: p, providerId: pid)
                    },
                    onError: { content in
                        chatStore.updateLastAssistantMessage(content: content, in: targetConversationId)
                    }
                )

                // 6. Handle stream completion (plan options, swarm delegation)
                await handleStreamResult(
                    conversationId: targetConversationId,
                    streamResult, shouldRunPlanInline: shouldRunPlanInline,
                    ctx: ctx, imageURLsToSend: imageURLsToSend, prompt: prompt
                )
            } catch {
                let lastContent = chatStore.conversation(for: targetConversationId)?
                    .messages.last(where: { $0.role == .assistant })?.content ?? ""
                if timelineConversationId == targetConversationId {
                    turnTimelineStore.finalize(lastFullText: lastContent)
                }
                chatStore.updateLastAssistantMessage(
                    content: "[Errore: \(error.localizedDescription)]", in: targetConversationId)
                chatStore.setLastAssistantStreaming(false, in: targetConversationId)
                await MainActor.run {
                    flowDiagnosticsStore.setError(error.localizedDescription)
                    flowCoordinator.fail()
                }
            }
            chatStore.endTask()
        }
    }

    // MARK: - Resolve Runtime Provider

    private func resolveRuntimeProvider(
        selectedProvider: any LLMProvider, shouldRunPlanInline: Bool
    ) -> (any LLMProvider)? {
        if shouldRunPlanInline,
            let p = providerRegistry.provider(for: "plan-mode"),
            p.isAuthenticated()
        {
            return p
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
                flowDiagnosticsStore.setError("Multi-account \(kind.rawValue): \(reason)")
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

    private func buildPrompt(userText: String) -> String {
        var prompt =
            userText.isEmpty
            ? "[L'utente ha allegato un'immagine. Analizzala e rispondi.]" : userText
        if coderMode == .ide {
            prompt =
                "Rispondi solo con testo. Non modificare file né eseguire comandi.\n\n" + prompt
        }
        if coderMode == .mcpServer { prompt = "[MCP Server] " + prompt }
        if providerRegistry.selectedProviderId == "codex-cli"
            || providerRegistry.selectedProviderId == "claude-cli"
            || providerRegistry.selectedProviderId == "gemini-cli"
        {
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
                    "Per task complessi che richiedono planner, coder, reviewer, ecc., delega allo swarm scrivendo: \(CoderIDEMarkers.invokeSwarmPrefix)DESCRIZIONE_TASK\(CoderIDEMarkers.invokeSwarmSuffix)\n\n"
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
        return prompt
    }

    // MARK: - Handle Raw Stream Events

    private func handleRawStreamEvent(
        type t: String, payload p: [String: String], providerId pid: String
    ) {
        if t == "coderide_show_task_panel" { taskPanelEnabled = true }
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

    // MARK: - Handle Stream Result (plan options + swarm delegation)

    private func handleStreamResult(
        conversationId streamConversationId: UUID,
        _ streamResult: (fullText: String, pendingSwarmTask: String?),
        shouldRunPlanInline: Bool,
        ctx: WorkspaceContext,
        imageURLsToSend: [URL]?,
        prompt: String
    ) async {
        let full = streamResult.fullText
        let pendingSwarmTask = streamResult.pendingSwarmTask
        if timelineConversationId == streamConversationId {
            turnTimelineStore.finalize(lastFullText: full)
        }
        chatStore.setLastAssistantStreaming(false, in: streamConversationId)
        await trySummarizeIfNeeded(ctx: ctx)

        // Handle plan options parsing
        if coderMode == .plan || shouldRunPlanInline {
            let opts = PlanOptionsParser.parse(from: full)
            if !opts.isEmpty {
                await MainActor.run {
                    if coderMode == .plan {
                        planningState = .awaitingChoice(planContent: full, options: opts)
                    }
                    let board = PlanBoard.build(from: full, options: opts)
                    chatStore.setPlanBoard(board, for: streamConversationId)
                    if shouldRunPlanInline {
                        let cid = streamConversationId
                        inlinePlanSummaries[cid] = {
                            let parsed = PlanOptionsParser.extractDisplaySummary(from: full)
                            return InlinePlanSummary(title: parsed.title, body: parsed.body)
                        }()
                        isPlanSummaryCollapsed = false
                        let currentConv = chatStore.conversation(for: cid)
                        let contextId = currentConv?.contextId
                        let contextFolderPath = currentConv?.contextFolderPath
                        let planConvId = chatStore.getOrCreateConversationForMode(
                            contextId: contextId, contextFolderPath: contextFolderPath,
                            mode: .plan)
                        chatStore.setPlanBoard(board, for: planConvId)
                    }
                }
            }
        }

        // Handle delegated swarm if pending
        if let task = pendingSwarmTask {
            await handleDelegatedSwarm(
                task: task, ctx: ctx, imageURLsToSend: imageURLsToSend, prompt: prompt
            )
        }
    }

    // MARK: - Delegated Swarm Handling

    private func handleDelegatedSwarm(
        task: String,
        ctx: WorkspaceContext,
        imageURLsToSend: [URL]?,
        prompt: String
    ) async {
        guard let swarm = providerRegistry.provider(for: "agent-swarm"),
            swarm.isAuthenticated()
        else { return }

        let agentProviderIdBeforeSwarm = providerRegistry.selectedProviderId
        chatStore.addMessage(
            ChatMessage(
                role: .user, content: "[Delegato allo swarm] \(task)",
                isStreaming: false), to: conversationId)
        chatStore.addMessage(
            ChatMessage(role: .assistant, content: "", isStreaming: true),
            to: conversationId)
        chatStore.beginTask()
        taskActivityStore.clear()
        turnTimelineStore.clear()
        timelineConversationId = conversationId
        swarmProgressStore.clear()

        let followUpProvider: (any LLMProvider)? = {
            guard let agentId = agentProviderIdBeforeSwarm,
                agentId == "codex-cli" || agentId == "claude-cli",
                let agentProvider = providerRegistry.provider(for: agentId),
                agentProvider.isAuthenticated()
            else { return nil }
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
                chatStore.updateLastAssistantMessage(
                    content: content, in: conversationId)
                turnTimelineStore.updateLastKnownText(content)
            },
            onRaw: { t, p, pid in
                handleRawStreamEvent(type: t, payload: p, providerId: pid)
            },
            onFollowUpText: { content in
                chatStore.updateLastAssistantMessage(
                    content: content, in: conversationId)
                turnTimelineStore.updateLastKnownText(content)
            },
            onError: { content in
                chatStore.updateLastAssistantMessage(
                    content: content, in: conversationId)
            }
        )
        chatStore.endTask()
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
        chatStore.addMessage(
            ChatMessage(role: .assistant, content: message, isStreaming: false), to: conversationId)
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
                if chatStore.isLoading {
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
                    chatStore.endTask()
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
                            flowDiagnosticsStore.setError(
                                "Rewind file parziale: \(error.localizedDescription)")
                        }
                    }
                }
            }

            await MainActor.run {
                let rewound: Bool
                if let checkpoint {
                    rewound = chatStore.rewindConversationState(
                        to: checkpoint.id, conversationId: convId)
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
                taskActivityStore.clear()
                swarmProgressStore.clear()
                turnTimelineStore.clear()
                timelineConversationId = nil
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
                if chatStore.isLoading {
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
                    chatStore.endTask()
                }
            }

            if let checkpoint {
                for state in checkpoint.gitStates {
                    do {
                        try checkpointGitStore.restoreSnapshot(
                            ref: state.gitSnapshotRef, gitRoot: state.gitRootPath)
                    } catch {
                        await MainActor.run {
                            flowDiagnosticsStore.setError(
                                "Rewind file parziale: \(error.localizedDescription)")
                        }
                    }
                }
            }

            await MainActor.run {
                let rewound = chatStore.rewindConversationToMessageCount(
                    messageIndex + 1, conversationId: conversationId)
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
                taskActivityStore.clear()
                swarmProgressStore.clear()
                turnTimelineStore.clear()
                timelineConversationId = nil
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
        guard let gitRoot = changedFilesStore.gitRoot else { return }
        let absolutePath = URL(fileURLWithPath: gitRoot).appendingPathComponent(repoRelativePath)
            .path
        let gitService = GitService()
        openFilesStore.openFileWithDiff(absolutePath, gitRoot: gitRoot, gitService: gitService)
        selectMode(.ide)
    }

    private func streamingStatusText(for message: ChatMessage) -> String {
        guard message.isStreaming, message.role == .assistant else { return "Sto scrivendo..." }
        if executionController.runState == .paused {
            return "In pausa..."
        }
        guard let last = taskActivityStore.activities.last else { return "Sto pensando..." }
        switch last.phase {
        case .executing:
            return "Sto eseguendo..."
        case .editing:
            return "Sto scrivendo..."
        case .searching:
            return "Ricerca web in corso..."
        case .planning, .thinking:
            return "Sto pensando..."
        }
    }

    private func streamingDetailText(for message: ChatMessage) -> String? {
        guard message.isStreaming, message.role == .assistant else { return nil }
        guard let last = taskActivityStore.activities.last else { return nil }
        let op = taskActivityStore.activeOperationsCount
        if op > 0 {
            return "\(last.title) • \(op) operazioni attive"
        }
        return last.title
    }

    private func streamingReasoningText(for message: ChatMessage) -> String? {
        guard message.isStreaming, message.role == .assistant else { return nil }
        let raw = taskActivityStore.activities
            .reversed()
            .first {
                $0.phase == .thinking
                    && !(($0.payload["output"] ?? $0.payload["text"] ?? "").trimmingCharacters(
                        in: .whitespacesAndNewlines
                    ).isEmpty)
            }
            .flatMap { $0.payload["output"] ?? $0.payload["text"] }
        let text = raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return text.isEmpty ? nil : text
    }
}
