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
    @FocusState private var isInputFocused: Bool
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
    @AppStorage("default_agent_provider_id") private var defaultAgentProviderId = "codex-cli"
    @AppStorage("openai_api_key") private var openaiApiKey = ""
    @AppStorage("openai_model") private var openaiModel = "gpt-4o-mini"
    @AppStorage("anthropic_api_key") private var anthropicApiKey = ""
    @AppStorage("anthropic_model") private var anthropicModel = "claude-sonnet-4-6"
    @AppStorage("google_api_key") private var googleApiKey = ""
    @AppStorage("google_model") private var googleModel = "gemini-2.5-pro"
    @AppStorage("openrouter_api_key") private var openrouterApiKey = ""
    @AppStorage("openrouter_model") private var openrouterModel = "anthropic/claude-sonnet-4.5"
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
    @State private var isFollowingLive = true
    @State private var newEventsWhileDetached = 0
    @State private var isAnyAgentProviderReady = false
    @State private var userModeOverrideUntilConversationChange = false
    @State private var ignoreNextConversationChangeReset = false
    @StateObject private var flowCoordinator = ConversationFlowCoordinator()
    @AppStorage("flow_diagnostics_enabled") private var flowDiagnosticsEnabled = false
    private let checkpointGitStore = ConversationCheckpointGitStore()
    private let cliAccountsStore = CLIAccountsStore.shared
    private let cliAccountRouter = CLIAccountRouter.shared

    private static let imagePastedNotification = Notification.Name("CoderIDE.ImagePasted")
    private static let threadSearchAskAINotification = Notification.Name(
        "CoderIDE.ThreadSearchAskAI")
    private let topInteractiveInset: CGFloat = 22

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

    // MARK: - Messages Area
    private var messagesArea: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if let conv = chatStore.conversation(for: conversationId) {
                        ForEach(conv.messages) { message in
                            MessageRow(
                                message: message,
                                context: effectiveContext.context,
                                modeColor: activeModeColor,
                                streamingStatusText: streamingStatusText(for: message),
                                streamingDetailText: streamingDetailText(for: message),
                                onFileClicked: { openFilesStore.openFile($0) }
                            )
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
                        // Attività e timer in chat (solo quando c'è un task e pannello attivo)
                        if chatStore.isLoading
                            || (!taskActivityStore.activities.isEmpty && taskPanelEnabled)
                        {
                            chatInlineTaskStatus
                                .id("chat-task-status")
                        }
                        if flowDiagnosticsEnabled {
                            flowDiagnosticsCard
                                .padding(.horizontal, 16)
                                .padding(.bottom, 8)
                        }
                        if hasJustCompletedTask, !changedFilesStore.files.isEmpty {
                            changedFilesSummaryCard
                                .padding(.horizontal, 16)
                                .padding(.bottom, 8)
                        }
                    }
                }
                .padding(.top, 8).padding(.bottom, 16)
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
                    withAnimation(.easeOut(duration: 0.2)) {
                        proxy.scrollTo("chat-task-status", anchor: .bottom)
                    }
                }
            }
            .onChange(of: taskActivityStore.activities.count) { _, _ in
                if chatStore.isLoading {
                    if isFollowingLive {
                        withAnimation(.easeOut(duration: 0.2)) {
                            proxy.scrollTo("chat-task-status", anchor: .bottom)
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

    private var changedFilesSummaryCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text("\(changedFilesStore.files.count) files changed")
                    .font(.system(size: 14, weight: .semibold))
                Text("+\(changedFilesStore.totalAdded)")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(DesignSystem.Colors.success)
                Text("-\(changedFilesStore.totalRemoved)")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(DesignSystem.Colors.error)
                Spacer()
                Button("Undo") {
                    changedFilesStore.undoAll()
                }
                .buttonStyle(.plain)
                .disabled(changedFilesStore.files.isEmpty)
            }

            ForEach(changedFilesStore.files.prefix(8)) { file in
                HStack(spacing: 8) {
                    Button {
                        openChangedFile(file.path)
                    } label: {
                        Text(file.path)
                            .font(.system(size: 12, weight: .medium))
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                    Text("+\(file.added)")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(DesignSystem.Colors.success)
                    Text("-\(file.removed)")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(DesignSystem.Colors.error)
                }
                .padding(.vertical, 2)
            }
        }
        .padding(12)
        .background(
            Color(nsColor: .controlBackgroundColor).opacity(0.55),
            in: RoundedRectangle(cornerRadius: 12)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12).strokeBorder(
                DesignSystem.Colors.border, lineWidth: 0.6))
    }

    @ViewBuilder
    private var chatInlineTaskStatus: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Execution control bar
            if chatStore.isLoading, let startDate = chatStore.taskStartDate {
                TimelineView(.periodic(from: startDate, by: 1.0)) { context in
                    let elapsed = Int(context.date.timeIntervalSince(startDate))
                    executionControlBar(elapsed: elapsed)
                }
            }

            // Summarizing indicator
            if isSummarizing {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Compressing context...")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(DesignSystem.Colors.info.opacity(0.06))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(DesignSystem.Colors.info.opacity(0.1), lineWidth: 0.5)
                )
            }

            // Todo inline card
            if chatStore.isLoading {
                TodoLiveInlineCard(
                    store: todoStore,
                    onOpenFile: { path in
                        openFilesStore.openFile(path)
                    })
            }

            // Activity panels
            if !taskActivityStore.activities.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    if coderMode == .agentSwarm {
                        SwarmLiveBoardView(
                            activities: taskActivityStore.activities,
                            isTaskRunning: chatStore.isLoading)
                    } else {
                        // Plan trace
                        if coderMode == .plan {
                            PlanLiveTraceView(
                                activities: taskActivityStore.planRelevantRecentActivities(
                                    limit: 60))
                        }

                        // Reasoning timeline
                        LiveActivityTimelineView(
                            activities: taskActivityStore.activities,
                            maxVisible: 20
                        )

                        // Web search results
                        WebSearchLiveView(activities: taskActivityStore.activities)

                        // Terminal sessions
                        ChatTerminalSessionsView(activities: taskActivityStore.activities)

                        // Grep results
                        InstantGrepCardsView(results: taskActivityStore.instantGreps) { match in
                            let fullPath: String
                            if (match.file as NSString).isAbsolutePath {
                                fullPath = match.file
                            } else {
                                let basePath = effectiveContext.primaryPath ?? ""
                                fullPath = (basePath as NSString).appendingPathComponent(match.file)
                            }
                            openFilesStore.openFile(fullPath)
                        }

                        // Todo
                        TodoLiveInlineCard(
                            store: todoStore,
                            onOpenFile: { path in
                                openFilesStore.openFile(path)
                            })

                        // Recent activity rows (compact)
                        let recentOther = taskActivityStore.activities
                            .filter { $0.type != "command_execution" && $0.type != "bash" }
                            .suffix(6)
                        if !recentOther.isEmpty {
                            VStack(alignment: .leading, spacing: 2) {
                                ForEach(recentOther) { activity in
                                    TaskActivityRow(activity: activity)
                                }
                            }
                        }
                    }
                }
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color(nsColor: .controlBackgroundColor).opacity(0.35))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Color(nsColor: .separatorColor).opacity(0.3), lineWidth: 0.5)
                )
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 8)
    }

    // MARK: - Execution Control Bar

    private func executionControlBar(elapsed: Int) -> some View {
        HStack(spacing: 10) {
            // Status indicator
            HStack(spacing: 6) {
                if executionController.runState == .paused {
                    Image(systemName: "pause.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.orange)
                } else {
                    ProgressView()
                        .controlSize(.small)
                }

                Text(executionController.runState == .paused ? "Paused" : "Running")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            // Timer
            Text(formatElapsed(elapsed))
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(DesignSystem.Colors.warning)

            // Active ops count
            if taskActivityStore.activeOperationsCount > 0 {
                Text("\(taskActivityStore.activeOperationsCount) ops")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.primary.opacity(0.04), in: Capsule())
            }

            Spacer()

            // Pause / Resume
            if executionController.runState == .paused {
                Button {
                    let scope = executionScope(for: coderMode)
                    executionController.resume(scope: scope)
                    taskActivityStore.markResumed()
                    taskActivityStore.addActivity(
                        TaskActivity(
                            type: "process_resumed",
                            title: "Process resumed",
                            detail: "Resumed by user",
                            payload: [:],
                            phase: .executing,
                            isRunning: true
                        )
                    )
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "play.fill")
                            .font(.system(size: 9, weight: .bold))
                        Text("Resume")
                            .font(.system(size: 11, weight: .medium))
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            } else {
                Button {
                    let scope = executionScope(for: coderMode)
                    executionController.pause(scope: scope)
                    taskActivityStore.markPaused()
                    taskActivityStore.addActivity(
                        TaskActivity(
                            type: "process_paused",
                            title: "Process paused",
                            detail: "Paused by user",
                            payload: [:],
                            phase: .thinking,
                            isRunning: false
                        )
                    )
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "pause.fill")
                            .font(.system(size: 9, weight: .bold))
                        Text("Pause")
                            .font(.system(size: 11, weight: .medium))
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            // Stop
            Button {
                let scope = executionScope(for: coderMode)
                executionController.terminate(scope: scope)
                flowCoordinator.interrupt()
                if let cid = conversationId {
                    let cur =
                        chatStore.conversation(for: cid)?.messages.last(where: {
                            $0.role == .assistant
                        })?.content ?? ""
                    chatStore.updateLastAssistantMessage(
                        content: cur.isEmpty
                            ? "[Stopped by user]"
                            : cur + "\n\n[Stopped by user]", in: cid)
                    chatStore.setLastAssistantStreaming(false, in: cid)
                }
                chatStore.endTask()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "stop.fill")
                        .font(.system(size: 9, weight: .bold))
                    Text("Stop")
                        .font(.system(size: 11, weight: .medium))
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
            .controlSize(.small)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.5))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(DesignSystem.Colors.warning.opacity(0.15), lineWidth: 0.5)
        )
    }

    private func executionScope(for mode: CoderMode) -> ExecutionScope {
        switch mode {
        case .agentSwarm: return .swarm
        case .codeReviewMultiSwarm: return .review
        case .plan: return .plan
        default: return .agent
        }
    }

    private func formatElapsed(_ s: Int) -> String {
        let m = s / 60
        let sec = s % 60
        return String(format: "%d:%02d", m, sec)
    }

    @MainActor
    private func recordTaskActivity(type: String, payload: [String: String], providerId: String) {
        let envelope = flowCoordinator.normalizeRawEvent(
            providerId: providerId, type: type, payload: payload)
        taskActivityStore.addEnvelope(envelope)
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
                    || activity.type == "web_search_failed"
                {
                    taskActivityStore.appendOrMergeBatchEvent(activity)
                } else {
                    taskActivityStore.addActivity(activity)
                }
            case .instantGrep(let grep):
                taskPanelEnabled = true
                taskActivityStore.addInstantGrep(grep)
            case .todoWrite(let todo):
                todoStore.upsertFromAgent(
                    id: todo.id,
                    title: todo.title,
                    status: todo.status,
                    priority: todo.priority,
                    notes: todo.notes,
                    linkedFiles: todo.files
                )
            case .todoRead:
                break
            case .planStepUpdate(let stepId, let status):
                chatStore.updatePlanStepStatus(stepId: stepId, status: status, in: conversationId)
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
    private var composerArea: some View {
        VStack(spacing: 0) {
            separator
            if !isProviderReady {
                providerNotReadyBanner
            }
            VStack(spacing: 8) {
                composerBox
                controlsBar
            }
            .padding(12)
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

    private var providerNotReadyBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 11))
                .foregroundStyle(.orange)
            Text(providerNotReadyMessage)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color.orange.opacity(0.08))
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

    private var composerBox: some View {
        HStack(alignment: .bottom, spacing: 10) {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 5) {
                    Circle().fill(activeModeGradient).frame(width: 6, height: 6)
                    Text(inputHint)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(activeModeColor.opacity(0.6))
                }
                if !attachedImageURLs.isEmpty {
                    attachedImagesRow
                }
                TextField("Scrivi un messaggio...", text: $inputText, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .lineLimit(1...8)
                    .focused($isInputFocused)
                    .onSubmit { sendMessage() }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 8) {
                imageAttachButton
                sendButton
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(DesignSystem.Colors.backgroundTertiary)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(
                    isComposerDropTargeted
                        ? activeModeColor.opacity(0.6)
                        : (isInputFocused
                            ? activeModeColor.opacity(0.4) : DesignSystem.Colors.border),
                    lineWidth: isComposerDropTargeted ? 2 : (isInputFocused ? 1.2 : 0.5)
                )
        )
        .shadow(color: isInputFocused ? activeModeColor.opacity(0.1) : .clear, radius: 12, y: 2)
        .shadow(color: .black.opacity(0.12), radius: 4, y: 2)
        .animation(.easeOut(duration: 0.2), value: isInputFocused)
        .onDrop(of: [.image, .fileURL, .png, .jpeg, .gif], isTargeted: $isComposerDropTargeted) {
            providers in
            Task {
                for provider in providers {
                    if let url = await ImageAttachmentHelper.imageURLFromDropProvider(provider) {
                        await MainActor.run { attachedImageURLs.append(url) }
                    }
                }
            }
            return true
        }
        .overlay {
            if isConvertingHeic {
                RoundedRectangle(cornerRadius: 12)
                    .fill(.ultraThinMaterial)
                    .overlay {
                        VStack(spacing: 8) {
                            ProgressView().controlSize(.regular)
                            Text("Conversione HEIC in corso…")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                    }
            }
        }
    }

    private var attachedImagesRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(Array(attachedImageURLs.enumerated()), id: \.offset) { index, url in
                    ZStack(alignment: .topTrailing) {
                        if let nsImage = NSImage(contentsOf: url) {
                            Image(nsImage: nsImage)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: 44, height: 44)
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                        }
                        Button {
                            attachedImageURLs.remove(at: index)
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 14))
                                .foregroundStyle(.white)
                                .shadow(color: .black.opacity(0.5), radius: 1)
                        }
                        .buttonStyle(.plain)
                        .offset(x: 4, y: -4)
                    }
                }
            }
        }
    }

    private var imageAttachButton: some View {
        Button {
            isSelectingImage = true
        } label: {
            Image(systemName: "photo.badge.plus")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .help("Allega immagine (⌘V per incollare)")
    }

    private var sendButton: some View {
        let awaitingChoice = if case .awaitingChoice = planningState { true } else { false }
        let canSend =
            (!inputText.isEmpty || !attachedImageURLs.isEmpty) && !chatStore.isLoading
            && !awaitingChoice && isProviderReady
        return Button(action: sendMessage) {
            Image(systemName: "arrow.up")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background {
                    Circle().fill(
                        canSend
                            ? activeModeGradient
                            : LinearGradient(
                                colors: [DesignSystem.Colors.borderAccent], startPoint: .top,
                                endPoint: .bottom))
                }
                .shadow(color: canSend ? activeModeColor.opacity(0.3) : .clear, radius: 6, y: 2)
        }
        .buttonStyle(.plain).disabled(!canSend)
        .animation(.easeOut(duration: 0.15), value: canSend)
    }

    /// Provider effettivo usato dalla modalità corrente, mostrato come badge sotto al provider.
    private var effectiveModeProviderLabel: String? {
        switch providerRegistry.selectedProviderId {
        case "plan-mode":
            return "Plan → " + (planModeBackend == "claude" ? "Claude CLI" : "Codex CLI")
        case "agent-swarm":
            return "Swarm → " + (swarmWorkerBackend == "claude" ? "Claude CLI" : "Codex CLI")
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
                if let selected = providerRegistry.selectedProviderId, selected == "codex-cli" {
                    return "Codex CLI"
                }
                if let selected = providerRegistry.selectedProviderId, selected == "claude-cli" {
                    return "Claude CLI"
                }
            }
            return nil
        }
    }

    private var controlsBar: some View {
        HStack(spacing: 6) {
            providerPicker
            if let modeLabel = effectiveModeProviderLabel {
                Text(modeLabel)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.primary.opacity(0.06))
                    .clipShape(Capsule())
            }
            if providerRegistry.selectedProviderId == "codex-cli" {
                codexModelPicker
                codexReasoningPicker
                accessLevelMenu
                if coderMode == .agent || coderMode == .agentSwarm { formicaButton }
            } else if providerRegistry.selectedProviderId == "gemini-cli" {
                geminiModelPicker
                if coderMode == .agent || coderMode == .agentSwarm { formicaButton }
            } else if providerRegistry.selectedProviderId == "claude-cli" {
                if coderMode == .agent || coderMode == .agentSwarm { formicaButton }
            } else if providerRegistry.selectedProviderId == "agent-swarm" {
                swarmOrchestratorPicker
                swarmWorkerPicker
                Button {
                    showSwarmHelp = true
                } label: {
                    Image(systemName: "questionmark.circle").font(.caption).foregroundStyle(
                        DesignSystem.Colors.swarmColor)
                }.buttonStyle(.plain)
                if coderMode == .agent || coderMode == .agentSwarm { formicaButton }
            } else if providerRegistry.selectedProviderId == "plan-mode" {
                Spacer()
                if coderMode == .plan { formicaButton }
            } else if [.agent, .agentSwarm, .plan].contains(coderMode) {
                Spacer()
                formicaButton
            } else if coderMode == .ide {
                Spacer()
                delegaAdAgentButton
            } else {
                Spacer()
            }
        }
    }

    private var delegaAdAgentButton: some View {
        let msg = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        let lastUser =
            chatStore.conversation(for: conversationId)?.messages.last(where: { $0.role == .user })?
            .content ?? ""
        let canDelegate =
            (!msg.isEmpty || !lastUser.isEmpty || !attachedImageURLs.isEmpty)
            && !chatStore.isLoading
        let agentOk = isAnyAgentProviderReady
        return Button {
            delegateToAgent()
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "arrow.right.circle")
                    .font(.system(size: 12))
                Text("Delega ad Agent")
                    .font(.system(size: 11, weight: .medium))
            }
            .foregroundStyle((canDelegate && agentOk) ? DesignSystem.Colors.agentColor : .secondary)
        }
        .buttonStyle(.plain)
        .disabled(!canDelegate || !agentOk)
        .help("Passa ad Agent e invia il messaggio (modifica file, comandi)")
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

    // MARK: - Pickers

    private var providerPicker: some View {
        Menu {
            ForEach(providerRegistry.providers, id: \.id) { provider in
                Button {
                    providerRegistry.selectedProviderId = provider.id
                    chatStore.updatePreferredProvider(
                        conversationId: conversationId, providerId: provider.id)
                    if coderMode == .agent && ProviderSupport.isAgentProvider(id: provider.id) {
                        defaultAgentProviderId = provider.id
                    }
                } label: {
                    HStack {
                        Text(provider.displayName)
                        if providerRegistry.selectedProviderId == provider.id {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "cpu").font(.caption2)
                Text(providerLabel).font(.caption)
                Image(systemName: "chevron.down").font(.system(size: 8, weight: .bold))
            }.foregroundStyle(.secondary)
        }.menuStyle(.borderlessButton).fixedSize()
    }

    private var providerLabel: String {
        if let id = providerRegistry.selectedProviderId,
            let p = providerRegistry.providers.first(where: { $0.id == id })
        {
            return p.displayName
        }
        return "Seleziona provider"
    }

    private var codexModelPicker: some View {
        Menu {
            Button {
                codexModelOverride = ""
                syncCodexProvider()
            } label: {
                HStack {
                    Text("Default (da config)")
                    if codexModelOverride.isEmpty { Image(systemName: "checkmark") }
                }
            }
            if !codexModels.isEmpty {
                Divider()
                ForEach(codexModels, id: \.slug) { m in
                    Button {
                        codexModelOverride = m.slug
                        syncCodexProvider()
                    } label: {
                        HStack {
                            Text(m.displayName)
                            if codexModelOverride == m.slug { Image(systemName: "checkmark") }
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text(codexModelLabel).font(.caption)
                Image(systemName: "chevron.down").font(.system(size: 8, weight: .bold))
            }.foregroundStyle(.secondary)
        }.menuStyle(.borderlessButton).fixedSize()
    }

    private var codexModelLabel: String {
        codexModelOverride.isEmpty
            ? "Default"
            : (codexModels.first(where: { $0.slug == codexModelOverride })?.displayName
                ?? codexModelOverride)
    }

    private var geminiModelPicker: some View {
        Menu {
            Button {
                geminiModelOverride = ""
                syncGeminiProvider()
            } label: {
                HStack {
                    Text("Default (auto)")
                    if geminiModelOverride.isEmpty { Image(systemName: "checkmark") }
                }
            }
            if !geminiModels.isEmpty {
                Divider()
                ForEach(geminiModels, id: \.slug) { m in
                    Button {
                        geminiModelOverride = m.slug
                        syncGeminiProvider()
                    } label: {
                        HStack {
                            Text(m.displayName)
                            if geminiModelOverride == m.slug { Image(systemName: "checkmark") }
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text(geminiModelLabel).font(.caption)
                Image(systemName: "chevron.down").font(.system(size: 8, weight: .bold))
            }.foregroundStyle(.secondary)
        }.menuStyle(.borderlessButton).fixedSize()
    }

    private var geminiModelLabel: String {
        geminiModelOverride.isEmpty
            ? "Default"
            : (geminiModels.first(where: { $0.slug == geminiModelOverride })?.displayName
                ?? geminiModelOverride)
    }

    private var codexReasoningPicker: some View {
        Menu {
            ForEach(["low", "medium", "high", "xhigh"], id: \.self) { e in
                Button {
                    codexReasoningEffort = e
                    syncCodexProvider()
                } label: {
                    HStack {
                        Text(reasoningEffortDisplay(e))
                        if codexReasoningEffort == e { Image(systemName: "checkmark") }
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text(reasoningEffortDisplay(codexReasoningEffort)).font(.caption)
                Image(systemName: "chevron.down").font(.system(size: 8, weight: .bold))
            }.foregroundStyle(.secondary)
        }.menuStyle(.borderlessButton).fixedSize()
    }

    private func reasoningEffortDisplay(_ e: String) -> String {
        switch e.lowercased() {
        case "low": return "Low"
        case "medium": return "Medium"
        case "high": return "High"
        case "xhigh": return "XHigh"
        default: return e
        }
    }

    private var effectiveSandbox: String {
        codexSandbox.isEmpty
            ? (CodexConfigLoader.load().sandboxMode ?? "workspace-write") : codexSandbox
    }

    private var accessLevelMenu: some View {
        let cfg = CodexConfigLoader.load()
        return Menu {
            Button {
                codexSandbox = ""
                syncCodexProvider()
            } label: {
                HStack {
                    Label("Default (da config)", systemImage: "doc.badge.gearshape")
                    if codexSandbox.isEmpty { Image(systemName: "checkmark") }
                }
            }
            if cfg.sandboxMode != nil {
                Text("Config: \(accessLevelLabel(for: cfg.sandboxMode ?? ""))").font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Divider()
            Button {
                codexSandbox = "read-only"
                syncCodexProvider()
            } label: {
                Label("Read Only", systemImage: "lock.shield")
            }
            Button {
                codexSandbox = "workspace-write"
                syncCodexProvider()
            } label: {
                Label("Default", systemImage: "shield")
            }
            Button {
                codexSandbox = "danger-full-access"
                syncCodexProvider()
            } label: {
                Label("Full Access", systemImage: "exclamationmark.shield.fill")
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: accessLevelIcon(for: effectiveSandbox)).font(.caption)
                Text(accessLevelLabel(for: effectiveSandbox)).font(.caption)
                Image(systemName: "chevron.down").font(.system(size: 8, weight: .bold))
            }.foregroundStyle(
                effectiveSandbox == "danger-full-access" ? DesignSystem.Colors.error : .secondary)
        }.menuStyle(.borderlessButton).fixedSize()
    }

    private var swarmOrchestratorPicker: some View {
        Menu {
            Button {
                swarmOrchestrator = "openai"
                syncSwarmProvider()
            } label: {
                HStack {
                    Text("OpenAI")
                    if swarmOrchestrator == "openai" { Image(systemName: "checkmark") }
                }
            }
            Button {
                swarmOrchestrator = "codex"
                syncSwarmProvider()
            } label: {
                HStack {
                    Text("Codex")
                    if swarmOrchestrator == "codex" { Image(systemName: "checkmark") }
                }
            }
            Button {
                swarmOrchestrator = "claude"
                syncSwarmProvider()
            } label: {
                HStack {
                    Text("Claude")
                    if swarmOrchestrator == "claude" { Image(systemName: "checkmark") }
                }
            }
            Button {
                swarmOrchestrator = "gemini"
                syncSwarmProvider()
            } label: {
                HStack {
                    Text("Gemini")
                    if swarmOrchestrator == "gemini" { Image(systemName: "checkmark") }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "ant.fill").font(.caption2)
                let orchLabel: String = {
                    switch swarmOrchestrator {
                    case "codex": return "Codex"
                    case "claude": return "Claude"
                    case "gemini": return "Gemini"
                    default: return "OpenAI"
                    }
                }()
                Text("Orchestrator: \(orchLabel)").font(.caption)
                Image(systemName: "chevron.down").font(.system(size: 8, weight: .bold))
            }.foregroundStyle(.secondary)
        }.menuStyle(.borderlessButton).fixedSize()
    }

    private var swarmWorkerPicker: some View {
        Menu {
            ForEach(["codex", "claude", "gemini"], id: \.self) { backend in
                Button {
                    swarmWorkerBackend = backend
                    syncSwarmProvider()
                } label: {
                    HStack {
                        Text(backend.capitalized)
                        if swarmWorkerBackend == backend { Image(systemName: "checkmark") }
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "cpu").font(.caption2)
                Text("Worker: \(swarmWorkerBackend.capitalized)").font(.caption)
                Image(systemName: "chevron.down").font(.system(size: 8, weight: .bold))
            }.foregroundStyle(.secondary)
        }.menuStyle(.borderlessButton).fixedSize()
    }

    private var formicaButton: some View {
        Button {
            taskPanelEnabled.toggle()
        } label: {
            Image(systemName: "ant.fill").font(.caption)
                .foregroundStyle(taskPanelEnabled ? DesignSystem.Colors.swarmColor : .secondary)
        }.buttonStyle(.plain).help("Task Activity Panel")
    }

    private func accessLevelIcon(for s: String) -> String {
        switch s {
        case "read-only": return "lock.shield"
        case "danger-full-access": return "exclamationmark.shield.fill"
        default: return "shield"
        }
    }
    private func accessLevelLabel(for s: String) -> String {
        switch s {
        case "read-only": return "Read Only"
        case "danger-full-access": return "Full Access"
        default: return "Default"
        }
    }
    private func selectMode(_ mode: CoderMode) {
        userModeOverrideUntilConversationChange = true
        let currentConv = chatStore.conversation(for: selectedConversationId)
        let contextId = currentConv?.contextId
        let contextFolderPath = currentConv?.contextFolderPath

        let newConvId = chatStore.getOrCreateConversationForMode(
            contextId: contextId, contextFolderPath: contextFolderPath, mode: mode)
        ignoreNextConversationChangeReset = true
        selectedConversationId = newConvId

        let newConv = chatStore.conversation(for: newConvId)
        switch mode {
        case .ide:
            if let preferred = newConv?.preferredProviderId,
                ProviderSupport.isIDEProvider(id: preferred),
                providerRegistry.provider(for: preferred) != nil
            {
                providerRegistry.selectedProviderId = preferred
            } else {
                providerRegistry.selectedProviderId = ProviderSupport.preferredIDEProvider(
                    in: providerRegistry)
            }
        case .agent:
            if let preferred = newConv?.preferredProviderId,
                ProviderSupport.isAgentProvider(id: preferred),
                providerRegistry.provider(for: preferred) != nil
            {
                providerRegistry.selectedProviderId = preferred
            } else if ProviderSupport.isAgentProvider(id: defaultAgentProviderId),
                providerRegistry.provider(for: defaultAgentProviderId) != nil
            {
                providerRegistry.selectedProviderId = defaultAgentProviderId
            } else if let current = providerRegistry.selectedProviderId,
                ProviderSupport.isAgentProvider(id: current)
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
        guard let codex = providerRegistry.provider(for: "codex-cli") as? CodexCLIProvider else {
            return
        }
        let claude = providerRegistry.provider(for: "claude-cli") as? ClaudeCLIProvider
        let gemini = providerRegistry.provider(for: "gemini-cli") as? GeminiCLIProvider
        providerRegistry.unregister(id: "agent-swarm")
        providerRegistry.register(
            ProviderFactory.swarmProvider(
                config: providerFactoryConfig(), codex: codex, claude: claude,
                gemini: gemini, executionController: executionController))
        checkProviderAuth()
    }
    private func syncMultiSwarmReviewProvider() {
        guard let codex = providerRegistry.provider(for: "codex-cli") as? CodexCLIProvider else {
            return
        }
        let claude = providerRegistry.provider(for: "claude-cli") as? ClaudeCLIProvider
        providerRegistry.unregister(id: "multi-swarm-review")
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
                ProviderSupport.isAgentProvider(id: preferred),
                providerRegistry.provider(for: preferred) != nil
            {
                providerRegistry.selectedProviderId = preferred
            } else if ProviderSupport.isAgentProvider(id: defaultAgentProviderId),
                providerRegistry.provider(for: defaultAgentProviderId) != nil
            {
                providerRegistry.selectedProviderId = defaultAgentProviderId
            } else if let current = providerRegistry.selectedProviderId,
                ProviderSupport.isAgentProvider(id: current)
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
        guard codex != nil || claude != nil else { return }
        providerRegistry.unregister(id: "plan-mode")
        providerRegistry.register(
            ProviderFactory.planProvider(
                config: providerFactoryConfig(), codex: codex, claude: claude,
                executionController: executionController))
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
            swarmWorkerBackendOverrides: UserDefaults.standard.string(
                forKey: "swarm_worker_backend_overrides") ?? "",
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
        guard case .awaitingChoice(let planContent, _) = planningState else { return }
        let useClaude = planModeBackend == "claude"
        let provider: any LLMProvider
        if useClaude {
            guard let c = providerRegistry.provider(for: "claude-cli") as? ClaudeCLIProvider else {
                return
            }
            provider = c
        } else {
            guard let c = providerRegistry.provider(for: "codex-cli") as? CodexCLIProvider else {
                return
            }
            provider = c
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
        chatStore.choosePlanPath(choice, for: conversationId)
        chatStore.updatePlanStepStatus(stepId: "1", status: .running, in: conversationId)
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

        let prompt =
            "L'utente ha scelto il seguente approccio dal piano precedentemente proposto. Implementalo.\n\nPiano di riferimento:\n\(planContent)\n\nScelta dell'utente:\n\(choice)"

        Task {
            do {
                _ = try await flowCoordinator.runStream(
                    provider: provider,
                    prompt: prompt,
                    context: ctx,
                    imageURLs: nil,
                    onText: { content in
                        chatStore.updateLastAssistantMessage(content: content, in: agentConvId)
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
                chatStore.updatePlanStepStatus(stepId: "1", status: .done, in: conversationId)
            } catch {
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
    private func sendMessage() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty || !attachedImageURLs.isEmpty else { return }
        guard let selectedProvider = providerRegistry.selectedProvider else { return }
        hasJustCompletedTask = false
        let shouldRunPlanInline = coderMode == .agent && planToggleEnabled
        let runtimeProvider: any LLMProvider = {
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
        }()
        if multiCLIAccountEnabled,
            let selectedProviderId = providerRegistry.selectedProviderId,
            let kind = CLIProviderKind.fromProviderId(selectedProviderId),
            case .allExhausted(let reason) = cliAccountRouter.currentAvailability(provider: kind)
        {
            appendTechnicalErrorMessage(
                "[Multi-account \(kind.displayName): \(reason). Configura account o resetta i limiti nelle Impostazioni.]",
                in: conversationId)
            flowDiagnosticsStore.setError("Multi-account \(kind.rawValue): \(reason)")
            return
        }
        guard runtimeProvider.isAuthenticated() else { return }
        let ctx = effectiveContext.toWorkspaceContext(
            openFiles: openFilesStore.openFilesForContext(linkedPaths: linkedContextPaths()),
            activeSelection: nil,
            activeFilePath: openFilesStore.openFilePath,
            scopeMode: ContextScopeMode(rawValue: contextScopeModeRaw) ?? .auto
        )
        do {
            try createCheckpointBeforeTurn(conversationId: conversationId, workspaceContext: ctx)
        } catch {
            appendTechnicalErrorMessage(
                "[Errore checkpoint: \(error.localizedDescription)]", in: conversationId)
            flowDiagnosticsStore.setError(error.localizedDescription)
            return
        }
        let imagePathsToStore = attachedImageURLs.map { $0.path }
        inputText = ""
        let contentToStore =
            text.isEmpty ? (attachedImageURLs.isEmpty ? "" : "[Immagine allegata]") : text
        chatStore.addMessage(
            ChatMessage(
                role: .user, content: contentToStore, isStreaming: false,
                imagePaths: imagePathsToStore.isEmpty ? nil : imagePathsToStore), to: conversationId
        )
        chatStore.addMessage(
            ChatMessage(role: .assistant, content: "", isStreaming: true), to: conversationId)
        if let conv = chatStore.conversation(for: conversationId), let ctxId = conv.contextId {
            projectContextStore.setLastActiveConversation(
                contextId: ctxId, folderPath: conv.contextFolderPath, conversationId: conv.id)
        }
        chatStore.beginTask()
        taskActivityStore.clear()
        if providerRegistry.selectedProviderId == "agent-swarm" { swarmProgressStore.clear() }

        let imageURLsToSend = attachedImageURLs.isEmpty ? nil : attachedImageURLs
        attachedImageURLs = []

        var prompt =
            text.isEmpty ? "[L'utente ha allegato un'immagine. Analizzala e rispondi.]" : text
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
                Se vuoi mostrare all'utente il pannello delle attività in corso (modifiche file, comandi, tool MCP), includi: \(CoderIDEMarkers.showTaskPanel)
                Per aggiornare la todo list in modo strutturato usa marker:
                \(CoderIDEMarkers.todoWritePrefix)title=TASK|status=pending|priority=medium|notes=...|files=file1.swift,file2.swift]
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
        }

        Task {
            await MainActor.run { flowDiagnosticsStore.selectedProviderId = runtimeProvider.id }
            do {
                let streamResult = try await flowCoordinator.runStream(
                    provider: runtimeProvider,
                    prompt: prompt,
                    context: ctx,
                    imageURLs: imageURLsToSend,
                    onText: { content in
                        chatStore.updateLastAssistantMessage(content: content, in: conversationId)
                    },
                    onRaw: { t, p, pid in
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
                    },
                    onError: { content in
                        chatStore.updateLastAssistantMessage(content: content, in: conversationId)
                    }
                )
                let full = streamResult.fullText
                let pendingSwarmTask = streamResult.pendingSwarmTask
                chatStore.setLastAssistantStreaming(false, in: conversationId)
                await trySummarizeIfNeeded(ctx: ctx)
                if coderMode == .plan || shouldRunPlanInline {
                    let opts = PlanOptionsParser.parse(from: full)
                    if !opts.isEmpty {
                        await MainActor.run {
                            if coderMode == .plan {
                                planningState = .awaitingChoice(planContent: full, options: opts)
                            }
                            let board = PlanBoard.build(from: full, options: opts)
                            chatStore.setPlanBoard(board, for: conversationId)
                            if shouldRunPlanInline, let cid = conversationId {
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
                if let task = pendingSwarmTask,
                    let swarm = providerRegistry.provider(for: "agent-swarm"),
                    swarm.isAuthenticated()
                {
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
                        },
                        onRaw: { t, p, pid in
                            if t == "coderide_show_task_panel" { taskPanelEnabled = true }
                            if t == "swarm_steps", let s = p["steps"], !s.isEmpty {
                                let n = s.split(separator: ",").map {
                                    String($0).trimmingCharacters(in: .whitespaces)
                                }
                                swarmProgressStore.setSteps(n)
                            }
                            if t == "agent", let ti = p["title"], let de = p["detail"] {
                                if de == "started" {
                                    swarmProgressStore.markStarted(name: ti)
                                } else if de == "completed" {
                                    swarmProgressStore.markCompleted(name: ti)
                                }
                            }
                            recordTaskActivity(type: t, payload: p, providerId: pid)
                        },
                        onFollowUpText: { content in
                            chatStore.updateLastAssistantMessage(
                                content: content, in: conversationId)
                        },
                        onError: { content in
                            chatStore.updateLastAssistantMessage(
                                content: content, in: conversationId)
                        }
                    )
                    chatStore.endTask()
                    await trySummarizeIfNeeded(ctx: ctx)
                }
            } catch {
                chatStore.updateLastAssistantMessage(
                    content: "[Errore: \(error.localizedDescription)]", in: conversationId)
                chatStore.setLastAssistantStreaming(false, in: conversationId)
                await MainActor.run {
                    flowDiagnosticsStore.setError(error.localizedDescription)
                    flowCoordinator.fail()
                }
            }
            chatStore.endTask()
        }
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
        guard message.isStreaming, message.role == .assistant else { return "Writing..." }
        if executionController.runState == .paused {
            return "Paused"
        }
        guard let last = taskActivityStore.activities.last else { return "Thinking..." }
        switch last.phase {
        case .executing:
            return "Executing..."
        case .editing:
            return "Editing files..."
        case .searching:
            return "Searching..."
        case .planning:
            return "Planning..."
        case .thinking:
            return "Thinking..."
        }
    }

    private func streamingDetailText(for message: ChatMessage) -> String? {
        guard message.isStreaming, message.role == .assistant else { return nil }
        guard let last = taskActivityStore.activities.last else { return nil }
        let op = taskActivityStore.activeOperationsCount
        if op > 0 {
            return "\(last.title) · \(op) active ops"
        }
        return last.title
    }
}

// MARK: - Message Row (Cursor-style)

struct MessageRow: View {
    let message: ChatMessage
    let context: ProjectContext?
    let modeColor: Color
    let streamingStatusText: String
    let streamingDetailText: String?
    let onFileClicked: (String) -> Void
    @State private var isHovered = false
    @State private var showCopyButton = false

    private var isUser: Bool { message.role == .user }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Role header
            HStack(spacing: 8) {
                avatar

                Text(isUser ? "You" : assistantLabel)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(isUser ? .primary : modeColor)

                if !isUser && message.isStreaming {
                    StreamingPulse(color: modeColor)
                }

                Spacer()

                if isHovered && !message.content.isEmpty && !message.isStreaming {
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(message.content, forType: .string)
                    } label: {
                        Image(systemName: "doc.on.doc")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                    .transition(.opacity)
                }
            }
            .padding(.bottom, 8)

            // Attached images (user messages)
            if let paths = message.imagePaths, !paths.isEmpty {
                userMessageImagesRow(paths: paths)
                    .padding(.bottom, 8)
            }

            // Message content
            if !message.content.isEmpty {
                if isUser {
                    // User messages: clean plain text, slightly different styling
                    Text(message.content)
                        .font(.system(size: 13))
                        .foregroundStyle(.primary)
                        .lineSpacing(4)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    // Assistant messages: full rich markdown rendering
                    ClickableMessageContent(
                        content: message.content,
                        context: context,
                        onFileClicked: onFileClicked
                    )
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            // Streaming indicator
            if message.isStreaming {
                streamingBar
                    .padding(.top, 8)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(messageBackground)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.12)) {
                isHovered = hovering
            }
        }
    }

    private var assistantLabel: String {
        "Assistant"
    }

    @ViewBuilder
    private var messageBackground: some View {
        if isUser {
            // User messages: subtle tinted background
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(DesignSystem.Colors.userBubble.opacity(0.55))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Color.accentColor.opacity(0.08), lineWidth: 0.5)
                )
        } else if isHovered {
            // Hovered assistant: very subtle highlight
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.primary.opacity(0.02))
        } else {
            Color.clear
        }
    }

    // MARK: - Avatar

    private var avatar: some View {
        Group {
            if isUser {
                ZStack {
                    Circle()
                        .fill(Color.accentColor.opacity(0.12))
                    Image(systemName: "person.fill")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Color.accentColor.opacity(0.7))
                }
                .frame(width: 24, height: 24)
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(modeColor.opacity(0.12))
                    Image(systemName: "sparkles")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(modeColor)
                }
                .frame(width: 24, height: 24)
            }
        }
    }

    // MARK: - Streaming Bar

    private var streamingBar: some View {
        HStack(spacing: 10) {
            // Animated thinking indicator
            HStack(spacing: 6) {
                StreamingDots(color: modeColor)
                Text(streamingStatusText)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            if let detail = streamingDetailText, !detail.isEmpty {
                Text("·")
                    .font(.system(size: 11))
                    .foregroundStyle(.quaternary)

                Text(detail)
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }

            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(modeColor.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(modeColor.opacity(0.08), lineWidth: 0.5)
        )
    }

    // MARK: - Image Attachments

    @ViewBuilder
    private func userMessageImagesRow(paths: [String]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(paths, id: \.self) { path in
                    Group {
                        if FileManager.default.fileExists(atPath: path),
                            let nsImage = NSImage(contentsOf: URL(fileURLWithPath: path))
                        {
                            Image(nsImage: nsImage)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                        } else {
                            Image(systemName: "photo")
                                .font(.system(size: 20))
                                .foregroundStyle(.quaternary)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                    }
                    .frame(width: 72, height: 72)
                    .background(Color(nsColor: .controlBackgroundColor).opacity(0.4))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5)
                    )
                }
            }
        }
    }
}

// MARK: - Streaming Dots (refined)

struct StreamingDots: View {
    let color: Color
    @State private var phase: Int = 0
    @State private var timer: Timer?

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .fill(color)
                    .frame(width: 4, height: 4)
                    .opacity(dotOpacity(for: i))
                    .scaleEffect(dotScale(for: i))
            }
        }
        .onAppear {
            timer?.invalidate()
            timer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: true) { _ in
                withAnimation(.easeInOut(duration: 0.3)) {
                    phase = (phase + 1) % 3
                }
            }
        }
        .onDisappear {
            timer?.invalidate()
            timer = nil
        }
    }

    private func dotOpacity(for index: Int) -> Double {
        phase == index ? 1.0 : 0.2
    }

    private func dotScale(for index: Int) -> CGFloat {
        phase == index ? 1.15 : 0.85
    }
}

// MARK: - Streaming Pulse (header indicator)

struct StreamingPulse: View {
    let color: Color
    @State private var isAnimating = false

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 6, height: 6)
            .opacity(isAnimating ? 1.0 : 0.25)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true)) {
                    isAnimating = true
                }
            }
    }
}

// MARK: - Backward compat aliases
typealias MessageBubbleView = MessageRow

struct TypingIndicator: View {
    @State private var dot = 0
    @State private var timer: Timer?
    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<3, id: \.self) { i in
                Circle().fill(Color.secondary).frame(width: 4, height: 4).opacity(
                    dot == i ? 1 : 0.3)
            }
        }
        .onAppear {
            timer?.invalidate()
            timer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: true) { _ in
                withAnimation { dot = (dot + 1) % 3 }
            }
        }
        .onDisappear {
            timer?.invalidate()
            timer = nil
        }
    }
}
