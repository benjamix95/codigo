import SwiftUI
import AppKit
import CoderEngine

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
    @EnvironmentObject var swarmProgressStore: SwarmProgressStore
    let conversationId: UUID?
    let effectiveContext: EffectiveContext
    @State private var coderMode: CoderMode = .agent
    @State private var inputText = ""
    @FocusState private var isInputFocused: Bool
    @AppStorage("codex_path") private var codexPath = ""
    @AppStorage("codex_sandbox") private var codexSandbox = ""
    @AppStorage("codex_model_override") private var codexModelOverride = ""
    @AppStorage("codex_reasoning_effort") private var codexReasoningEffort = "xhigh"
    @AppStorage("swarm_orchestrator") private var swarmOrchestrator = "openai"
    @AppStorage("swarm_auto_post_code_pipeline") private var swarmAutoPostCodePipeline = true
    @AppStorage("swarm_max_post_code_retries") private var swarmMaxPostCodeRetries = 10
    @AppStorage("code_review_yolo") private var codeReviewYolo = false
    @AppStorage("code_review_partitions") private var codeReviewPartitions = 3
    @AppStorage("code_review_analysis_only") private var codeReviewAnalysisOnly = false
    @AppStorage("openai_api_key") private var openaiApiKey = ""
    @AppStorage("openai_model") private var openaiModel = "gpt-4o-mini"
    @State private var codexModels: [CodexModel] = []
    @State private var showSwarmHelp = false
    @AppStorage("task_panel_enabled") private var taskPanelEnabled = false
    @AppStorage("plan_mode_backend") private var planModeBackend = "codex"
    @State private var planningState: PlanningState = .idle

    var body: some View {
        VStack(spacing: 0) {
            modeTabBar
            Divider()

            if coderMode == .agentSwarm && !swarmProgressStore.steps.isEmpty {
                SwarmProgressView(store: swarmProgressStore)
            }
            if taskPanelEnabled && (coderMode == .agent || coderMode == .agentSwarm || coderMode == .codeReviewMultiSwarm || coderMode == .plan) {
                TaskActivityPanelView(store: taskActivityStore)
            }

            messagesArea

            if chatStore.isLoading, let startDate = chatStore.taskStartDate {
                taskTimerBanner(startDate: startDate)
            }

            composerArea
        }
        .background(Color(nsColor: .textBackgroundColor))
        .onChange(of: providerRegistry.selectedProviderId) { _, newId in
            syncCoderModeToProvider(newId)
        }
        .onAppear {
            syncCoderModeToProvider(providerRegistry.selectedProviderId)
            codexModels = CodexModelsCache.loadModels()
            syncSwarmProvider()
            syncMultiSwarmReviewProvider()
            syncPlanProvider()
        }
        .onChange(of: swarmOrchestrator) { _, _ in syncSwarmProvider() }
        .onChange(of: swarmAutoPostCodePipeline) { _, _ in syncSwarmProvider() }
        .onChange(of: swarmMaxPostCodeRetries) { _, _ in syncSwarmProvider() }
        .onChange(of: codeReviewYolo) { _, _ in syncMultiSwarmReviewProvider() }
        .onChange(of: codeReviewPartitions) { _, _ in syncMultiSwarmReviewProvider() }
        .onChange(of: codeReviewAnalysisOnly) { _, _ in syncMultiSwarmReviewProvider() }
        .sheet(isPresented: $showSwarmHelp) { AgentSwarmHelpView() }
    }

    // MARK: - Mode Tab Bar
    private var modeTabBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 2) {
                ForEach(CoderMode.allCases, id: \.self) { mode in
                    modeTabButton(for: mode)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
        }
    }

    private func modeTabButton(for mode: CoderMode) -> some View {
        let isSelected = coderMode == mode
        let color = modeColor(for: mode)
        return Button { selectMode(mode) } label: {
            HStack(spacing: 5) {
                Image(systemName: modeIcon(for: mode))
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(isSelected ? color : .secondary)
                Text(mode.rawValue)
                    .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? Color.primary : .secondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                Group {
                    if isSelected {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(color.opacity(0.1))
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .strokeBorder(color.opacity(0.2), lineWidth: 0.5)
                            )
                    }
                }
            )
            .contentShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .hoverHighlight(color.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private func selectMode(_ mode: CoderMode) {
        if mode == .ide { providerRegistry.selectedProviderId = "openai-api" }
        else if mode == .agent { providerRegistry.selectedProviderId = "codex-cli" }
        else if mode == .agentSwarm { providerRegistry.selectedProviderId = "agent-swarm" }
        else if mode == .codeReviewMultiSwarm { providerRegistry.selectedProviderId = "multi-swarm-review" }
        else if mode == .plan { providerRegistry.selectedProviderId = "plan-mode"; planningState = .idle }
        else if mode == .mcpServer { providerRegistry.selectedProviderId = "claude-cli" }
        coderMode = mode
    }

    private func modeColor(for mode: CoderMode) -> Color {
        switch mode {
        case .agent: return DesignSystem.Colors.agentColor
        case .agentSwarm: return DesignSystem.Colors.swarmColor
        case .codeReviewMultiSwarm: return DesignSystem.Colors.reviewColor
        case .plan: return DesignSystem.Colors.planColor
        case .ide: return DesignSystem.Colors.ideColor
        case .mcpServer: return DesignSystem.Colors.mcpColor
        }
    }

    private func modeIcon(for mode: CoderMode) -> String {
        switch mode {
        case .agent: return "brain.head.profile"
        case .agentSwarm: return "ant.fill"
        case .codeReviewMultiSwarm: return "doc.text.magnifyingglass"
        case .plan: return "list.bullet.rectangle"
        case .ide: return "sparkles"
        case .mcpServer: return "server.rack"
        }
    }

    private func modeGradient(for mode: CoderMode) -> LinearGradient {
        LinearGradient(colors: [modeColor(for: mode)], startPoint: .leading, endPoint: .trailing)
    }

    // MARK: - Pickers
    private var providerPicker: some View {
        Menu {
            ForEach(providerRegistry.providers, id: \.id) { provider in
                Button {
                    providerRegistry.selectedProviderId = provider.id
                } label: {
                    HStack {
                        Text(provider.displayName)
                        if providerRegistry.selectedProviderId == provider.id { Image(systemName: "checkmark") }
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "cpu").font(.caption2)
                Text(providerLabel).font(.caption)
                Image(systemName: "chevron.down").font(.system(size: 8, weight: .semibold))
            }
            .foregroundStyle(.secondary)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    private var providerLabel: String {
        if let id = providerRegistry.selectedProviderId,
           let provider = providerRegistry.providers.first(where: { $0.id == id }) {
            return provider.displayName
        }
        return "Seleziona provider"
    }

    private var codexModelPicker: some View {
        Menu {
            Button {
                codexModelOverride = ""; syncCodexProvider()
            } label: {
                HStack { Text("Default (da config)"); if codexModelOverride.isEmpty { Image(systemName: "checkmark") } }
            }
            if !codexModels.isEmpty {
                Divider()
                ForEach(codexModels, id: \.slug) { model in
                    Button {
                        codexModelOverride = model.slug; syncCodexProvider()
                    } label: {
                        HStack { Text(model.displayName); if codexModelOverride == model.slug { Image(systemName: "checkmark") } }
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text(codexModelLabel).font(.caption)
                Image(systemName: "chevron.down").font(.system(size: 8, weight: .semibold))
            }
            .foregroundStyle(.secondary)
        }
        .menuStyle(.borderlessButton).fixedSize()
    }

    private var codexModelLabel: String {
        if codexModelOverride.isEmpty { return "Default" }
        return codexModels.first(where: { $0.slug == codexModelOverride })?.displayName ?? codexModelOverride
    }

    private var codexReasoningPicker: some View {
        Menu {
            ForEach(["low", "medium", "high", "xhigh"], id: \.self) { effort in
                Button {
                    codexReasoningEffort = effort; syncCodexProvider()
                } label: {
                    HStack { Text(reasoningEffortDisplay(effort)); if codexReasoningEffort == effort { Image(systemName: "checkmark") } }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text(reasoningEffortDisplay(codexReasoningEffort)).font(.caption)
                Image(systemName: "chevron.down").font(.system(size: 8, weight: .semibold))
            }
            .foregroundStyle(.secondary)
        }
        .menuStyle(.borderlessButton).fixedSize()
    }

    private func reasoningEffortDisplay(_ effort: String) -> String {
        switch effort.lowercased() {
        case "low": return "Low"; case "medium": return "Medium"; case "high": return "High"; case "xhigh": return "XHigh"
        default: return effort
        }
    }

    private var effectiveSandbox: String {
        if codexSandbox.isEmpty { return CodexConfigLoader.load().sandboxMode ?? "workspace-write" }
        return codexSandbox
    }

    private var accessLevelMenu: some View {
        let config = CodexConfigLoader.load()
        return Menu {
            Button {
                codexSandbox = ""; syncCodexProvider()
            } label: {
                HStack { Label("Default (da config)", systemImage: "doc.badge.gearshape"); if codexSandbox.isEmpty { Image(systemName: "checkmark") } }
            }
            if config.sandboxMode != nil {
                Text("Config: \(accessLevelLabel(for: config.sandboxMode ?? ""))").font(.caption2).foregroundStyle(.secondary)
            }
            Divider()
            Button { codexSandbox = "read-only"; syncCodexProvider() } label: { Label("Read Only", systemImage: "lock.shield") }
            Button { codexSandbox = "workspace-write"; syncCodexProvider() } label: { Label("Default", systemImage: "shield") }
            Button { codexSandbox = "danger-full-access"; syncCodexProvider() } label: { Label("Full Access", systemImage: "exclamationmark.shield.fill") }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: accessLevelIcon(for: effectiveSandbox)).font(.caption)
                Text(accessLevelLabel(for: effectiveSandbox)).font(.caption)
                Image(systemName: "chevron.down").font(.system(size: 8, weight: .semibold))
            }
            .foregroundStyle(effectiveSandbox == "danger-full-access" ? .red : .secondary)
        }
        .menuStyle(.borderlessButton).fixedSize()
    }

    private var swarmOrchestratorPicker: some View {
        Menu {
            Button { swarmOrchestrator = "openai"; syncSwarmProvider() } label: {
                HStack { Text("OpenAI"); if swarmOrchestrator == "openai" { Image(systemName: "checkmark") } }
            }
            Button { swarmOrchestrator = "codex"; syncSwarmProvider() } label: {
                HStack { Text("Codex"); if swarmOrchestrator == "codex" { Image(systemName: "checkmark") } }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "ant.fill").font(.caption2)
                Text(swarmOrchestrator == "openai" ? "Orchestrator: OpenAI" : "Orchestrator: Codex").font(.caption)
                Image(systemName: "chevron.down").font(.system(size: 8, weight: .semibold))
            }
            .foregroundStyle(.secondary)
        }
        .menuStyle(.borderlessButton).fixedSize()
    }

    private var formicaButton: some View {
        Button { taskPanelEnabled.toggle() } label: {
            Image(systemName: "ant.fill").font(.caption)
                .foregroundStyle(taskPanelEnabled ? DesignSystem.Colors.swarmColor : .secondary)
        }
        .buttonStyle(.plain).help("Task Activity Panel")
    }

    private func accessLevelIcon(for sandbox: String) -> String {
        switch sandbox {
        case "read-only": return "lock.shield"; case "workspace-write": return "shield"
        case "danger-full-access": return "exclamationmark.shield.fill"; default: return "shield"
        }
    }
    private func accessLevelLabel(for sandbox: String) -> String {
        switch sandbox {
        case "read-only": return "Read Only"; case "workspace-write": return "Default"
        case "danger-full-access": return "Full Access"; default: return "Default"
        }
    }

    // MARK: - Messages Area
    private var messagesArea: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if let conv = chatStore.conversation(for: conversationId) {
                        ForEach(conv.messages) { message in
                            MessageBubbleView(
                                message: message,
                                workspacePath: effectiveContext.primaryPath ?? "",
                                onFileClicked: { path in openFilesStore.openFile(path) }
                            )
                            .id(message.id)
                        }

                        if case .awaitingChoice(_, let options) = planningState {
                            PlanOptionsView(
                                options: options,
                                planColor: DesignSystem.Colors.planColor,
                                onSelectOption: { opt in executeWithPlanChoice(opt.fullText) },
                                onCustomResponse: { text in executeWithPlanChoice(text) }
                            )
                            .id("plan-options")
                        }
                    }
                }
                .padding(.top, 8)
                .padding(.bottom, 12)
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
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Task Timer Banner
    private func taskTimerBanner(startDate: Date) -> some View {
        TimelineView(.periodic(from: startDate, by: 1.0)) { context in
            let elapsed = Int(context.date.timeIntervalSince(startDate))
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Task in esecuzione").font(.caption).foregroundStyle(.secondary)
                Text(formatElapsed(elapsed))
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(DesignSystem.Colors.warning)
                Spacer()
            }
            .padding(.horizontal, 16).padding(.vertical, 6)
            .background(DesignSystem.Colors.warning.opacity(0.06))
        }
    }

    private func formatElapsed(_ seconds: Int) -> String {
        let m = seconds / 60; let s = seconds % 60
        return m > 0 ? String(format: "%d:%02d", m, s) : "\(s)s"
    }

    // MARK: - Composer Area
    private var composerArea: some View {
        VStack(spacing: 0) {
            Divider()
            VStack(spacing: 8) {
                composerBox
                controlsBar
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Color(nsColor: .windowBackgroundColor))
        }
    }

    private var composerBox: some View {
        HStack(alignment: .bottom, spacing: 8) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    Circle()
                        .fill(modeColor(for: coderMode))
                        .frame(width: 6, height: 6)
                    Text(inputHint)
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }

                TextField("Scrivi un messaggio...", text: $inputText, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .lineLimit(1...8)
                    .focused($isInputFocused)
                    .onSubmit { sendMessage() }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            sendButton
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(nsColor: .textBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(
                    isInputFocused ? modeColor(for: coderMode).opacity(0.5) : Color(nsColor: .separatorColor).opacity(0.6),
                    lineWidth: isInputFocused ? 1.5 : 0.5
                )
        )
        .shadow(color: .black.opacity(isInputFocused ? 0.06 : 0.02), radius: isInputFocused ? 4 : 1, y: 1)
        .animation(.easeOut(duration: 0.15), value: isInputFocused)
    }

    private var controlsBar: some View {
        HStack(spacing: 6) {
            providerPicker
            if providerRegistry.selectedProviderId == "codex-cli" {
                codexModelPicker; codexReasoningPicker; accessLevelMenu
                if coderMode == .agent || coderMode == .agentSwarm { formicaButton }
            } else if providerRegistry.selectedProviderId == "claude-cli" {
                if coderMode == .agent || coderMode == .agentSwarm { formicaButton }
            } else if providerRegistry.selectedProviderId == "agent-swarm" {
                swarmOrchestratorPicker
                Button { showSwarmHelp = true } label: {
                    Image(systemName: "questionmark.circle").font(.caption).foregroundStyle(DesignSystem.Colors.swarmColor)
                }
                .buttonStyle(.plain)
                if coderMode == .agent || coderMode == .agentSwarm { formicaButton }
            } else if providerRegistry.selectedProviderId == "plan-mode" {
                Spacer()
                if coderMode == .plan { formicaButton }
            } else if coderMode == .agent || coderMode == .agentSwarm || coderMode == .plan {
                Spacer(); formicaButton
            } else {
                Spacer()
            }
        }
    }

    private var inputHint: String {
        switch coderMode {
        case .agent: return "L'agente può modificare file ed eseguire comandi"
        case .agentSwarm: return "Swarm di agenti specializzati"
        case .codeReviewMultiSwarm: return "Code review parallela su più swarm"
        case .plan: return "Piano con opzioni + risposta custom"
        case .ide: return "Modalità sola lettura"
        case .mcpServer: return "Invia al server MCP configurato"
        }
    }

    private var sendButton: some View {
        let awaitingChoice = if case .awaitingChoice = planningState { true } else { false }
        let canSend = !inputText.isEmpty && !chatStore.isLoading && !awaitingChoice
        return Button(action: sendMessage) {
            Image(systemName: "arrow.up")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(canSend ? .white : Color(nsColor: .tertiaryLabelColor))
                .frame(width: 26, height: 26)
                .background(
                    Circle().fill(canSend ? modeColor(for: coderMode) : Color(nsColor: .separatorColor).opacity(0.3))
                )
        }
        .buttonStyle(.plain)
        .disabled(!canSend)
    }

    // MARK: - Provider Sync
    private func syncCodexProvider() {
        let sandbox: CodexSandboxMode = CodexSandboxMode(rawValue: effectiveSandbox) ?? .workspaceWrite
        let provider = CodexCLIProvider(
            codexPath: codexPath.isEmpty ? nil : codexPath,
            sandboxMode: sandbox,
            modelOverride: codexModelOverride.isEmpty ? nil : codexModelOverride,
            modelReasoningEffort: codexReasoningEffort.isEmpty ? nil : codexReasoningEffort
        )
        providerRegistry.unregister(id: "codex-cli"); providerRegistry.register(provider)
        syncSwarmProvider(); syncPlanProvider()
    }

    private func syncSwarmProvider() {
        guard let codex = providerRegistry.provider(for: "codex-cli") as? CodexCLIProvider else { return }
        let backend: OrchestratorBackend = swarmOrchestrator == "codex" ? .codex : .openai
        let openAIClient: OpenAICompletionsClient? = backend == .openai && !openaiApiKey.isEmpty
            ? OpenAICompletionsClient(apiKey: openaiApiKey, model: openaiModel)
            : nil
        let config = SwarmConfig(orchestratorBackend: backend, autoPostCodePipeline: swarmAutoPostCodePipeline, maxPostCodeRetries: swarmMaxPostCodeRetries)
        let swarm = AgentSwarmProvider(config: config, openAIClient: openAIClient, codexProvider: codex)
        providerRegistry.unregister(id: "agent-swarm"); providerRegistry.register(swarm)
    }

    private func syncMultiSwarmReviewProvider() {
        guard let codex = providerRegistry.provider(for: "codex-cli") as? CodexCLIProvider else { return }
        let sandbox: CodexSandboxMode = CodexSandboxMode(rawValue: effectiveSandbox) ?? .workspaceWrite
        let config = MultiSwarmReviewConfig(
            partitionCount: codeReviewPartitions, yoloMode: codeReviewYolo,
            enabledPhases: codeReviewAnalysisOnly ? ReviewPhase.analysisOnly : ReviewPhase.analysisAndExecution
        )
        let codexParams = CodexCreateParams(
            codexPath: codexPath.isEmpty ? nil : codexPath, sandboxMode: sandbox,
            modelOverride: codexModelOverride.isEmpty ? nil : codexModelOverride,
            modelReasoningEffort: codexReasoningEffort.isEmpty ? nil : codexReasoningEffort
        )
        let provider = MultiSwarmReviewProvider(config: config, codexProvider: codex, codexParams: codexParams)
        providerRegistry.unregister(id: "multi-swarm-review"); providerRegistry.register(provider)
    }

    private func syncCoderModeToProvider(_ providerId: String?) {
        guard let id = providerId else { return }
        if id == "agent-swarm" { coderMode = .agentSwarm; planningState = .idle }
        else if id == "multi-swarm-review" { coderMode = .codeReviewMultiSwarm; planningState = .idle }
        else if id == "plan-mode" { coderMode = .plan }
        else if id == "codex-cli" || id == "claude-cli" { coderMode = .agent; planningState = .idle }
        else if id == "openai-api" { coderMode = .ide; planningState = .idle }
    }

    private func syncPlanProvider() {
        let codex = providerRegistry.provider(for: "codex-cli") as? CodexCLIProvider
        let claude = providerRegistry.provider(for: "claude-cli") as? ClaudeCLIProvider
        guard codex != nil || claude != nil else { return }
        let planProvider = PlanModeProvider(codexProvider: codex, claudeProvider: claude)
        providerRegistry.unregister(id: "plan-mode"); providerRegistry.register(planProvider)
    }

    // MARK: - Plan Choice Execution
    private func executeWithPlanChoice(_ choice: String) {
        guard case .awaitingChoice(let planContent, _) = planningState else { return }
        let useClaude = planModeBackend == "claude"
        let provider: any LLMProvider
        if useClaude {
            guard let claude = providerRegistry.provider(for: "claude-cli") as? ClaudeCLIProvider else { return }
            provider = claude
        } else {
            guard let codex = providerRegistry.provider(for: "codex-cli") as? CodexCLIProvider else { return }
            provider = codex
        }

        let userMessage = "Procedi con: \(choice)"
        chatStore.addMessage(ChatMessage(role: .user, content: userMessage, isStreaming: false), to: conversationId)
        chatStore.addMessage(ChatMessage(role: .assistant, content: "", isStreaming: true), to: conversationId)
        chatStore.beginTask()
        if taskPanelEnabled { taskActivityStore.clear() }
        planningState = .idle

        let executePrompt = """
        L'utente ha scelto il seguente approccio dal piano precedentemente proposto. Implementalo.

        Piano di riferimento:
        \(planContent)

        Scelta dell'utente:
        \(choice)
        """

        let ctx = effectiveContext.toWorkspaceContext(openFiles: [], activeSelection: nil, activeFilePath: openFilesStore.openFilePath)

        Task {
            do {
                let stream = try await provider.send(prompt: executePrompt, context: ctx)
                var fullContent = ""
                for try await event in stream {
                    switch event {
                    case .textDelta(let delta):
                        fullContent += delta
                        chatStore.updateLastAssistantMessage(content: fullContent, in: conversationId)
                    case .completed, .started: break
                    case .error(let err):
                        fullContent += "\n\n[Errore: \(err)]"
                        chatStore.updateLastAssistantMessage(content: fullContent, in: conversationId)
                    case .raw(let type, let payload):
                        if type == "coderide_show_task_panel" { await MainActor.run { taskPanelEnabled = true } }
                        if taskPanelEnabled {
                            let activity = TaskActivity(type: type, title: payload["title"] ?? type, detail: payload["detail"], payload: payload)
                            await MainActor.run { taskActivityStore.addActivity(activity) }
                        }
                    }
                }
                chatStore.setLastAssistantStreaming(false, in: conversationId)
            } catch {
                chatStore.updateLastAssistantMessage(content: "[Errore: \(error.localizedDescription)]", in: conversationId)
                chatStore.setLastAssistantStreaming(false, in: conversationId)
            }
            chatStore.endTask()
        }
    }

    // MARK: - Send Message
    private func sendMessage() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        guard let provider = providerRegistry.selectedProvider else { return }
        guard provider.isAuthenticated() else { return }

        inputText = ""
        chatStore.addMessage(ChatMessage(role: .user, content: text, isStreaming: false), to: conversationId)
        chatStore.addMessage(ChatMessage(role: .assistant, content: "", isStreaming: true), to: conversationId)
        chatStore.beginTask()
        if taskPanelEnabled { taskActivityStore.clear() }
        if providerRegistry.selectedProviderId == "agent-swarm" { swarmProgressStore.clear() }

        let ctx = effectiveContext.toWorkspaceContext(openFiles: [], activeSelection: nil, activeFilePath: openFilesStore.openFilePath)
        var prompt = text
        if coderMode == .ide { prompt = "Rispondi solo con testo. Non modificare file né eseguire comandi.\n\n" + text }
        if coderMode == .mcpServer { prompt = "[MCP Server] " + text }
        if providerRegistry.selectedProviderId == "codex-cli" || providerRegistry.selectedProviderId == "claude-cli" {
            var instr = "Se vuoi mostrare all'utente il pannello delle attività in corso (modifiche file, comandi, tool MCP), includi: \(CoderIDEMarkers.showTaskPanel)\n"
            instr += "Per task complessi che richiedono planner, coder, reviewer, ecc., delega allo swarm scrivendo: \(CoderIDEMarkers.invokeSwarmPrefix)DESCRIZIONE_TASK\(CoderIDEMarkers.invokeSwarmSuffix)\n\n"
            prompt = instr + prompt
        }

        Task {
            do {
                let stream = try await provider.send(prompt: prompt, context: ctx)
                var fullContent = ""
                var pendingSwarmTask: String?
                for try await event in stream {
                    switch event {
                    case .textDelta(let delta):
                        fullContent += delta
                        chatStore.updateLastAssistantMessage(content: fullContent, in: conversationId)
                    case .completed, .started: break
                    case .error(let err):
                        fullContent += "\n\n[Errore: \(err)]"
                        chatStore.updateLastAssistantMessage(content: fullContent, in: conversationId)
                    case .raw(let type, let payload):
                        if type == "coderide_show_task_panel" { await MainActor.run { taskPanelEnabled = true } }
                        if type == "coderide_invoke_swarm", let task = payload["task"], !task.isEmpty { pendingSwarmTask = task }
                        if type == "swarm_steps", let stepsStr = payload["steps"], !stepsStr.isEmpty {
                            let names = stepsStr.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespaces) }
                            await MainActor.run { swarmProgressStore.setSteps(names) }
                        }
                        if type == "agent", let title = payload["title"], let detail = payload["detail"] {
                            if detail == "started" { await MainActor.run { swarmProgressStore.markStarted(name: title) } }
                            else if detail == "completed" { await MainActor.run { swarmProgressStore.markCompleted(name: title) } }
                        }
                        if taskPanelEnabled {
                            let activity = TaskActivity(type: type, title: payload["title"] ?? type, detail: payload["detail"], payload: payload)
                            await MainActor.run { taskActivityStore.addActivity(activity) }
                        }
                    }
                }
                chatStore.setLastAssistantStreaming(false, in: conversationId)

                if coderMode == .plan {
                    let options = PlanOptionsParser.parse(from: fullContent)
                    if !options.isEmpty {
                        await MainActor.run { planningState = .awaitingChoice(planContent: fullContent, options: options) }
                    }
                } else if let task = pendingSwarmTask, let swarm = providerRegistry.provider(for: "agent-swarm"), swarm.isAuthenticated() {
                    await MainActor.run { providerRegistry.selectedProviderId = "agent-swarm"; coderMode = .agentSwarm }
                    chatStore.addMessage(ChatMessage(role: .user, content: "[Delegato allo swarm] \(task)", isStreaming: false), to: conversationId)
                    chatStore.addMessage(ChatMessage(role: .assistant, content: "", isStreaming: true), to: conversationId)
                    chatStore.beginTask()
                    if taskPanelEnabled { taskActivityStore.clear() }
                    swarmProgressStore.clear()
                    do {
                        let swarmStream = try await swarm.send(prompt: task, context: ctx)
                        var swarmContent = ""
                        for try await ev in swarmStream {
                            switch ev {
                            case .textDelta(let d):
                                swarmContent += d; chatStore.updateLastAssistantMessage(content: swarmContent, in: conversationId)
                            case .raw(let t, let p):
                                if t == "coderide_show_task_panel" { await MainActor.run { taskPanelEnabled = true } }
                                if t == "swarm_steps", let stepsStr = p["steps"], !stepsStr.isEmpty {
                                    let names = stepsStr.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespaces) }
                                    await MainActor.run { swarmProgressStore.setSteps(names) }
                                }
                                if t == "agent", let title = p["title"], let detail = p["detail"] {
                                    if detail == "started" { await MainActor.run { swarmProgressStore.markStarted(name: title) } }
                                    else if detail == "completed" { await MainActor.run { swarmProgressStore.markCompleted(name: title) } }
                                }
                                if taskPanelEnabled {
                                    let act = TaskActivity(type: t, title: p["title"] ?? t, detail: p["detail"], payload: p)
                                    await MainActor.run { taskActivityStore.addActivity(act) }
                                }
                            default: break
                            }
                        }
                        chatStore.setLastAssistantStreaming(false, in: conversationId)
                    } catch {
                        chatStore.updateLastAssistantMessage(content: "[Errore swarm: \(error.localizedDescription)]", in: conversationId)
                        chatStore.setLastAssistantStreaming(false, in: conversationId)
                    }
                    chatStore.endTask()
                }
            } catch {
                chatStore.updateLastAssistantMessage(content: "[Errore: \(error.localizedDescription)]", in: conversationId)
                chatStore.setLastAssistantStreaming(false, in: conversationId)
            }
            chatStore.endTask()
        }
    }
}

