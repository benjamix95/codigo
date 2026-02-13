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
    @AppStorage("codex_sandbox") private var codexSandbox = ""  // "" = usa ~/.codex/config.toml
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
            // Header with mode selector
            glassHeader
            
            // Swarm progress checklist
            if coderMode == .agentSwarm && !swarmProgressStore.steps.isEmpty {
                SwarmProgressView(store: swarmProgressStore)
            }
            // Task Activity Panel (formica attiva)
            if taskPanelEnabled && (coderMode == .agent || coderMode == .agentSwarm || coderMode == .codeReviewMultiSwarm || coderMode == .plan) {
                TaskActivityPanelView(store: taskActivityStore)
            }
            
            // Messages area
            messagesArea
            
            // Loading indicator
            if chatStore.isLoading, let startDate = chatStore.taskStartDate {
                taskTimerBanner(startDate: startDate)
            }
            
            // Input area
            glassInputArea
        }
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
        .sheet(isPresented: $showSwarmHelp) {
            AgentSwarmHelpView()
        }
    }
    
    // MARK: - Glass Header
    private var glassHeader: some View {
        modeSelectorPills
            .padding(.horizontal, DesignSystem.Spacing.md)
            .padding(.vertical, DesignSystem.Spacing.sm)
            .overlay {
                Rectangle()
                    .frame(height: 0.5)
                    .foregroundStyle(DesignSystem.Colors.divider)
                    .frame(maxHeight: .infinity, alignment: .bottom)
            }
    }
    
    private var modeSelectorPills: some View {
        HStack(spacing: DesignSystem.Spacing.xs) {
            ForEach(CoderMode.allCases, id: \.self) { mode in
                modePillButton(for: mode)
            }
        }
    }

    private var formicaButton: some View {
        Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                taskPanelEnabled.toggle()
            }
        } label: {
            Image(systemName: "ant.fill")
                .font(DesignSystem.Typography.caption)
                .foregroundStyle(taskPanelEnabled ? DesignSystem.Colors.swarmColor : DesignSystem.Colors.textTertiary)
        }
        .buttonStyle(.plain)
        .hoverEffect(scale: 1.1)
        .help("Task Activity Panel")
    }
    
    private func modePillButton(for mode: CoderMode) -> some View {
        let isSelected = coderMode == mode
        
        return Button {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                if mode == .ide {
                    providerRegistry.selectedProviderId = "openai-api"
                } else if mode == .agent {
                    providerRegistry.selectedProviderId = "codex-cli"
                } else if mode == .agentSwarm {
                    providerRegistry.selectedProviderId = "agent-swarm"
                } else if mode == .codeReviewMultiSwarm {
                    providerRegistry.selectedProviderId = "multi-swarm-review"
                } else if mode == .plan {
                    providerRegistry.selectedProviderId = "plan-mode"
                    planningState = .idle
                } else if mode == .mcpServer {
                    providerRegistry.selectedProviderId = "claude-cli"
                }
                coderMode = mode
            }
        } label: {
            HStack(spacing: DesignSystem.Spacing.sm) {
                Image(systemName: modeIcon(for: mode))
                    .font(DesignSystem.Typography.subheadline)
                Text(mode.rawValue)
                    .font(DesignSystem.Typography.subheadlineMedium)
            }
            .foregroundStyle(isSelected ? .white : DesignSystem.Colors.textTertiary)
            .padding(.horizontal, DesignSystem.Spacing.lg)
            .padding(.vertical, DesignSystem.Spacing.md)
            .background {
                if isSelected {
                    Capsule()
                        .fill(modeGradient(for: mode))
                        .overlay {
                            Capsule()
                                .stroke(Color.white.opacity(0.2), lineWidth: 0.5)
                        }
                        .shadow(color: modeColor(for: mode).opacity(0.3), radius: 8, x: 0, y: 4)
                } else {
                    Capsule()
                        .fill(.ultraThinMaterial)
                        .opacity(0.5)
                        .overlay {
                            Capsule()
                                .stroke(Color.white.opacity(0.08), lineWidth: 0.5)
                        }
                }
            }
        }
        .buttonStyle(.plain)
        .hoverEffect(scale: 1.02)
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
    
    private func modeGradient(for mode: CoderMode) -> LinearGradient {
        switch mode {
        case .agent: return DesignSystem.Colors.agentGradient
        case .agentSwarm: return DesignSystem.Colors.swarmGradient
        case .codeReviewMultiSwarm: return DesignSystem.Colors.reviewGradient
        case .plan: return DesignSystem.Colors.planGradient
        case .ide: return DesignSystem.Colors.ideGradient
        case .mcpServer: return DesignSystem.Colors.mcpGradient
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
    
    private var providerPicker: some View {
        Menu {
            Text("Seleziona provider")
                .font(DesignSystem.Typography.caption)
            Divider()
            ForEach(providerRegistry.providers, id: \.id) { provider in
                Button {
                    providerRegistry.selectedProviderId = provider.id
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
            HStack(spacing: DesignSystem.Spacing.sm) {
                Image(systemName: "cpu.fill")
                    .font(DesignSystem.Typography.caption)
                    .foregroundStyle(DesignSystem.Colors.primary)
                Text(providerLabel)
                    .font(DesignSystem.Typography.subheadlineMedium)
                    .foregroundStyle(DesignSystem.Colors.textPrimary)
                Image(systemName: "chevron.down")
                    .font(DesignSystem.Typography.caption2)
                    .foregroundStyle(DesignSystem.Colors.textTertiary)
            }
            .padding(.horizontal, DesignSystem.Spacing.md)
            .padding(.vertical, DesignSystem.Spacing.sm)
            .liquidGlass(
                cornerRadius: DesignSystem.CornerRadius.medium,
                tint: DesignSystem.Colors.primary
            )
        }
        .menuStyle(.borderlessButton)
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
                codexModelOverride = ""
                syncCodexProvider()
            } label: {
                HStack {
                    Text("Default (da config)")
                    if codexModelOverride.isEmpty {
                        Image(systemName: "checkmark")
                    }
                }
            }
            if !codexModels.isEmpty {
                Divider()
                ForEach(codexModels, id: \.slug) { model in
                    Button {
                        codexModelOverride = model.slug
                        syncCodexProvider()
                    } label: {
                        HStack {
                            Text(model.displayName)
                            if codexModelOverride == model.slug {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: DesignSystem.Spacing.sm) {
                Image(systemName: "cpu.fill")
                    .font(DesignSystem.Typography.caption)
                    .foregroundStyle(DesignSystem.Colors.primary)
                Text(codexModelLabel)
                    .font(DesignSystem.Typography.captionMedium)
                    .foregroundStyle(DesignSystem.Colors.textPrimary)
                Image(systemName: "chevron.down")
                    .font(DesignSystem.Typography.caption2)
                    .foregroundStyle(DesignSystem.Colors.textTertiary)
            }
            .padding(.horizontal, DesignSystem.Spacing.md)
            .padding(.vertical, DesignSystem.Spacing.sm)
            .liquidGlass(
                cornerRadius: DesignSystem.CornerRadius.medium,
                tint: DesignSystem.Colors.primary
            )
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("Modello Codex")
    }
    
    private var codexReasoningPicker: some View {
        Menu {
            ForEach(["low", "medium", "high", "xhigh"], id: \.self) { effort in
                Button {
                    codexReasoningEffort = effort
                    syncCodexProvider()
                } label: {
                    HStack {
                        Text(reasoningEffortDisplay(effort))
                        if codexReasoningEffort == effort {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: DesignSystem.Spacing.sm) {
                Text(reasoningEffortDisplay(codexReasoningEffort))
                    .font(DesignSystem.Typography.captionMedium)
                    .foregroundStyle(DesignSystem.Colors.textSecondary)
                Image(systemName: "chevron.down")
                    .font(DesignSystem.Typography.caption2)
                    .foregroundStyle(DesignSystem.Colors.textTertiary)
            }
            .padding(.horizontal, DesignSystem.Spacing.md)
            .padding(.vertical, DesignSystem.Spacing.sm)
            .liquidGlass(cornerRadius: DesignSystem.CornerRadius.medium)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("Livello reasoning")
    }
    
    private var codexModelLabel: String {
        if codexModelOverride.isEmpty {
            return "Default"
        }
        return codexModels.first(where: { $0.slug == codexModelOverride })?.displayName ?? codexModelOverride
    }
    
    /// Sandbox effettivo: da config Codex se vuoto, altrimenti valore scelto dall'utente
    private var effectiveSandbox: String {
        if codexSandbox.isEmpty {
            return CodexConfigLoader.load().sandboxMode ?? "workspace-write"
        }
        return codexSandbox
    }
    
    private func reasoningEffortDisplay(_ effort: String) -> String {
        switch effort.lowercased() {
        case "low": return "Low"
        case "medium": return "Medium"
        case "high": return "High"
        case "xhigh": return "XHigh"
        default: return effort
        }
    }
    
    private var accessLevelMenu: some View {
        let config = CodexConfigLoader.load()
        return Menu {
            Button {
                codexSandbox = ""
                syncCodexProvider()
            } label: {
                HStack {
                    Label("Default (da config)", systemImage: "doc.badge.gearshape")
                    if codexSandbox.isEmpty {
                        Image(systemName: "checkmark")
                    }
                }
            }
            if config.sandboxMode != nil {
                Text("Config: \(accessLevelLabel(for: config.sandboxMode ?? ""))")
                    .font(DesignSystem.Typography.caption2)
                    .foregroundStyle(DesignSystem.Colors.textTertiary)
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
            HStack(spacing: DesignSystem.Spacing.sm) {
                Image(systemName: accessLevelIcon(for: effectiveSandbox))
                    .font(DesignSystem.Typography.subheadline)
                Text(accessLevelLabel(for: effectiveSandbox))
                    .font(DesignSystem.Typography.captionMedium)
                Image(systemName: "chevron.down")
                    .font(DesignSystem.Typography.caption2)
            }
            .padding(.horizontal, DesignSystem.Spacing.md)
            .padding(.vertical, DesignSystem.Spacing.sm)
            .liquidGlass(
                cornerRadius: DesignSystem.CornerRadius.medium,
                tint: effectiveSandbox == "danger-full-access" ? DesignSystem.Colors.error : .clear
            )
            .foregroundStyle(effectiveSandbox == "danger-full-access" ? DesignSystem.Colors.error : DesignSystem.Colors.textSecondary)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("Livello di accesso Codex (Default = legge da ~/.codex/config.toml)")
    }

    private var swarmOrchestratorPicker: some View {
        Menu {
            Button {
                swarmOrchestrator = "openai"
                syncSwarmProvider()
            } label: {
                HStack {
                    Text("OpenAI")
                    if swarmOrchestrator == "openai" {
                        Image(systemName: "checkmark")
                    }
                }
            }
            Button {
                swarmOrchestrator = "codex"
                syncSwarmProvider()
            } label: {
                HStack {
                    Text("Codex")
                    if swarmOrchestrator == "codex" {
                        Image(systemName: "checkmark")
                    }
                }
            }
        } label: {
            HStack(spacing: DesignSystem.Spacing.sm) {
                Image(systemName: "ant.fill")
                    .font(DesignSystem.Typography.caption)
                    .foregroundStyle(DesignSystem.Colors.swarmColor)
                Text(swarmOrchestrator == "openai" ? "Orchestrator: OpenAI" : "Orchestrator: Codex")
                    .font(DesignSystem.Typography.captionMedium)
                Image(systemName: "chevron.down")
                    .font(DesignSystem.Typography.caption2)
            }
            .padding(.horizontal, DesignSystem.Spacing.md)
            .padding(.vertical, DesignSystem.Spacing.sm)
            .liquidGlass(
                cornerRadius: DesignSystem.CornerRadius.medium,
                tint: DesignSystem.Colors.swarmColor
            )
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("Backend per l'orchestratore dello swarm")
    }
    
    private func accessLevelIcon(for sandbox: String) -> String {
        switch sandbox {
        case "read-only": return "lock.shield"
        case "workspace-write": return "shield"
        case "danger-full-access": return "exclamationmark.shield.fill"
        default: return "shield"
        }
    }
    
    private func accessLevelLabel(for sandbox: String) -> String {
        switch sandbox {
        case "read-only": return "Read Only"
        case "workspace-write": return "Default"
        case "danger-full-access": return "Full Access"
        default: return "Default"
        }
    }
    
    // MARK: - Messages Area
    private var messagesArea: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
                    if let conv = chatStore.conversation(for: conversationId) {
                        ForEach(conv.messages) { message in
                            MessageBubbleView(
                                message: message,
                                workspacePath: effectiveContext.primaryPath ?? "",
                                onFileClicked: { path in openFilesStore.openFile(path) }
                            )
                                .id(message.id)
                                .transition(.asymmetric(
                                    insertion: .opacity.combined(with: .move(edge: .bottom)),
                                    removal: .opacity
                                ))
                        }

                        if case .awaitingChoice(_, let options) = planningState {
                            PlanOptionsView(
                                options: options,
                                planColor: DesignSystem.Colors.planColor,
                                onSelectOption: { opt in executeWithPlanChoice(opt.fullText) },
                                onCustomResponse: { text in executeWithPlanChoice(text) }
                            )
                            .id("plan-options")
                            .transition(.opacity.combined(with: .move(edge: .bottom)))
                        }
                    }
                }
                .padding(DesignSystem.Spacing.md)
            }
            .onChange(of: chatStore.conversation(for: conversationId)?.messages.last?.content ?? "") { _, _ in
                if let last = chatStore.conversation(for: conversationId)?.messages.last {
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
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // MARK: - Task Timer Banner
    private func taskTimerBanner(startDate: Date) -> some View {
        TimelineView(.periodic(from: startDate, by: 1.0)) { context in
            let elapsed = Int(context.date.timeIntervalSince(startDate))
            HStack(spacing: DesignSystem.Spacing.md) {
                // Animated progress ring
                ZStack {
                    Circle()
                        .stroke(DesignSystem.Colors.warning.opacity(0.2), lineWidth: 2)
                    Circle()
                        .trim(from: 0, to: min(CGFloat(elapsed % 60) / 60, 1))
                        .stroke(DesignSystem.Colors.warning, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .animation(.linear(duration: 1), value: elapsed)
                }
                .frame(width: 20, height: 20)
                
                Text("Task in esecuzione")
                    .font(DesignSystem.Typography.subheadlineMedium)
                    .foregroundStyle(DesignSystem.Colors.textPrimary)
                
                Text("•")
                    .foregroundStyle(DesignSystem.Colors.textTertiary)
                
                Text("\(elapsed)s")
                    .font(DesignSystem.Typography.subheadline)
                    .foregroundStyle(DesignSystem.Colors.warning)
                    .monospacedDigit()
                
                Spacer()
                
                // Pulsing indicator
                Circle()
                    .fill(DesignSystem.Colors.warning)
                    .frame(width: 8, height: 8)
                    .opacity(0.5 + 0.5 * sin(context.date.timeIntervalSinceReferenceDate * 3))
            }
            .padding(.horizontal, DesignSystem.Spacing.lg)
            .padding(.vertical, DesignSystem.Spacing.md)
            .liquidGlass(
                cornerRadius: 0,
                tint: DesignSystem.Colors.warning
            )
            .overlay {
                Rectangle()
                    .frame(height: 0.5)
                    .foregroundStyle(DesignSystem.Colors.divider)
                    .frame(maxHeight: .infinity, alignment: .top)
            }
        }
    }
    
    // MARK: - Glass Input Area
    private var glassInputArea: some View {
        VStack(spacing: DesignSystem.Spacing.sm) {
            // Input hint
            HStack(spacing: DesignSystem.Spacing.xs) {
                Image(systemName: modeIcon(for: coderMode))
                    .font(DesignSystem.Typography.caption2)
                    .foregroundStyle(modeColor(for: coderMode))
                    .glow(color: modeColor(for: coderMode), radius: 4)
                Text(inputHint)
                    .font(DesignSystem.Typography.caption2)
                    .foregroundStyle(DesignSystem.Colors.textTertiary)
            }
            
            // Input field with glass effect
            HStack(alignment: .bottom, spacing: DesignSystem.Spacing.sm) {
                TextField("Scrivi un messaggio...", text: $inputText, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(DesignSystem.Typography.body)
                    .foregroundStyle(DesignSystem.Colors.textPrimary)
                    .lineLimit(1...6)
                    .focused($isInputFocused)
                    .onSubmit { sendMessage() }
                    .padding(DesignSystem.Spacing.sm)
                    .background {
                        RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.large)
                            .fill(.ultraThinMaterial)
                            .opacity(0.6)
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.large)
                            .stroke(
                                isInputFocused
                                    ? modeColor(for: coderMode).opacity(0.5)
                                    : Color.white.opacity(0.08),
                                lineWidth: isInputFocused ? 1 : 0.5
                            )
                    }
                    .animation(.easeOut(duration: 0.2), value: isInputFocused)
                
                // Send button
                sendButton
            }
            
            // Provider, Model, Reasoning, Full Access (sotto il campo input)
            HStack(spacing: DesignSystem.Spacing.sm) {
                providerPicker
                if providerRegistry.selectedProviderId == "codex-cli" {
                    codexModelPicker
                    codexReasoningPicker
                    accessLevelMenu
                    if coderMode == .agent || coderMode == .agentSwarm { formicaButton }
                } else if providerRegistry.selectedProviderId == "claude-cli" {
                    if coderMode == .agent || coderMode == .agentSwarm { formicaButton }
                } else if providerRegistry.selectedProviderId == "agent-swarm" {
                    swarmOrchestratorPicker
                    Button {
                        showSwarmHelp = true
                    } label: {
                        Image(systemName: "questionmark.circle")
                            .font(DesignSystem.Typography.title3)
                            .foregroundStyle(DesignSystem.Colors.swarmColor)
                    }
                    .buttonStyle(.plain)
                    .help("Agent Swarm guide")
                    if coderMode == .agent || coderMode == .agentSwarm { formicaButton }
                } else if providerRegistry.selectedProviderId == "plan-mode" {
                    Spacer()
                    if coderMode == .plan { formicaButton }
                } else if coderMode == .agent || coderMode == .agentSwarm || coderMode == .plan {
                    Spacer()
                    formicaButton
                } else {
                    Spacer()
                }
            }
        }
        .padding(.horizontal, DesignSystem.Spacing.md)
        .padding(.vertical, DesignSystem.Spacing.sm)
        .overlay {
            Rectangle()
                .frame(height: 0.5)
                .foregroundStyle(DesignSystem.Colors.divider)
                .frame(maxHeight: .infinity, alignment: .top)
        }
    }
    
    private var inputHint: String {
        switch coderMode {
        case .agent: return "L'agente può modificare file ed eseguire comandi"
        case .agentSwarm: return "Swarm di agenti specializzati (Planner, Coder, ecc.)"
        case .codeReviewMultiSwarm: return "Code review parallela su più swarm, report aggregato"
        case .plan: return "Piano con opzioni + possibilità di aggiungere risposta custom"
        case .ide: return "Modalità sola lettura - nessuna modifica ai file"
        case .mcpServer: return "Invia al server MCP configurato"
        }
    }
    
    private var sendButton: some View {
        let awaitingChoice = if case .awaitingChoice = planningState { true } else { false }
        let canSend = !inputText.isEmpty && !chatStore.isLoading && !awaitingChoice
        
        return Button(action: sendMessage) {
            ZStack {
                // Outer glow
                if canSend {
                    Circle()
                        .fill(modeColor(for: coderMode).opacity(0.3))
                        .frame(width: 44, height: 44)
                        .blur(radius: 8)
                }
                
                // Button
                Circle()
                    .fill(canSend
                          ? AnyShapeStyle(modeGradient(for: coderMode))
                          : AnyShapeStyle(Color.white.opacity(0.1)))
                    .frame(width: 40, height: 40)
                    .overlay {
                        Image(systemName: "arrow.up")
                            .font(DesignSystem.Typography.body.bold())
                            .foregroundStyle(canSend ? .white : DesignSystem.Colors.textTertiary)
                    }
                    .overlay {
                        Circle()
                            .stroke(canSend ? Color.white.opacity(0.2) : Color.clear, lineWidth: 0.5)
                    }
            }
        }
        .buttonStyle(.plain)
        .disabled(!canSend)
        .scaleEffect(canSend ? 1 : 0.95)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: canSend)
    }
    
    // MARK: - Actions
    private func syncCodexProvider() {
        let sandbox: CodexSandboxMode = CodexSandboxMode(rawValue: effectiveSandbox) ?? .workspaceWrite
        let provider = CodexCLIProvider(
            codexPath: codexPath.isEmpty ? nil : codexPath,
            sandboxMode: sandbox,
            modelOverride: codexModelOverride.isEmpty ? nil : codexModelOverride,
            modelReasoningEffort: codexReasoningEffort.isEmpty ? nil : codexReasoningEffort
        )
        providerRegistry.unregister(id: "codex-cli")
        providerRegistry.register(provider)
        syncSwarmProvider()
        syncPlanProvider()
    }

    private func syncSwarmProvider() {
        guard let codex = providerRegistry.provider(for: "codex-cli") as? CodexCLIProvider else { return }
        let backend: OrchestratorBackend = swarmOrchestrator == "codex" ? .codex : .openai
        let openAIClient: OpenAICompletionsClient? = backend == .openai && !openaiApiKey.isEmpty
            ? OpenAICompletionsClient(apiKey: openaiApiKey, model: openaiModel)
            : nil
        let config = SwarmConfig(
            orchestratorBackend: backend,
            autoPostCodePipeline: swarmAutoPostCodePipeline,
            maxPostCodeRetries: swarmMaxPostCodeRetries
        )
        let swarm = AgentSwarmProvider(config: config, openAIClient: openAIClient, codexProvider: codex)
        providerRegistry.unregister(id: "agent-swarm")
        providerRegistry.register(swarm)
    }

    private func syncMultiSwarmReviewProvider() {
        guard let codex = providerRegistry.provider(for: "codex-cli") as? CodexCLIProvider else { return }
        let sandbox: CodexSandboxMode = CodexSandboxMode(rawValue: effectiveSandbox) ?? .workspaceWrite
        let config = MultiSwarmReviewConfig(
            partitionCount: codeReviewPartitions,
            yoloMode: codeReviewYolo,
            enabledPhases: codeReviewAnalysisOnly ? ReviewPhase.analysisOnly : ReviewPhase.analysisAndExecution
        )
        let codexParams = CodexCreateParams(
            codexPath: codexPath.isEmpty ? nil : codexPath,
            sandboxMode: sandbox,
            modelOverride: codexModelOverride.isEmpty ? nil : codexModelOverride,
            modelReasoningEffort: codexReasoningEffort.isEmpty ? nil : codexReasoningEffort
        )
        let provider = MultiSwarmReviewProvider(config: config, codexProvider: codex, codexParams: codexParams)
        providerRegistry.unregister(id: "multi-swarm-review")
        providerRegistry.register(provider)
    }
    
    private func syncCoderModeToProvider(_ providerId: String?) {
        guard let id = providerId else { return }
        if id == "agent-swarm" {
            coderMode = .agentSwarm
            planningState = .idle
        } else if id == "multi-swarm-review" {
            coderMode = .codeReviewMultiSwarm
            planningState = .idle
        } else if id == "plan-mode" {
            coderMode = .plan
        } else if id == "codex-cli" || id == "claude-cli" {
            coderMode = .agent
            planningState = .idle
        } else if id == "openai-api" {
            coderMode = .ide
            planningState = .idle
        }
    }

    private func syncPlanProvider() {
        let codex = providerRegistry.provider(for: "codex-cli") as? CodexCLIProvider
        let claude = providerRegistry.provider(for: "claude-cli") as? ClaudeCLIProvider
        guard codex != nil || claude != nil else { return }
        let planProvider = PlanModeProvider(codexProvider: codex, claudeProvider: claude)
        providerRegistry.unregister(id: "plan-mode")
        providerRegistry.register(planProvider)
    }

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
        chatStore.addMessage(
            ChatMessage(role: .user, content: userMessage, isStreaming: false),
            to: conversationId
        )
        chatStore.addMessage(
            ChatMessage(role: .assistant, content: "", isStreaming: true),
            to: conversationId
        )
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

        let ctx = effectiveContext.toWorkspaceContext(
            openFiles: [],
            activeSelection: nil,
            activeFilePath: openFilesStore.openFilePath
        )

        Task {
            do {
                let stream = try await provider.send(prompt: executePrompt, context: ctx)
                var fullContent = ""
                for try await event in stream {
                    switch event {
                    case .textDelta(let delta):
                        fullContent += delta
                        chatStore.updateLastAssistantMessage(content: fullContent, in: conversationId)
                    case .completed, .started:
                        break
                    case .error(let err):
                        fullContent += "\n\n[Errore: \(err)]"
                        chatStore.updateLastAssistantMessage(content: fullContent, in: conversationId)
                    case .raw(let type, let payload):
                        if type == "coderide_show_task_panel" {
                            await MainActor.run { taskPanelEnabled = true }
                        }
                        if taskPanelEnabled {
                            let title = payload["title"] ?? type
                            let detail = payload["detail"]
                            let activity = TaskActivity(type: type, title: title, detail: detail, payload: payload)
                            await MainActor.run { taskActivityStore.addActivity(activity) }
                        }
                    }
                }
                chatStore.setLastAssistantStreaming(false, in: conversationId)
            } catch {
                chatStore.updateLastAssistantMessage(
                    content: "[Errore: \(error.localizedDescription)]",
                    in: conversationId
                )
                chatStore.setLastAssistantStreaming(false, in: conversationId)
            }
            chatStore.endTask()
        }
    }
    
    private func sendMessage() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        guard let provider = providerRegistry.selectedProvider else {
            return
        }
        guard provider.isAuthenticated() else {
            return
        }
        
        inputText = ""
        chatStore.addMessage(
            ChatMessage(role: .user, content: text, isStreaming: false),
            to: conversationId
        )
        chatStore.addMessage(
            ChatMessage(role: .assistant, content: "", isStreaming: true),
            to: conversationId
        )
        chatStore.beginTask()
        if taskPanelEnabled {
            taskActivityStore.clear()
        }
        if providerRegistry.selectedProviderId == "agent-swarm" {
            swarmProgressStore.clear()
        }

        let ctx = effectiveContext.toWorkspaceContext(
            openFiles: [],
            activeSelection: nil,
            activeFilePath: openFilesStore.openFilePath
        )
        var prompt = text
        if coderMode == .ide {
            prompt = "Rispondi solo con testo. Non modificare file né eseguire comandi.\n\n" + text
        }
        if coderMode == .mcpServer {
            prompt = "[MCP Server] " + text
        }
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
                    case .completed, .started:
                        break
                    case .error(let err):
                        fullContent += "\n\n[Errore: \(err)]"
                        chatStore.updateLastAssistantMessage(content: fullContent, in: conversationId)
                    case .raw(let type, let payload):
                        if type == "coderide_show_task_panel" {
                            await MainActor.run { taskPanelEnabled = true }
                        }
                        if type == "coderide_invoke_swarm", let task = payload["task"], !task.isEmpty {
                            pendingSwarmTask = task
                        }
                        if type == "swarm_steps", let stepsStr = payload["steps"], !stepsStr.isEmpty {
                            let names = stepsStr.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespaces) }
                            await MainActor.run { swarmProgressStore.setSteps(names) }
                        }
                        if type == "agent", let title = payload["title"], let detail = payload["detail"] {
                            if detail == "started" {
                                await MainActor.run { swarmProgressStore.markStarted(name: title) }
                            } else if detail == "completed" {
                                await MainActor.run { swarmProgressStore.markCompleted(name: title) }
                            }
                        }
                        if taskPanelEnabled {
                            let title = payload["title"] ?? type
                            let detail = payload["detail"]
                            let activity = TaskActivity(type: type, title: title, detail: detail, payload: payload)
                            await MainActor.run { taskActivityStore.addActivity(activity) }
                        }
                    }
                }
                chatStore.setLastAssistantStreaming(false, in: conversationId)

                if coderMode == .plan {
                    let options = PlanOptionsParser.parse(from: fullContent)
                    if !options.isEmpty {
                        await MainActor.run {
                            planningState = .awaitingChoice(planContent: fullContent, options: options)
                        }
                    }
                } else if let task = pendingSwarmTask, let swarm = providerRegistry.provider(for: "agent-swarm"), swarm.isAuthenticated() {
                    await MainActor.run {
                        providerRegistry.selectedProviderId = "agent-swarm"
                        coderMode = .agentSwarm
                    }
                    chatStore.addMessage(
                        ChatMessage(role: .user, content: "[Delegato allo swarm] \(task)", isStreaming: false),
                        to: conversationId
                    )
                    chatStore.addMessage(
                        ChatMessage(role: .assistant, content: "", isStreaming: true),
                        to: conversationId
                    )
                    chatStore.beginTask()
                    if taskPanelEnabled { taskActivityStore.clear() }
                    swarmProgressStore.clear()
                    do {
                        let swarmStream = try await swarm.send(prompt: task, context: ctx)
                        var swarmContent = ""
                        for try await ev in swarmStream {
                            switch ev {
                            case .textDelta(let d):
                                swarmContent += d
                                chatStore.updateLastAssistantMessage(content: swarmContent, in: conversationId)
                            case .raw(let t, let p):
                                if t == "coderide_show_task_panel" {
                                    await MainActor.run { taskPanelEnabled = true }
                                }
                                if t == "swarm_steps", let stepsStr = p["steps"], !stepsStr.isEmpty {
                                    let names = stepsStr.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespaces) }
                                    await MainActor.run { swarmProgressStore.setSteps(names) }
                                }
                                if t == "agent", let title = p["title"], let detail = p["detail"] {
                                    if detail == "started" {
                                        await MainActor.run { swarmProgressStore.markStarted(name: title) }
                                    } else if detail == "completed" {
                                        await MainActor.run { swarmProgressStore.markCompleted(name: title) }
                                    }
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
                chatStore.updateLastAssistantMessage(
                    content: "[Errore: \(error.localizedDescription)]",
                    in: conversationId
                )
                chatStore.setLastAssistantStreaming(false, in: conversationId)
            }
            chatStore.endTask()
        }
    }
}

// MARK: - Message Bubble View - Glass Style
struct MessageBubbleView: View {
    let message: ChatMessage
    let workspacePath: String
    let onFileClicked: (String) -> Void
    
    var body: some View {
        HStack(alignment: .top, spacing: DesignSystem.Spacing.md) {
            // Avatar
            avatar
                .frame(width: 36, height: 36)
            
            // Content
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
                // Header
                HStack(spacing: DesignSystem.Spacing.xs) {
                    Text(message.role == .user ? "Tu" : "Coder AI")
                        .font(DesignSystem.Typography.subheadlineMedium)
                        .foregroundStyle(message.role == .user ? DesignSystem.Colors.primary : DesignSystem.Colors.agentColor)
                    
                    if message.role == .assistant {
                        Image(systemName: "sparkles")
                            .font(DesignSystem.Typography.caption2)
                            .foregroundStyle(DesignSystem.Colors.agentColor)
                            .glow(color: DesignSystem.Colors.agentColor, radius: 3)
                    }
                }
                
                // Message content (with clickable file references)
                ClickableMessageContent(
                    content: message.content,
                    workspacePath: workspacePath,
                    onFileClicked: onFileClicked
                )
                .frame(maxWidth: .infinity, alignment: .leading)
                
                // Streaming indicator
                if message.isStreaming {
                    HStack(spacing: DesignSystem.Spacing.xs) {
                        // Typing dots animation
                        TypingIndicator()
                        Text("Sto scrivendo...")
                            .font(DesignSystem.Typography.caption)
                            .foregroundStyle(DesignSystem.Colors.textTertiary)
                    }
                }
            }
            .padding(DesignSystem.Spacing.lg)
            .frame(maxWidth: .infinity, alignment: .leading)
            .liquidGlass(
                cornerRadius: DesignSystem.CornerRadius.large,
                tint: message.role == .user ? DesignSystem.Colors.primary : DesignSystem.Colors.agentColor,
                borderOpacity: message.role == .user ? 0.1 : 0.05
            )
        }
    }
    
    private var avatar: some View {
        ZStack {
            // Glow effect
            Circle()
                .fill(message.role == .user
                      ? DesignSystem.Colors.primary.opacity(0.3)
                      : DesignSystem.Colors.agentColor.opacity(0.3))
                .frame(width: 40, height: 40)
                .blur(radius: 6)
            
            // Avatar circle
            Circle()
                .fill(message.role == .user
                      ? DesignSystem.Colors.primaryGradient
                      : DesignSystem.Colors.agentGradient)
                .overlay {
                    Image(systemName: message.role == .user ? "person.fill" : "brain.head.profile")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.white)
                }
                .overlay {
                    Circle()
                        .stroke(Color.white.opacity(0.2), lineWidth: 0.5)
                }
        }
    }
}

// MARK: - Typing Indicator
struct TypingIndicator: View {
    @State private var animatingDot = 0
    
    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .fill(DesignSystem.Colors.textTertiary)
                    .frame(width: 4, height: 4)
                    .scaleEffect(animatingDot == index ? 1.3 : 0.8)
                    .opacity(animatingDot == index ? 1 : 0.5)
            }
        }
        .onAppear {
            Timer.scheduledTimer(withTimeInterval: 0.4, repeats: true) { _ in
                withAnimation(.easeInOut(duration: 0.2)) {
                    animatingDot = (animatingDot + 1) % 3
                }
            }
        }
    }
}
