import SwiftUI
import AppKit
import CoderEngine
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

struct ChatPanelView: View {
    @EnvironmentObject var providerRegistry: ProviderRegistry
    @EnvironmentObject var chatStore: ChatStore
    @EnvironmentObject var openFilesStore: OpenFilesStore
    @EnvironmentObject var taskActivityStore: TaskActivityStore
    @EnvironmentObject var todoStore: TodoStore
    @EnvironmentObject var swarmProgressStore: SwarmProgressStore
    @EnvironmentObject var executionController: ExecutionController
    @EnvironmentObject var providerUsageStore: ProviderUsageStore
    @EnvironmentObject var flowDiagnosticsStore: FlowDiagnosticsStore
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
    @AppStorage("swarm_enabled_roles") private var swarmEnabledRoles = "planner,coder,debugger,reviewer,testWriter"
    @AppStorage("agent_auto_delegate_swarm") private var agentAutoDelegateSwarm = true
    @AppStorage("global_yolo") private var globalYolo = false
    @AppStorage("code_review_partitions") private var codeReviewPartitions = 3
    @AppStorage("code_review_analysis_only") private var codeReviewAnalysisOnly = false
    @AppStorage("code_review_max_rounds") private var codeReviewMaxRounds = 3
    @AppStorage("code_review_analysis_backend") private var codeReviewAnalysisBackend = "codex"
    @AppStorage("openai_api_key") private var openaiApiKey = ""
    @AppStorage("openai_model") private var openaiModel = "gpt-4o-mini"
    @State private var codexModels: [CodexModel] = []
    @State private var showSwarmHelp = false
    @AppStorage("task_panel_enabled") private var taskPanelEnabled = false
    @AppStorage("plan_mode_backend") private var planModeBackend = "codex"
    @AppStorage("claude_path") private var claudePath = ""
    @AppStorage("claude_model") private var claudeModel = "sonnet"
    @AppStorage("summarize_threshold") private var summarizeThreshold = 0.8
    @AppStorage("summarize_keep_last") private var summarizeKeepLast = 6
    @AppStorage("summarize_provider") private var summarizeProvider = "openai-api"
    @State private var planningState: PlanningState = .idle
    @State private var isProviderReady = false
    @State private var attachedImageURLs: [URL] = []
    @State private var isSelectingImage = false
    @State private var isComposerDropTargeted = false
    @State private var isConvertingHeic = false
    @State private var pasteMonitor: Any?
    @State private var isSummarizing = false
    @StateObject private var flowCoordinator = ConversationFlowCoordinator()
    @AppStorage("flow_diagnostics_enabled") private var flowDiagnosticsEnabled = false

    private static let imagePastedNotification = Notification.Name("CoderIDE.ImagePasted")

    private var activeModeColor: Color { modeColor(for: coderMode) }
    private var activeModeGradient: LinearGradient { modeGradient(for: coderMode) }