// MARK: - Message Bubble View
struct MessageBubbleView: View {
    let message: ChatMessage
    let workspacePath: String
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
                        .foregroundStyle(isUser ? Color.accentColor : DesignSystem.Colors.agentColor)
                    if !isUser {
                        Image(systemName: "sparkle")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(DesignSystem.Colors.agentColor.opacity(0.6))
                    }
                }

                ClickableMessageContent(
                    content: message.content,
                    workspacePath: workspacePath,
                    onFileClicked: onFileClicked
                )
                .frame(maxWidth: .infinity, alignment: .leading)

                if message.isStreaming {
                    streamingIndicator
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(isUser ? Color.accentColor.opacity(0.04) : Color.clear)
        .background(isHovered ? Color.primary.opacity(0.02) : Color.clear)
        .onHover { isHovered = $0 }
    }

    private var avatar: some View {
        ZStack {
            Circle()
                .fill(isUser ? Color.accentColor.opacity(0.12) : DesignSystem.Colors.agentColor.opacity(0.12))
            Image(systemName: isUser ? "person.fill" : "brain.head.profile")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(isUser ? Color.accentColor : DesignSystem.Colors.agentColor)
        }
        .frame(width: 28, height: 28)
    }

    private var streamingIndicator: some View {
        HStack(spacing: 6) {
            PulsingDot(color: DesignSystem.Colors.agentColor)
            Text("Sto scrivendo...")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
        }
        .padding(.top, 2)
    }
}

// MARK: - Pulsing Dot (replaces old TypingIndicator)
struct PulsingDot: View {
    let color: Color
    @State private var isPulsing = false

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 6, height: 6)
            .opacity(isPulsing ? 1 : 0.3)
            .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: isPulsing)
            .onAppear { isPulsing = true }
    }
}

// MARK: - Backward compat alias
struct TypingIndicator: View {
    @State private var animatingDot = 0
    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<3, id: \.self) { index in
                Circle().fill(Color.secondary).frame(width: 4, height: 4).opacity(animatingDot == index ? 1 : 0.3)
            }
        }
        .onAppear {
            Timer.scheduledTimer(withTimeInterval: 0.4, repeats: true) { _ in
                withAnimation(.easeInOut(duration: 0.2)) { animatingDot = (animatingDot + 1) % 3 }
            }
        }
    }
}
