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

    private var activeModeColor: Color { modeColor(for: coderMode) }
    private var activeModeGradient: LinearGradient { modeGradient(for: coderMode) }

    var body: some View {
        VStack(spacing: 0) {
            modeTabBar
            separator

            if coderMode == .agentSwarm && !swarmProgressStore.steps.isEmpty {
                SwarmProgressView(store: swarmProgressStore)
            }
            if taskPanelEnabled && [.agent, .agentSwarm, .codeReviewMultiSwarm, .plan].contains(coderMode) {
                TaskActivityPanelView(store: taskActivityStore)
            }

            messagesArea

            if chatStore.isLoading, let startDate = chatStore.taskStartDate {
                taskTimerBanner(startDate: startDate)
            }

            composerArea
        }
        .onChange(of: providerRegistry.selectedProviderId) { _, newId in syncCoderModeToProvider(newId) }
        .onAppear {
            syncCoderModeToProvider(providerRegistry.selectedProviderId)
            codexModels = CodexModelsCache.loadModels()
            syncSwarmProvider(); syncMultiSwarmReviewProvider(); syncPlanProvider()
        }
        .onChange(of: swarmOrchestrator) { _, _ in syncSwarmProvider() }
        .onChange(of: swarmAutoPostCodePipeline) { _, _ in syncSwarmProvider() }
        .onChange(of: swarmMaxPostCodeRetries) { _, _ in syncSwarmProvider() }
        .onChange(of: codeReviewYolo) { _, _ in syncMultiSwarmReviewProvider() }
        .onChange(of: codeReviewPartitions) { _, _ in syncMultiSwarmReviewProvider() }
        .onChange(of: codeReviewAnalysisOnly) { _, _ in syncMultiSwarmReviewProvider() }
        .sheet(isPresented: $showSwarmHelp) { AgentSwarmHelpView() }
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
                        if case .awaitingChoice(_, let options) = planningState {
                            PlanOptionsView(
                                options: options,
                                planColor: DesignSystem.Colors.planColor,
                                onSelectOption: { executeWithPlanChoice($0.fullText) },
                                onCustomResponse: { executeWithPlanChoice($0) }
                            )
                            .id("plan-options")
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
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Task Timer Banner
    private func taskTimerBanner(startDate: Date) -> some View {
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
            }
            .padding(.horizontal, 16).padding(.vertical, 6)
            .background(DesignSystem.Colors.warning.opacity(0.06))
        }
    }

    private func formatElapsed(_ s: Int) -> String {
        let m = s / 60; let sec = s % 60
        return m > 0 ? String(format: "%d:%02d", m, sec) : "\(sec)s"
    }

    // MARK: - Composer
    private var composerArea: some View {
        VStack(spacing: 0) {
            separator
            VStack(spacing: 8) {
                composerBox
                controlsBar
            }
            .padding(12)
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
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(DesignSystem.Colors.backgroundTertiary)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(
                    isInputFocused ? activeModeColor.opacity(0.4) : DesignSystem.Colors.border,
                    lineWidth: isInputFocused ? 1.2 : 0.5
                )
        )
        .shadow(color: isInputFocused ? activeModeColor.opacity(0.1) : .clear, radius: 12, y: 2)
        .shadow(color: .black.opacity(0.12), radius: 4, y: 2)
        .animation(.easeOut(duration: 0.2), value: isInputFocused)
    }

    private var sendButton: some View {
        let awaitingChoice = if case .awaitingChoice = planningState { true } else { false }
        let canSend = !inputText.isEmpty && !chatStore.isLoading && !awaitingChoice
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
                }.buttonStyle(.plain)
                if coderMode == .agent || coderMode == .agentSwarm { formicaButton }
            } else if providerRegistry.selectedProviderId == "plan-mode" {
                Spacer()
                if coderMode == .plan { formicaButton }
            } else if [.agent, .agentSwarm, .plan].contains(coderMode) {
                Spacer(); formicaButton
            } else { Spacer() }
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
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "ant.fill").font(.caption2)
                Text(swarmOrchestrator == "openai" ? "Orchestrator: OpenAI" : "Orchestrator: Codex").font(.caption)
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
        switch mode {
        case .ide: providerRegistry.selectedProviderId = "openai-api"
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
    private func syncCodexProvider() {
        let sandbox = CodexSandboxMode(rawValue: effectiveSandbox) ?? .workspaceWrite
        let p = CodexCLIProvider(codexPath: codexPath.isEmpty ? nil : codexPath, sandboxMode: sandbox, modelOverride: codexModelOverride.isEmpty ? nil : codexModelOverride, modelReasoningEffort: codexReasoningEffort.isEmpty ? nil : codexReasoningEffort)
        providerRegistry.unregister(id: "codex-cli"); providerRegistry.register(p); syncSwarmProvider(); syncPlanProvider()
    }
    private func syncSwarmProvider() {
        guard let codex = providerRegistry.provider(for: "codex-cli") as? CodexCLIProvider else { return }
        let backend: OrchestratorBackend = swarmOrchestrator == "codex" ? .codex : .openai
        let oai: OpenAICompletionsClient? = backend == .openai && !openaiApiKey.isEmpty ? OpenAICompletionsClient(apiKey: openaiApiKey, model: openaiModel) : nil
        let cfg = SwarmConfig(orchestratorBackend: backend, autoPostCodePipeline: swarmAutoPostCodePipeline, maxPostCodeRetries: swarmMaxPostCodeRetries)
        providerRegistry.unregister(id: "agent-swarm"); providerRegistry.register(AgentSwarmProvider(config: cfg, openAIClient: oai, codexProvider: codex))
    }
    private func syncMultiSwarmReviewProvider() {
        guard let codex = providerRegistry.provider(for: "codex-cli") as? CodexCLIProvider else { return }
        let sandbox = CodexSandboxMode(rawValue: effectiveSandbox) ?? .workspaceWrite
        let cfg = MultiSwarmReviewConfig(partitionCount: codeReviewPartitions, yoloMode: codeReviewYolo, enabledPhases: codeReviewAnalysisOnly ? ReviewPhase.analysisOnly : ReviewPhase.analysisAndExecution)
        let cp = CodexCreateParams(codexPath: codexPath.isEmpty ? nil : codexPath, sandboxMode: sandbox, modelOverride: codexModelOverride.isEmpty ? nil : codexModelOverride, modelReasoningEffort: codexReasoningEffort.isEmpty ? nil : codexReasoningEffort)
        providerRegistry.unregister(id: "multi-swarm-review"); providerRegistry.register(MultiSwarmReviewProvider(config: cfg, codexProvider: codex, codexParams: cp))
    }
    private func syncCoderModeToProvider(_ pid: String?) {
        guard let id = pid else { return }
        switch id {
        case "agent-swarm": coderMode = .agentSwarm; planningState = .idle
        case "multi-swarm-review": coderMode = .codeReviewMultiSwarm; planningState = .idle
        case "plan-mode": coderMode = .plan
        case "codex-cli", "claude-cli": coderMode = .agent; planningState = .idle
        case "openai-api": coderMode = .ide; planningState = .idle
        default: break
        }
    }
    private func syncPlanProvider() {
        let codex = providerRegistry.provider(for: "codex-cli") as? CodexCLIProvider
        let claude = providerRegistry.provider(for: "claude-cli") as? ClaudeCLIProvider
        guard codex != nil || claude != nil else { return }
        providerRegistry.unregister(id: "plan-mode"); providerRegistry.register(PlanModeProvider(codexProvider: codex, claudeProvider: claude))
    }

    // MARK: - Plan Choice Execution
    private func executeWithPlanChoice(_ choice: String) {
        guard case .awaitingChoice(let planContent, _) = planningState else { return }
        let useClaude = planModeBackend == "claude"
        let provider: any LLMProvider
        if useClaude { guard let c = providerRegistry.provider(for: "claude-cli") as? ClaudeCLIProvider else { return }; provider = c }
        else { guard let c = providerRegistry.provider(for: "codex-cli") as? CodexCLIProvider else { return }; provider = c }

        chatStore.addMessage(ChatMessage(role: .user, content: "Procedi con: \(choice)", isStreaming: false), to: conversationId)
        chatStore.addMessage(ChatMessage(role: .assistant, content: "", isStreaming: true), to: conversationId)
        chatStore.beginTask(); if taskPanelEnabled { taskActivityStore.clear() }; planningState = .idle
        let prompt = "L'utente ha scelto il seguente approccio dal piano precedentemente proposto. Implementalo.\n\nPiano di riferimento:\n\(planContent)\n\nScelta dell'utente:\n\(choice)"
        let ctx = effectiveContext.toWorkspaceContext(openFiles: [], activeSelection: nil, activeFilePath: openFilesStore.openFilePath)

        Task {
            do {
                let stream = try await provider.send(prompt: prompt, context: ctx); var full = ""
                for try await ev in stream {
                    switch ev {
                    case .textDelta(let d): full += d; chatStore.updateLastAssistantMessage(content: full, in: conversationId)
                    case .error(let e): full += "\n\n[Errore: \(e)]"; chatStore.updateLastAssistantMessage(content: full, in: conversationId)
                    case .raw(let t, let p):
                        if t == "coderide_show_task_panel" { await MainActor.run { taskPanelEnabled = true } }
                        if taskPanelEnabled { await MainActor.run { taskActivityStore.addActivity(TaskActivity(type: t, title: p["title"] ?? t, detail: p["detail"], payload: p)) } }
                    default: break
                    }
                }
                chatStore.setLastAssistantStreaming(false, in: conversationId)
            } catch { chatStore.updateLastAssistantMessage(content: "[Errore: \(error.localizedDescription)]", in: conversationId); chatStore.setLastAssistantStreaming(false, in: conversationId) }
            chatStore.endTask()
        }
    }

    // MARK: - Send Message
    private func sendMessage() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, let provider = providerRegistry.selectedProvider, provider.isAuthenticated() else { return }
        inputText = ""
        chatStore.addMessage(ChatMessage(role: .user, content: text, isStreaming: false), to: conversationId)
        chatStore.addMessage(ChatMessage(role: .assistant, content: "", isStreaming: true), to: conversationId)
        chatStore.beginTask(); if taskPanelEnabled { taskActivityStore.clear() }
        if providerRegistry.selectedProviderId == "agent-swarm" { swarmProgressStore.clear() }

        let ctx = effectiveContext.toWorkspaceContext(openFiles: [], activeSelection: nil, activeFilePath: openFilesStore.openFilePath)
        var prompt = text
        if coderMode == .ide { prompt = "Rispondi solo con testo. Non modificare file né eseguire comandi.\n\n" + text }
        if coderMode == .mcpServer { prompt = "[MCP Server] " + text }
        if providerRegistry.selectedProviderId == "codex-cli" || providerRegistry.selectedProviderId == "claude-cli" {
            prompt = "Se vuoi mostrare all'utente il pannello delle attività in corso (modifiche file, comandi, tool MCP), includi: \(CoderIDEMarkers.showTaskPanel)\nPer task complessi che richiedono planner, coder, reviewer, ecc., delega allo swarm scrivendo: \(CoderIDEMarkers.invokeSwarmPrefix)DESCRIZIONE_TASK\(CoderIDEMarkers.invokeSwarmSuffix)\n\n" + prompt
        }

        Task {
            do {
                let stream = try await provider.send(prompt: prompt, context: ctx)
                var full = ""; var pendingSwarmTask: String?
                for try await ev in stream {
                    switch ev {
                    case .textDelta(let d): full += d; chatStore.updateLastAssistantMessage(content: full, in: conversationId)
                    case .error(let e): full += "\n\n[Errore: \(e)]"; chatStore.updateLastAssistantMessage(content: full, in: conversationId)
                    case .raw(let t, let p):
                        if t == "coderide_show_task_panel" { await MainActor.run { taskPanelEnabled = true } }
                        if t == "coderide_invoke_swarm", let task = p["task"], !task.isEmpty { pendingSwarmTask = task }
                        if t == "swarm_steps", let s = p["steps"], !s.isEmpty { let n = s.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespaces) }; await MainActor.run { swarmProgressStore.setSteps(n) } }
                        if t == "agent", let title = p["title"], let detail = p["detail"] {
                            if detail == "started" { await MainActor.run { swarmProgressStore.markStarted(name: title) } }
                            else if detail == "completed" { await MainActor.run { swarmProgressStore.markCompleted(name: title) } }
                        }
                        if taskPanelEnabled { await MainActor.run { taskActivityStore.addActivity(TaskActivity(type: t, title: p["title"] ?? t, detail: p["detail"], payload: p)) } }
                    default: break
                    }
                }
                chatStore.setLastAssistantStreaming(false, in: conversationId)
                if coderMode == .plan { let opts = PlanOptionsParser.parse(from: full); if !opts.isEmpty { await MainActor.run { planningState = .awaitingChoice(planContent: full, options: opts) } } }
                else if let task = pendingSwarmTask, let swarm = providerRegistry.provider(for: "agent-swarm"), swarm.isAuthenticated() {
                    await MainActor.run { providerRegistry.selectedProviderId = "agent-swarm"; coderMode = .agentSwarm }
                    chatStore.addMessage(ChatMessage(role: .user, content: "[Delegato allo swarm] \(task)", isStreaming: false), to: conversationId)
                    chatStore.addMessage(ChatMessage(role: .assistant, content: "", isStreaming: true), to: conversationId)
                    chatStore.beginTask(); if taskPanelEnabled { taskActivityStore.clear() }; swarmProgressStore.clear()
                    do {
                        let ss = try await swarm.send(prompt: task, context: ctx); var sc = ""
                        for try await e in ss {
                            switch e {
                            case .textDelta(let d): sc += d; chatStore.updateLastAssistantMessage(content: sc, in: conversationId)
                            case .raw(let t, let p):
                                if t == "coderide_show_task_panel" { await MainActor.run { taskPanelEnabled = true } }
                                if t == "swarm_steps", let s = p["steps"], !s.isEmpty { let n = s.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespaces) }; await MainActor.run { swarmProgressStore.setSteps(n) } }
                                if t == "agent", let ti = p["title"], let de = p["detail"] { if de == "started" { await MainActor.run { swarmProgressStore.markStarted(name: ti) } } else if de == "completed" { await MainActor.run { swarmProgressStore.markCompleted(name: ti) } } }
                                if taskPanelEnabled { await MainActor.run { taskActivityStore.addActivity(TaskActivity(type: t, title: p["title"] ?? t, detail: p["detail"], payload: p)) } }
                            default: break
                            }
                        }
                        chatStore.setLastAssistantStreaming(false, in: conversationId)
                    } catch { chatStore.updateLastAssistantMessage(content: "[Errore swarm: \(error.localizedDescription)]", in: conversationId); chatStore.setLastAssistantStreaming(false, in: conversationId) }
                    chatStore.endTask()
                }
            } catch { chatStore.updateLastAssistantMessage(content: "[Errore: \(error.localizedDescription)]", in: conversationId); chatStore.setLastAssistantStreaming(false, in: conversationId) }
            chatStore.endTask()
        }
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
                ClickableMessageContent(content: message.content, workspacePath: workspacePath, onFileClicked: onFileClicked)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if message.isStreaming { streamingBar }
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
        .background(
            isUser ? DesignSystem.Colors.userBubble : (isHovered ? DesignSystem.Colors.backgroundSecondary.opacity(0.3) : Color.clear)
        )
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