    var body: some View {
        VStack(spacing: 0) {
            modeTabBar
            separator

            if coderMode == .agentSwarm && !swarmProgressStore.steps.isEmpty {
                SwarmProgressView(store: swarmProgressStore)
            }

            messagesArea

            composerArea
        }
        .onChange(of: providerRegistry.selectedProviderId) { _, newId in syncCoderModeToProvider(newId); checkProviderAuth() }
        .onChange(of: selectedConversationId) { _, _ in syncProviderFromConversation() }
        .onAppear {
            syncProviderFromConversation()
            codexModels = CodexModelsCache.loadModels()
            syncSwarmProvider(); syncMultiSwarmReviewProvider(); syncPlanProvider()
            checkProviderAuth()
        }
        .onChange(of: swarmOrchestrator) { _, _ in syncSwarmProvider() }
        .onChange(of: swarmWorkerBackend) { _, _ in syncSwarmProvider() }
        .onChange(of: swarmAutoPostCodePipeline) { _, _ in syncSwarmProvider() }
        .onChange(of: swarmMaxPostCodeRetries) { _, _ in syncSwarmProvider() }
        .onChange(of: globalYolo) { _, _ in syncCodexProvider(); syncMultiSwarmReviewProvider(); syncPlanProvider() }
        .onChange(of: codeReviewPartitions) { _, _ in syncMultiSwarmReviewProvider() }
        .onChange(of: codeReviewAnalysisOnly) { _, _ in syncMultiSwarmReviewProvider() }
        .onChange(of: codeReviewAnalysisBackend) { _, _ in syncMultiSwarmReviewProvider() }
        .sheet(isPresented: $showSwarmHelp) { AgentSwarmHelpView() }
        .fileImporter(isPresented: $isSelectingImage, allowedContentTypes: [.image, .png, .jpeg, .gif, .heic], allowsMultipleSelection: true) { result in
            handleImageSelection(result: result)
        }
        .onAppear {
            installPasteMonitor()
        }
        .onDisappear {
            removePasteMonitor()
        }
        .onReceive(NotificationCenter.default.publisher(for: Self.imagePastedNotification)) { notification in
            if let url = notification.userInfo?["url"] as? URL {
                attachedImageURLs.append(url)
            }
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
                let valid = urls.compactMap { ImageAttachmentHelper.normalizeToPngIfNeeded(url: $0) }
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
            guard event.modifierFlags.contains(.command), event.charactersIgnoringModifiers == "v" else {
                return event
            }
            if let url = ImageAttachmentHelper.imageURLFromPasteboard() {
                DispatchQueue.main.async {
                    NotificationCenter.default.post(name: Self.imagePastedNotification, object: nil, userInfo: ["url": url])
                }
                return nil
            }
            return event
        }
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

    // MARK: - Mode Tab Bar
    private var modeTabBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 3) {
                ForEach(CoderMode.allCases, id: \.self) { mode in
                    modeTabButton(for: mode)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
    }

    @ViewBuilder
    private func modeTabButton(for mode: CoderMode) -> some View {
        let isSelected = coderMode == mode
        let color = modeColor(for: mode)
        let gradient = modeGradient(for: mode)
        Button {
            withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
                self.selectMode(mode)
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: modeIcon(for: mode))
                    .font(.system(size: 10, weight: .semibold))
                Text(mode.rawValue)
                    .font(.system(size: 11.5, weight: isSelected ? .semibold : .medium))
            }
            .foregroundStyle(isSelected ? .white : .secondary)
            .padding(.horizontal, 11)
            .padding(.vertical, 5.5)
            .background {
                if isSelected {
                    Capsule()
                        .fill(gradient)
                        .shadow(color: color.opacity(0.35), radius: 8, y: 2)
                }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
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
                                workspacePath: effectiveContext.primaryPath ?? "",
                                modeColor: activeModeColor,
                                onFileClicked: { openFilesStore.openFile($0) }
                            )
                            .id(message.id)
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
                        if chatStore.isLoading || (!taskActivityStore.activities.isEmpty && taskPanelEnabled) {
                            chatInlineTaskStatus
                                .id("chat-task-status")
                        }
                        if flowDiagnosticsEnabled {
                            flowDiagnosticsCard
                                .padding(.horizontal, 16)
                                .padding(.bottom, 8)
                        }
                    }
                }
                .padding(.top, 8).padding(.bottom, 16)
            }
            .onChange(of: chatStore.conversation(for: conversationId)?.messages.last?.content ?? "") { _, _ in
                if let last = chatStore.conversation(for: conversationId)?.messages.last {
                    withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(last.id, anchor: .bottom) }
                }
            }
            .onChange(of: planningState) { _, new in
                if case .awaitingChoice = new {
                    withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo("plan-options", anchor: .bottom) }
                }
            }
            .onChange(of: chatStore.isLoading) { _, loading in
                if loading { withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo("chat-task-status", anchor: .bottom) } }
            }
            .onChange(of: taskActivityStore.activities.count) { _, _ in
                if chatStore.isLoading { withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo("chat-task-status", anchor: .bottom) } }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var chatInlineTaskStatus: some View {
        VStack(alignment: .leading, spacing: 8) {
            if chatStore.isLoading, let startDate = chatStore.taskStartDate {
                TimelineView(.periodic(from: startDate, by: 1.0)) { context in
                    let elapsed = Int(context.date.timeIntervalSince(startDate))
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("Task in esecuzione")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)
                        Text(formatElapsed(elapsed))
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            .foregroundStyle(DesignSystem.Colors.warning)
                        Spacer()
                        Button {
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
                            if let cid = conversationId {
                                let cur = chatStore.conversation(for: cid)?.messages.last(where: { $0.role == .assistant })?.content ?? ""
                                chatStore.updateLastAssistantMessage(content: cur.isEmpty ? "[Interrotto dall'utente]" : cur + "\n\n[Interrotto dall'utente]", in: cid)
                                chatStore.setLastAssistantStreaming(false, in: cid)
                            }
                            chatStore.endTask()
                        } label: {
                            Text("Ferma")
                                .font(.system(size: 11, weight: .medium))
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.red)
                        .controlSize(.small)
                    }
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(DesignSystem.Colors.warning.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
                }
            }
            if isSummarizing {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Compressione contesto…")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(DesignSystem.Colors.info.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
            }
            if taskPanelEnabled && !taskActivityStore.activities.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ChatTerminalSessionsView(activities: taskActivityStore.activities)
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
                    TodoLiveInlineCard(store: todoStore, onOpenFile: { path in
                        openFilesStore.openFile(path)
                    })

                    ForEach(taskActivityStore.activities
                        .filter { $0.type != "command_execution" && $0.type != "bash" }
                        .suffix(8)) { activity in
                            TaskActivityRow(activity: activity)
                    }
                }
                .padding(10)
                .background(Color(nsColor: .controlBackgroundColor).opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 8)
    }

    private func formatElapsed(_ s: Int) -> String {
        let m = s / 60; let sec = s % 60
        return m > 0 ? String(format: "%d:%02d", m, sec) : "\(sec)s"
    }

    @MainActor
    private func recordTaskActivity(type: String, payload: [String: String], providerId: String) {
        let envelope = flowCoordinator.normalizeRawEvent(providerId: providerId, type: type, payload: payload)
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
                let shouldAutoShow = activity.type == "command_execution" || activity.type == "bash"
                if shouldAutoShow {
                    taskPanelEnabled = true
                }
                if taskPanelEnabled || shouldAutoShow {
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
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.45), in: RoundedRectangle(cornerRadius: 8))
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
        case "codex-cli": return "Codex CLI non connesso. Configuralo nelle Impostazioni → Codex CLI."
        case "claude-cli": return "Claude Code non trovato. Configuralo nelle Impostazioni → Claude Code."
        case "agent-swarm": return "Agent Swarm non configurato. Verifica provider nelle Impostazioni."
        case "plan-mode": return "Backend Plan Mode non disponibile. Verifica Codex o Claude nelle Impostazioni."
        case "multi-swarm-review": return "Code Review non configurato. Verifica Codex nelle Impostazioni."
        case "openrouter-api": return "API Key OpenRouter mancante. Configurala nelle Impostazioni."
        case "minimax-api": return "API Key MiniMax mancante. Configurala nelle Impostazioni."
        default: return "Provider \"\(id)\" non autenticato. Vai nelle Impostazioni per configurare."
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
                    isComposerDropTargeted ? activeModeColor.opacity(0.6) : (isInputFocused ? activeModeColor.opacity(0.4) : DesignSystem.Colors.border),
                    lineWidth: isComposerDropTargeted ? 2 : (isInputFocused ? 1.2 : 0.5)
                )
        )
        .shadow(color: isInputFocused ? activeModeColor.opacity(0.1) : .clear, radius: 12, y: 2)
        .shadow(color: .black.opacity(0.12), radius: 4, y: 2)
        .animation(.easeOut(duration: 0.2), value: isInputFocused)
        .onDrop(of: [.image, .fileURL, .png, .jpeg, .gif], isTargeted: $isComposerDropTargeted) { providers in
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
        let canSend = (!inputText.isEmpty || !attachedImageURLs.isEmpty) && !chatStore.isLoading && !awaitingChoice && isProviderReady
        return Button(action: sendMessage) {
            Image(systemName: "arrow.up")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background {
                    Circle().fill(canSend ? activeModeGradient : LinearGradient(colors: [DesignSystem.Colors.borderAccent], startPoint: .top, endPoint: .bottom))
                }
                .shadow(color: canSend ? activeModeColor.opacity(0.3) : .clear, radius: 6, y: 2)
        }
        .buttonStyle(.plain).disabled(!canSend)
        .animation(.easeOut(duration: 0.15), value: canSend)
    }

    /// Provider effettivo (Codex CLI o Claude CLI) usato dall’agent in base a plan-mode, agent-swarm, multi-swarm-review
    private var effectiveAgentProviderLabel: String? {
        guard [.agent, .agentSwarm, .codeReviewMultiSwarm, .plan].contains(coderMode) else { return nil }
        switch providerRegistry.selectedProviderId {
        case "codex-cli": return "Codex CLI"
        case "claude-cli": return "Claude CLI"
        case "plan-mode": return planModeBackend == "claude" ? "Claude CLI" : "Codex CLI"
        case "agent-swarm": return swarmWorkerBackend == "claude" ? "Claude CLI" : "Codex CLI"
        case "multi-swarm-review": return codeReviewAnalysisBackend == "claude" ? "Claude CLI" : "Codex CLI"
        default: return nil
        }
    }

    private var controlsBar: some View {
        HStack(spacing: 6) {
            providerPicker
            if let agentLabel = effectiveAgentProviderLabel {
                Text(agentLabel)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.primary.opacity(0.06))
                    .clipShape(Capsule())
            }
            if providerRegistry.selectedProviderId == "codex-cli" {
                codexModelPicker; codexReasoningPicker; accessLevelMenu
                if coderMode == .agent || coderMode == .agentSwarm { formicaButton }
            } else if providerRegistry.selectedProviderId == "claude-cli" {
                if coderMode == .agent || coderMode == .agentSwarm { formicaButton }
            } else if providerRegistry.selectedProviderId == "agent-swarm" {
                swarmOrchestratorPicker
                Button { showSwarmHelp = true } label: {
                    Image(systemName: "questionmark.circle").font(.caption).foregroundStyle(DesignSystem.Colors.swarmColor)
                }.buttonStyle(.plain)
                if coderMode == .agent || coderMode == .agentSwarm { formicaButton }
            } else if providerRegistry.selectedProviderId == "plan-mode" {
                Spacer()
                if coderMode == .plan { formicaButton }
            } else if [.agent, .agentSwarm, .plan].contains(coderMode) {
                Spacer(); formicaButton
            } else if coderMode == .ide {
                Spacer(); delegaAdAgentButton
            } else { Spacer() }
        }
    }

    private var delegaAdAgentButton: some View {
        let msg = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        let lastUser = chatStore.conversation(for: conversationId)?.messages.last(where: { $0.role == .user })?.content ?? ""
        let canDelegate = (!msg.isEmpty || !lastUser.isEmpty || !attachedImageURLs.isEmpty) && !chatStore.isLoading
        let agentOk = (providerRegistry.provider(for: "codex-cli")?.isAuthenticated() == true) || (providerRegistry.provider(for: "claude-cli")?.isAuthenticated() == true)
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
        case .codeReviewMultiSwarm: return "Stai usando Code Review Multi-Swarm: la richiesta verrà suddivisa in partizioni."
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
                } label: {
                    HStack { Text(provider.displayName); if providerRegistry.selectedProviderId == provider.id { Image(systemName: "checkmark") } }
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
           let p = providerRegistry.providers.first(where: { $0.id == id }) { return p.displayName }
        return "Seleziona provider"
    }

    private var codexModelPicker: some View {
        Menu {
            Button { codexModelOverride = ""; syncCodexProvider() } label: {
                HStack { Text("Default (da config)"); if codexModelOverride.isEmpty { Image(systemName: "checkmark") } }
            }
            if !codexModels.isEmpty { Divider()
                ForEach(codexModels, id: \.slug) { m in
                    Button { codexModelOverride = m.slug; syncCodexProvider() } label: {
                        HStack { Text(m.displayName); if codexModelOverride == m.slug { Image(systemName: "checkmark") } }
                    }
                }
            }
        } label: {
            HStack(spacing: 4) { Text(codexModelLabel).font(.caption); Image(systemName: "chevron.down").font(.system(size: 8, weight: .bold)) }.foregroundStyle(.secondary)
        }.menuStyle(.borderlessButton).fixedSize()
    }

    private var codexModelLabel: String {
        codexModelOverride.isEmpty ? "Default" : (codexModels.first(where: { $0.slug == codexModelOverride })?.displayName ?? codexModelOverride)
    }

    private var codexReasoningPicker: some View {
        Menu {
            ForEach(["low", "medium", "high", "xhigh"], id: \.self) { e in
                Button { codexReasoningEffort = e; syncCodexProvider() } label: {
                    HStack { Text(reasoningEffortDisplay(e)); if codexReasoningEffort == e { Image(systemName: "checkmark") } }
                }
            }
        } label: {
            HStack(spacing: 4) { Text(reasoningEffortDisplay(codexReasoningEffort)).font(.caption); Image(systemName: "chevron.down").font(.system(size: 8, weight: .bold)) }.foregroundStyle(.secondary)
        }.menuStyle(.borderlessButton).fixedSize()
    }

    private func reasoningEffortDisplay(_ e: String) -> String {
        switch e.lowercased() { case "low": return "Low"; case "medium": return "Medium"; case "high": return "High"; case "xhigh": return "XHigh"; default: return e }
    }

    private var effectiveSandbox: String {
        codexSandbox.isEmpty ? (CodexConfigLoader.load().sandboxMode ?? "workspace-write") : codexSandbox
    }

    private var accessLevelMenu: some View {
        let cfg = CodexConfigLoader.load()
        return Menu {
            Button { codexSandbox = ""; syncCodexProvider() } label: {
                HStack { Label("Default (da config)", systemImage: "doc.badge.gearshape"); if codexSandbox.isEmpty { Image(systemName: "checkmark") } }
            }
            if cfg.sandboxMode != nil { Text("Config: \(accessLevelLabel(for: cfg.sandboxMode ?? ""))").font(.caption2).foregroundStyle(.secondary) }
            Divider()
            Button { codexSandbox = "read-only"; syncCodexProvider() } label: { Label("Read Only", systemImage: "lock.shield") }
            Button { codexSandbox = "workspace-write"; syncCodexProvider() } label: { Label("Default", systemImage: "shield") }
            Button { codexSandbox = "danger-full-access"; syncCodexProvider() } label: { Label("Full Access", systemImage: "exclamationmark.shield.fill") }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: accessLevelIcon(for: effectiveSandbox)).font(.caption)
                Text(accessLevelLabel(for: effectiveSandbox)).font(.caption)
                Image(systemName: "chevron.down").font(.system(size: 8, weight: .bold))
            }.foregroundStyle(effectiveSandbox == "danger-full-access" ? DesignSystem.Colors.error : .secondary)
        }.menuStyle(.borderlessButton).fixedSize()
    }

    private var swarmOrchestratorPicker: some View {
        Menu {
            Button { swarmOrchestrator = "openai"; syncSwarmProvider() } label: { HStack { Text("OpenAI"); if swarmOrchestrator == "openai" { Image(systemName: "checkmark") } } }
            Button { swarmOrchestrator = "codex"; syncSwarmProvider() } label: { HStack { Text("Codex"); if swarmOrchestrator == "codex" { Image(systemName: "checkmark") } } }
            Button { swarmOrchestrator = "claude"; syncSwarmProvider() } label: { HStack { Text("Claude"); if swarmOrchestrator == "claude" { Image(systemName: "checkmark") } } }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "ant.fill").font(.caption2)
                let orchLabel: String = { switch swarmOrchestrator { case "codex": return "Codex"; case "claude": return "Claude"; default: return "OpenAI" } }()
                Text("Orchestrator: \(orchLabel)").font(.caption)
                Image(systemName: "chevron.down").font(.system(size: 8, weight: .bold))
            }.foregroundStyle(.secondary)
        }.menuStyle(.borderlessButton).fixedSize()
    }

    private var formicaButton: some View {
        Button { taskPanelEnabled.toggle() } label: {
            Image(systemName: "ant.fill").font(.caption)
                .foregroundStyle(taskPanelEnabled ? DesignSystem.Colors.swarmColor : .secondary)
        }.buttonStyle(.plain).help("Task Activity Panel")
    }

    private func accessLevelIcon(for s: String) -> String {
        switch s { case "read-only": return "lock.shield"; case "danger-full-access": return "exclamationmark.shield.fill"; default: return "shield" }
    }
    private func accessLevelLabel(for s: String) -> String {
        switch s { case "read-only": return "Read Only"; case "danger-full-access": return "Full Access"; default: return "Default" }
    }
    private func selectMode(_ mode: CoderMode) {
        let currentConv = chatStore.conversation(for: selectedConversationId)
        let workspaceId = currentConv?.workspaceId
        let adHocPaths = currentConv?.adHocFolderPaths ?? []

        let newConvId = chatStore.getOrCreateConversationForMode(workspaceId: workspaceId, mode: mode, adHocFolderPaths: adHocPaths)
        selectedConversationId = newConvId

        switch mode {
        case .ide: providerRegistry.selectedProviderId = ProviderSupport.preferredIDEProvider(in: providerRegistry)
        case .agent: providerRegistry.selectedProviderId = "codex-cli"
        case .agentSwarm: providerRegistry.selectedProviderId = "agent-swarm"
        case .codeReviewMultiSwarm: providerRegistry.selectedProviderId = "multi-swarm-review"
        case .plan: providerRegistry.selectedProviderId = "plan-mode"; planningState = .idle
        case .mcpServer: providerRegistry.selectedProviderId = "claude-cli"
        }
        coderMode = mode
    }

    private func modeColor(for m: CoderMode) -> Color {
        switch m {
        case .agent: return DesignSystem.Colors.agentColor; case .agentSwarm: return DesignSystem.Colors.swarmColor
        case .codeReviewMultiSwarm: return DesignSystem.Colors.reviewColor; case .plan: return DesignSystem.Colors.planColor
        case .ide: return DesignSystem.Colors.ideColor; case .mcpServer: return DesignSystem.Colors.mcpColor
        }
    }
    private func modeIcon(for m: CoderMode) -> String {
        switch m {
        case .agent: return "brain.head.profile"; case .agentSwarm: return "ant.fill"
        case .codeReviewMultiSwarm: return "doc.text.magnifyingglass"; case .plan: return "list.bullet.rectangle"
        case .ide: return "sparkles"; case .mcpServer: return "server.rack"
        }
    }
    private func modeGradient(for m: CoderMode) -> LinearGradient {
        switch m {
        case .agent: return DesignSystem.Colors.agentGradient; case .agentSwarm: return DesignSystem.Colors.swarmGradient
        case .codeReviewMultiSwarm: return DesignSystem.Colors.reviewGradient; case .plan: return DesignSystem.Colors.planGradient
        case .ide: return DesignSystem.Colors.ideGradient; case .mcpServer: return DesignSystem.Colors.mcpGradient
        }
    }

    // MARK: - Provider Sync

    private func checkProviderAuth() {
        let provider = providerRegistry.selectedProvider
        Task.detached {
            let ready = provider?.isAuthenticated() ?? false
            await MainActor.run { isProviderReady = ready }
        }
    }

    private func syncCodexProvider() {
        let p = ProviderFactory.codexProvider(config: providerFactoryConfig(), executionController: executionController)
        providerRegistry.unregister(id: "codex-cli"); providerRegistry.register(p); syncSwarmProvider(); syncPlanProvider()
        checkProviderAuth()
        persistCodexConfigToToml()
    }

    private func persistCodexConfigToToml() {
        var cfg = CodexConfigLoader.load()
        cfg.sandboxMode = codexSandbox.isEmpty ? nil : codexSandbox
        cfg.model = codexModelOverride.isEmpty ? nil : codexModelOverride
        cfg.modelReasoningEffort = codexReasoningEffort.isEmpty ? nil : codexReasoningEffort
        CodexConfigLoader.save(cfg)
    }
    private func syncSwarmProvider() {
        guard let codex = providerRegistry.provider(for: "codex-cli") as? CodexCLIProvider else { return }
        let claude = providerRegistry.provider(for: "claude-cli") as? ClaudeCLIProvider
        providerRegistry.unregister(id: "agent-swarm")
        providerRegistry.register(ProviderFactory.swarmProvider(config: providerFactoryConfig(), codex: codex, claude: claude, executionController: executionController))
        checkProviderAuth()
    }
    private func syncMultiSwarmReviewProvider() {
        guard let codex = providerRegistry.provider(for: "codex-cli") as? CodexCLIProvider else { return }
        let claude = providerRegistry.provider(for: "claude-cli") as? ClaudeCLIProvider
        providerRegistry.unregister(id: "multi-swarm-review")
        providerRegistry.register(ProviderFactory.codeReviewProvider(config: providerFactoryConfig(), codex: codex, claude: claude))
        checkProviderAuth()
    }
    private func syncProviderFromConversation() {
        guard let conv = chatStore.conversation(for: selectedConversationId), let mode = conv.mode else {
            syncCoderModeToProvider(providerRegistry.selectedProviderId)
            return
        }
        coderMode = mode
        planningState = .idle
        switch mode {
        case .ide: providerRegistry.selectedProviderId = ProviderSupport.preferredIDEProvider(in: providerRegistry)
        case .agent: providerRegistry.selectedProviderId = "codex-cli"
        case .agentSwarm: providerRegistry.selectedProviderId = "agent-swarm"
        case .codeReviewMultiSwarm: providerRegistry.selectedProviderId = "multi-swarm-review"
        case .plan: providerRegistry.selectedProviderId = "plan-mode"
        case .mcpServer: providerRegistry.selectedProviderId = "claude-cli"
        }
        checkProviderAuth()
    }

    private func syncCoderModeToProvider(_ pid: String?) {
        guard let id = pid else { return }
        if ProviderSupport.isIDEProvider(id: id) {
            coderMode = .ide
            planningState = .idle
            return
        }
        switch id {
        case "agent-swarm": coderMode = .agentSwarm; planningState = .idle
        case "multi-swarm-review": coderMode = .codeReviewMultiSwarm; planningState = .idle
        case "plan-mode": coderMode = .plan
        case "codex-cli", "claude-cli": coderMode = .agent; planningState = .idle
        default: break
        }
    }
    private func syncPlanProvider() {
        let codex = providerRegistry.provider(for: "codex-cli") as? CodexCLIProvider
        let claude = providerRegistry.provider(for: "claude-cli") as? ClaudeCLIProvider
        guard codex != nil || claude != nil else { return }
        providerRegistry.unregister(id: "plan-mode")
        providerRegistry.register(ProviderFactory.planProvider(config: providerFactoryConfig(), codex: codex, claude: claude, executionController: executionController))
    }

    private func providerFactoryConfig() -> ProviderFactoryConfig {
        ProviderFactoryConfig(
            openaiApiKey: openaiApiKey,
            openaiModel: openaiModel,
            anthropicApiKey: "",
            anthropicModel: "",
            googleApiKey: "",
            googleModel: "",
            minimaxApiKey: "",
            minimaxModel: "",
            openrouterApiKey: "",
            openrouterModel: "",
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
            claudePath: claudePath,
            claudeModel: claudeModel,
            claudeAllowedTools: ["Read", "Edit", "Bash", "Write", "Search"]
        )
    }

    private func trySummarizeIfNeeded(ctx: WorkspaceContext) async {
        // Con Codex CLI preferiamo il compact nativo del provider rispetto al riassunto custom.
        if summarizeProvider == "codex-cli" {
            return
        }
        guard let conv = chatStore.conversation(for: conversationId) else { return }
        let ctxPrompt = ctx.contextPrompt()
        let size = ContextEstimator.contextSize(for: providerRegistry.selectedProviderId, model: openaiModel)
        let (_, _, pct) = ContextEstimator.estimate(messages: conv.messages, contextPrompt: ctxPrompt, modelContextSize: size)
        guard pct >= summarizeThreshold else { return }
        guard let prov = providerRegistry.provider(for: summarizeProvider), prov.isAuthenticated() else {
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
            _ = try await chatStore.summarizeConversation(id: conversationId, keepLast: summarizeKeepLast, provider: provider, context: ctx)
        } catch {
            // Non bloccare su errore
        }
    }

    // MARK: - Delega ad Agent (da IDE)
    private func delegateToAgent() {
        var msg = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        if msg.isEmpty {
            msg = chatStore.conversation(for: conversationId)?.messages.last(where: { $0.role == .user })?.content ?? ""
        }
        guard !msg.isEmpty || !attachedImageURLs.isEmpty else { return }
        let codex = providerRegistry.provider(for: "codex-cli")
        let claude = providerRegistry.provider(for: "claude-cli")
        let agentProvider: (any LLMProvider)? = codex?.isAuthenticated() == true ? codex : (claude?.isAuthenticated() == true ? claude : nil)
        guard let agentProvider else { return }

        let currentConv = chatStore.conversation(for: conversationId)
        let workspaceId = currentConv?.workspaceId
        let adHocPaths = currentConv?.adHocFolderPaths ?? []
        let agentConvId = chatStore.getOrCreateConversationForMode(workspaceId: workspaceId, mode: .agent, adHocFolderPaths: adHocPaths)

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
        if useClaude { guard let c = providerRegistry.provider(for: "claude-cli") as? ClaudeCLIProvider else { return }; provider = c }
        else { guard let c = providerRegistry.provider(for: "codex-cli") as? CodexCLIProvider else { return }; provider = c }

        planningState = .idle
        chatStore.choosePlanPath(choice, for: conversationId)
        chatStore.updatePlanStepStatus(stepId: "1", status: .running, in: conversationId)
        let currentConv = chatStore.conversation(for: conversationId)
        let workspaceId = currentConv?.workspaceId
        let adHocPaths = currentConv?.adHocFolderPaths ?? []
        let agentConvId = chatStore.getOrCreateConversationForMode(workspaceId: workspaceId, mode: .agent, adHocFolderPaths: adHocPaths)
        selectedConversationId = agentConvId
        providerRegistry.selectedProviderId = planModeBackend == "claude" ? "claude-cli" : "codex-cli"
        coderMode = .agent

        chatStore.addMessage(ChatMessage(role: .user, content: "Procedi con: \(choice)", isStreaming: false), to: agentConvId)
        chatStore.addMessage(ChatMessage(role: .assistant, content: "", isStreaming: true), to: agentConvId)
        chatStore.beginTask(); if taskPanelEnabled { taskActivityStore.clear() }

        let prompt = "L'utente ha scelto il seguente approccio dal piano precedentemente proposto. Implementalo.\n\nPiano di riferimento:\n\(planContent)\n\nScelta dell'utente:\n\(choice)"
        let ctx = effectiveContext.toWorkspaceContext(
            openFiles: openFilesStore.openFilesForContext(linkedPaths: linkedContextPaths()),
            activeSelection: nil,
            activeFilePath: openFilesStore.openFilePath
        )

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
                chatStore.updateLastAssistantMessage(content: "[Errore: \(error.localizedDescription)]", in: agentConvId)
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
        guard !text.isEmpty || !attachedImageURLs.isEmpty, let provider = providerRegistry.selectedProvider, provider.isAuthenticated() else { return }
        let imagePathsToStore = attachedImageURLs.map { $0.path }
        inputText = ""
        let contentToStore = text.isEmpty ? (attachedImageURLs.isEmpty ? "" : "[Immagine allegata]") : text
        chatStore.addMessage(ChatMessage(role: .user, content: contentToStore, isStreaming: false, imagePaths: imagePathsToStore.isEmpty ? nil : imagePathsToStore), to: conversationId)
        chatStore.addMessage(ChatMessage(role: .assistant, content: "", isStreaming: true), to: conversationId)
        chatStore.beginTask(); if taskPanelEnabled { taskActivityStore.clear() }
        if providerRegistry.selectedProviderId == "agent-swarm" { swarmProgressStore.clear() }

        let ctx = effectiveContext.toWorkspaceContext(
            openFiles: openFilesStore.openFilesForContext(linkedPaths: linkedContextPaths()),
            activeSelection: nil,
            activeFilePath: openFilesStore.openFilePath
        )
        let imageURLsToSend = attachedImageURLs.isEmpty ? nil : attachedImageURLs
        attachedImageURLs = []

        var prompt = text.isEmpty ? "[L'utente ha allegato un'immagine. Analizzala e rispondi.]" : text
        if coderMode == .ide { prompt = "Rispondi solo con testo. Non modificare file né eseguire comandi.\n\n" + prompt }
        if coderMode == .mcpServer { prompt = "[MCP Server] " + prompt }
        if providerRegistry.selectedProviderId == "codex-cli" || providerRegistry.selectedProviderId == "claude-cli" {
            let baseInstructions = """
            Se vuoi mostrare all'utente il pannello delle attività in corso (modifiche file, comandi, tool MCP), includi: \(CoderIDEMarkers.showTaskPanel)
            Per aggiornare la todo list in modo strutturato usa marker:
            \(CoderIDEMarkers.todoWritePrefix)title=TASK|status=pending|priority=medium|notes=...|files=file1.swift,file2.swift]
            Per aggiornare step del piano usa marker:
            \(CoderIDEMarkers.planStepPrefix)step_id=1|status=running]
            Se fai ricerche codice con rg, puoi emettere marker con risultati:
            \(CoderIDEMarkers.instantGrepPrefix)query=foo|pathScope=Sources|matchesCount=3|previewLines=Sources/A.swift:12:linea]
            """
            if agentAutoDelegateSwarm {
                let swarmInstructions = "Per task complessi che richiedono planner, coder, reviewer, ecc., delega allo swarm scrivendo: \(CoderIDEMarkers.invokeSwarmPrefix)DESCRIZIONE_TASK\(CoderIDEMarkers.invokeSwarmSuffix)\n\n"
                prompt = baseInstructions + swarmInstructions + prompt
            } else {
                prompt = baseInstructions + "\n" + prompt
            }
        }

        Task {
            await MainActor.run { flowDiagnosticsStore.selectedProviderId = provider.id }
            do {
                let streamResult = try await flowCoordinator.runStream(
                    provider: provider,
                    prompt: prompt,
                    context: ctx,
                    imageURLs: imageURLsToSend,
                    onText: { content in
                        chatStore.updateLastAssistantMessage(content: content, in: conversationId)
                    },
                    onRaw: { t, p, pid in
                        if t == "coderide_show_task_panel" { taskPanelEnabled = true }
                        if t == "swarm_steps", let s = p["steps"], !s.isEmpty {
                            let n = s.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespaces) }
                            swarmProgressStore.setSteps(n)
                        }
                        if t == "agent", let title = p["title"], let detail = p["detail"] {
                            if detail == "started" { swarmProgressStore.markStarted(name: title) }
                            else if detail == "completed" { swarmProgressStore.markCompleted(name: title) }
                        }
                        if t == "usage", let selectedId = providerRegistry.selectedProviderId, selectedId.hasSuffix("-api"),
                           let inpStr = p["input_tokens"], let outStr = p["output_tokens"],
                           let inp = Int(inpStr), let out = Int(outStr) {
                            providerUsageStore.addApiUsage(inputTokens: inp, outputTokens: out, model: p["model"] ?? "gpt-4o-mini")
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
                if coderMode == .plan { let opts = PlanOptionsParser.parse(from: full); if !opts.isEmpty { await MainActor.run { planningState = .awaitingChoice(planContent: full, options: opts) } } }
                if coderMode == .plan {
                    let opts = PlanOptionsParser.parse(from: full)
                    if !opts.isEmpty {
                        await MainActor.run {
                            let board = PlanBoard.build(from: full, options: opts)
                            chatStore.setPlanBoard(board, for: conversationId)
                        }
                    }
                }
                else if let task = pendingSwarmTask, let swarm = providerRegistry.provider(for: "agent-swarm"), swarm.isAuthenticated() {
                    let agentProviderIdBeforeSwarm = providerRegistry.selectedProviderId
                    await MainActor.run { providerRegistry.selectedProviderId = "agent-swarm"; coderMode = .agentSwarm }
                    chatStore.addMessage(ChatMessage(role: .user, content: "[Delegato allo swarm] \(task)", isStreaming: false), to: conversationId)
                    chatStore.addMessage(ChatMessage(role: .assistant, content: "", isStreaming: true), to: conversationId)
                    chatStore.beginTask(); if taskPanelEnabled { taskActivityStore.clear() }; swarmProgressStore.clear()
                    let followUpProvider: (any LLMProvider)? = {
                        guard let agentId = agentProviderIdBeforeSwarm, (agentId == "codex-cli" || agentId == "claude-cli"),
                              let agentProvider = providerRegistry.provider(for: agentId), agentProvider.isAuthenticated() else { return nil }
                        providerRegistry.selectedProviderId = agentId
                        coderMode = .agent
                        chatStore.addMessage(ChatMessage(role: .user, content: "[Seguito agent dopo swarm]", isStreaming: false), to: conversationId)
                        chatStore.addMessage(ChatMessage(role: .assistant, content: "", isStreaming: true), to: conversationId)
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
                            chatStore.updateLastAssistantMessage(content: content, in: conversationId)
                        },
                        onRaw: { t, p, pid in
                            if t == "coderide_show_task_panel" { taskPanelEnabled = true }
                            if t == "swarm_steps", let s = p["steps"], !s.isEmpty {
                                let n = s.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespaces) }
                                swarmProgressStore.setSteps(n)
                            }
                            if t == "agent", let ti = p["title"], let de = p["detail"] {
                                if de == "started" { swarmProgressStore.markStarted(name: ti) }
                                else if de == "completed" { swarmProgressStore.markCompleted(name: ti) }
                            }
                            recordTaskActivity(type: t, payload: p, providerId: pid)
                        },
                        onFollowUpText: { content in
                            chatStore.updateLastAssistantMessage(content: content, in: conversationId)
                        },
                        onError: { content in
                            chatStore.updateLastAssistantMessage(content: content, in: conversationId)
                        }
                    )
                    chatStore.endTask()
                    await trySummarizeIfNeeded(ctx: ctx)
                }
            } catch {
                chatStore.updateLastAssistantMessage(content: "[Errore: \(error.localizedDescription)]", in: conversationId)
                chatStore.setLastAssistantStreaming(false, in: conversationId)
                await MainActor.run {
                    flowDiagnosticsStore.setError(error.localizedDescription)
                    flowCoordinator.fail()
                }
            }
            chatStore.endTask()
        }
    }

    private func linkedContextPaths() -> [String] {
        var ordered: [String] = []
        ordered.append(contentsOf: todoStore.todos.flatMap(\.linkedFiles))
        if let board = chatStore.planBoard(for: conversationId) {
            ordered.append(contentsOf: board.steps.compactMap(\.targetFile))
        }
        var seen = Set<String>()
        return ordered.filter { seen.insert($0).inserted }
    }
}

// MARK: - Message Row

struct MessageRow: View {
    let message: ChatMessage
    let workspacePath: String
    let modeColor: Color
    let onFileClicked: (String) -> Void
    @State private var isHovered = false

    private var isUser: Bool { message.role == .user }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            avatar
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text(isUser ? "Tu" : "Coder AI")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(isUser ? Color.accentColor : modeColor)
                    if !isUser {
                        Image(systemName: "sparkle")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(modeColor.opacity(0.5))
                    }
                }
                if let paths = message.imagePaths, !paths.isEmpty {
                    userMessageImagesRow(paths: paths)
                }
                ClickableMessageContent(content: message.content, workspacePath: workspacePath, onFileClicked: onFileClicked)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if message.isStreaming { streamingBar }
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.large, style: .continuous)
                .fill(
                    isUser
                        ? DesignSystem.Colors.userBubble.opacity(0.78)
                        : (isHovered ? DesignSystem.Colors.backgroundSecondary.opacity(0.34) : DesignSystem.Colors.backgroundSecondary.opacity(0.18))
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.large, style: .continuous)
                .strokeBorder(DesignSystem.Colors.border.opacity(0.7), lineWidth: 0.7)
        )
        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.large, style: .continuous))
        .onHover { isHovered = $0 }
        .animation(.easeOut(duration: 0.1), value: isHovered)
    }

    private var avatar: some View {
        ZStack {
            Circle()
                .fill(isUser ? Color.accentColor.opacity(0.14) : modeColor.opacity(0.14))
            Circle()
                .strokeBorder(isUser ? Color.accentColor.opacity(0.25) : modeColor.opacity(0.25), lineWidth: 1)
            Image(systemName: isUser ? "person.fill" : "brain.head.profile")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(isUser ? Color.accentColor : modeColor)
        }
        .frame(width: 28, height: 28)
    }

    private var streamingBar: some View {
        HStack(spacing: 6) {
            StreamingDots(color: modeColor)
            Text("Sto scrivendo...")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.tertiary)
        }.padding(.top, 2)
    }

    @ViewBuilder
    private func userMessageImagesRow(paths: [String]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(paths, id: \.self) { path in
                    Group {
                        if FileManager.default.fileExists(atPath: path),
                           let nsImage = NSImage(contentsOf: URL(fileURLWithPath: path)) {
                            Image(nsImage: nsImage)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                        } else {
                            Image(systemName: "photo")
                                .font(.system(size: 24))
                                .foregroundStyle(.tertiary)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                    }
                    .frame(width: 60, height: 60)
                    .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }
        }
        .padding(.bottom, 4)
    }
}

// MARK: - Streaming Dots

struct StreamingDots: View {
    let color: Color
    @State private var phase: Int = 0

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .fill(color)
                    .frame(width: 4, height: 4)
                    .opacity(phase == i ? 1 : 0.25)
            }
        }
        .onAppear {
            Timer.scheduledTimer(withTimeInterval: 0.35, repeats: true) { _ in
                withAnimation(.easeInOut(duration: 0.2)) { phase = (phase + 1) % 3 }
            }
        }
    }
}

// MARK: - Backward compat aliases
typealias MessageBubbleView = MessageRow

struct TypingIndicator: View {
    @State private var dot = 0
    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<3, id: \.self) { i in
                Circle().fill(Color.secondary).frame(width: 4, height: 4).opacity(dot == i ? 1 : 0.3)
            }
        }
        .onAppear { Timer.scheduledTimer(withTimeInterval: 0.4, repeats: true) { _ in withAnimation { dot = (dot + 1) % 3 } } }
    }
}
