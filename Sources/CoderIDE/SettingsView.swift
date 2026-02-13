import SwiftUI
import AppKit
import CoderEngine

// Latest OpenAI models
let openAIModels = [
    "gpt-4o-mini",
    "gpt-4o",
    "gpt-4.5",
    "o1",
    "o1-mini", 
    "o1-preview",
    "o3",
    "o3-mini",
    "o4-mini",
    "gpt-4"
]

enum SettingsTab: String, CaseIterable {
    case openai = "OpenAI"
    case codex = "Codex"
    case claude = "Claude"
    case swarm = "Agent Swarm"
    case codeReview = "Code Review"
    case terminal = "Terminale"
    case appearance = "Aspetto"
    case mcp = "MCP"
    
    var icon: String {
        switch self {
        case .openai: return "brain.head.profile"
        case .codex: return "terminal"
        case .claude: return "sparkles"
        case .swarm: return "ant.fill"
        case .codeReview: return "doc.text.magnifyingglass"
        case .terminal: return "terminal.fill"
        case .appearance: return "paintbrush.fill"
        case .mcp: return "server.rack"
        }
    }
}

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var providerRegistry: ProviderRegistry
    @AppStorage("openai_api_key") private var apiKey = ""
    @AppStorage("openai_model") private var model = "gpt-4o-mini"
    @AppStorage("reasoning_effort") private var reasoningEffort = "medium"
    @AppStorage("codex_path") private var codexPath = ""
    @AppStorage("claude_path") private var claudePath = ""
    @AppStorage("appearance") private var appearance = "system"
    @AppStorage("full_auto_tools") private var fullAutoTools = true
    @AppStorage("codex_sandbox") private var codexSandbox = "workspace-write"
    @AppStorage("codex_model_override") private var codexModelOverride = ""
    @AppStorage("codex_reasoning_effort") private var codexReasoningEffort = "xhigh"
    @AppStorage("codex_session_full_access") private var codexSessionFullAccess = false
    @AppStorage("swarm_orchestrator") private var swarmOrchestrator = "openai"
    @AppStorage("swarm_auto_post_code_pipeline") private var swarmAutoPostCodePipeline = true
    @AppStorage("swarm_max_post_code_retries") private var swarmMaxPostCodeRetries = 10
    @AppStorage("code_review_yolo") private var codeReviewYolo = false
    @AppStorage("code_review_partitions") private var codeReviewPartitions = 3
    @AppStorage("code_review_analysis_only") private var codeReviewAnalysisOnly = false
    @AppStorage("plan_mode_backend") private var planModeBackend = "codex"
    @StateObject private var codexState = CodexStateStore()
    @State private var selectedTab: SettingsTab = .openai
    @State private var showCodexLogin = false
    
    var body: some View {
        ZStack {
            // Background
            AnimatedGradientBackground()
            
            // Floating orbs
            FloatingOrb(color: DesignSystem.Colors.primary, size: 200)
                .offset(x: -80, y: -80)
            FloatingOrb(color: DesignSystem.Colors.ideColor, size: 150)
                .offset(x: 150, y: 100)
            
            VStack(spacing: 0) {
                // Header
                settingsHeader
                
                // Main content
                HStack(spacing: DesignSystem.Spacing.md) {
                    // Sidebar
                    settingsSidebar
                        .liquidGlass(cornerRadius: DesignSystem.CornerRadius.xl, borderOpacity: 0.1)
                    
                    // Content
                    settingsContent
                        .liquidGlass(cornerRadius: DesignSystem.CornerRadius.xl, borderOpacity: 0.1)
                }
                .padding(DesignSystem.Spacing.md)
            }
        }
        .frame(width: 700, height: 550)
        .onAppear {
            codexState.refresh()
            syncProviders()
        }
        .sheet(isPresented: $showCodexLogin) {
            if let path = codexState.status.path ?? CodexDetector.findCodexPath(customPath: codexPath.isEmpty ? nil : codexPath) {
                CodexLoginView(codexPath: path) {
                    codexState.refresh()
                    syncCodex()
                }
            }
        }
        .onChange(of: apiKey) { _, _ in syncOpenAI() }
        .onChange(of: model) { _, _ in syncOpenAI() }
    }
    
    // MARK: - Settings Header
    private var settingsHeader: some View {
        HStack {
            Image(systemName: "gearshape.fill")
                .font(.title2)
                .foregroundStyle(DesignSystem.Colors.primary)
            Text("Impostazioni")
                .font(DesignSystem.Typography.title2)
            Spacer()
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title2)
                    .foregroundStyle(DesignSystem.Colors.textSecondary)
            }
            .buttonStyle(.plain)
            .hoverEffect(scale: 1.1)
        }
        .padding(.horizontal, DesignSystem.Spacing.md)
        .padding(.vertical, DesignSystem.Spacing.sm)
        .overlay {
            Rectangle()
                .frame(height: 0.5)
                .foregroundStyle(DesignSystem.Colors.divider)
                .frame(maxHeight: .infinity, alignment: .bottom)
        }
    }
    
    // MARK: - Settings Sidebar
    private var settingsSidebar: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
            ForEach(SettingsTab.allCases, id: \.self) { tab in
                settingsTabButton(for: tab)
            }
        }
        .padding(DesignSystem.Spacing.sm)
        .frame(width: 140)
    }
    
    private func settingsTabButton(for tab: SettingsTab) -> some View {
        let isSelected = selectedTab == tab
        
        return Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                selectedTab = tab
            }
        } label: {
            HStack(spacing: DesignSystem.Spacing.sm) {
                Image(systemName: tab.icon)
                    .font(DesignSystem.Typography.subheadline)
                
                Text(tab.rawValue)
                    .font(DesignSystem.Typography.subheadlineMedium)
                    .lineLimit(1)
            }
            .foregroundStyle(isSelected ? DesignSystem.Colors.textPrimary : DesignSystem.Colors.textTertiary)
            .padding(.horizontal, DesignSystem.Spacing.sm)
            .padding(.vertical, DesignSystem.Spacing.sm)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium)
                        .fill(DesignSystem.Colors.primary.opacity(0.15))
                        .overlay {
                            RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium)
                                .stroke(DesignSystem.Colors.primary.opacity(0.3), lineWidth: 0.5)
                        }
                }
            }
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - Settings Content
    @ViewBuilder
    private var settingsContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
                switch selectedTab {
                case .openai:
                    openAIContent
                case .codex:
                    codexContent
                case .claude:
                    claudeContent
                case .swarm:
                    swarmContent
                case .codeReview:
                    codeReviewContent
                case .terminal:
                    terminalContent
                case .appearance:
                    appearanceContent
                case .mcp:
                    mcpContent
                }
            }
            .padding(DesignSystem.Spacing.md)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // MARK: - OpenAI Content
    private var openAIContent: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
            sectionHeader("OpenAI API", icon: "brain.head.profile")
            
            settingsField("API Key") {
                SecureField("sk-...", text: $apiKey)
                    .textFieldStyle(.plain)
            }
            
            settingsField("Modello") {
                Picker("", selection: $model) {
                    ForEach(openAIModels, id: \.self) { m in
                        Text(m).tag(m)
                    }
                }
                .pickerStyle(.menu)
            }
            
            if OpenAIAPIProvider.isReasoningModel(model) {
                settingsField("Reasoning Effort") {
                    Picker("", selection: $reasoningEffort) {
                        Text("Low").tag("low")
                        Text("Medium").tag("medium")
                        Text("High").tag("high")
                    }
                    .pickerStyle(.segmented)
                }
            }
        }
    }
    
    // MARK: - Codex Content
    private var codexContent: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
            sectionHeader("Codex CLI", icon: "terminal")
            
            // Connect button
            HStack {
                Button(action: connectToCodex) {
                    HStack(spacing: DesignSystem.Spacing.xs) {
                        Image(systemName: codexState.status.isLoggedIn ? "checkmark.circle.fill" : "bolt.fill")
                        Text(codexState.status.isLoggedIn ? "Connesso" : "Connect")
                    }
                    .font(DesignSystem.Typography.subheadline.bold())
                    .padding(.horizontal, DesignSystem.Spacing.md)
                    .padding(.vertical, DesignSystem.Spacing.sm)
                    .background(codexState.status.isLoggedIn ? DesignSystem.Colors.success : DesignSystem.Colors.primary)
                    .foregroundColor(.white)
                    .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium))
                }
                .buttonStyle(.plain)
                .disabled(codexState.status.isLoggedIn)
                
                if codexState.status.isLoggedIn {
                    Text("Codex CLI connesso")
                        .font(DesignSystem.Typography.caption)
                        .foregroundStyle(DesignSystem.Colors.success)
                }
            }
            
            settingsField("Path") {
                TextField("Lascia vuoto per auto-detect", text: $codexPath)
                    .textFieldStyle(.plain)
                    .onChange(of: codexPath) { _, _ in
                        codexState.refresh()
                        syncCodex()
                    }
            }
            
            settingsField("Sandbox") {
                Picker("", selection: $codexSandbox) {
                    Text("Read-only").tag("read-only")
                    Text("Workspace write").tag("workspace-write")
                    Text("Full access (⚠️)").tag("danger-full-access")
                }
                .pickerStyle(.segmented)
                .onChange(of: codexSandbox) { _, _ in syncCodex() }
            }
            
            settingsField("Modello Override") {
                TextField("es. o3, o4-mini", text: $codexModelOverride)
                    .textFieldStyle(.plain)
                    .onChange(of: codexModelOverride) { _, _ in syncCodex() }
            }
            
            settingsField("Backend Plan mode") {
                Picker("", selection: $planModeBackend) {
                    Text("Codex").tag("codex")
                    Text("Claude").tag("claude")
                }
                .pickerStyle(.segmented)
            }
            
            // Status
            HStack(spacing: DesignSystem.Spacing.sm) {
                if !codexState.status.isInstalled {
                    statusBadge(.error, "Non installato")
                    Text("brew install codex")
                        .font(DesignSystem.Typography.caption)
                        .foregroundStyle(DesignSystem.Colors.textTertiary)
                } else if codexState.status.isLoggedIn {
                    statusBadge(.online, "Connesso")
                } else {
                    statusBadge(.offline, "Non connesso")
                }
            }
        }
    }
    
    // MARK: - Swarm Content
    private var swarmContent: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
            sectionHeader("Agent Swarm", icon: "ant.fill")

            Text("Orchestratore: decide il piano e assegna task a Planner, Coder, Debugger, Reviewer, DocWriter, SecurityAuditor, TestWriter. I worker usano sempre Codex.")
                .font(DesignSystem.Typography.caption)
                .foregroundStyle(DesignSystem.Colors.textTertiary)

            settingsField("Backend Orchestratore") {
                Picker("", selection: $swarmOrchestrator) {
                    Text("OpenAI (leggero)").tag("openai")
                    Text("Codex").tag("codex")
                }
                .pickerStyle(.segmented)
                .onChange(of: swarmOrchestrator) { _, _ in syncSwarm() }
            }

            Toggle("Pipeline QA dopo Coder (Reviewer + TestWriter + test)", isOn: $swarmAutoPostCodePipeline)
                .font(DesignSystem.Typography.subheadline)
                .foregroundStyle(DesignSystem.Colors.textPrimary)
                .onChange(of: swarmAutoPostCodePipeline) { _, _ in syncSwarm() }

            if swarmAutoPostCodePipeline {
                settingsField("Max tentativi correzione (loop fino a test OK)") {
                    Stepper("\(swarmMaxPostCodeRetries)", value: $swarmMaxPostCodeRetries, in: 1...50)
                        .onChange(of: swarmMaxPostCodeRetries) { _, _ in syncSwarm() }
                }
            }
        }
    }

    // MARK: - Code Review Content
    private var codeReviewContent: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
            sectionHeader("Code Review Multi-Swarm", icon: "doc.text.magnifyingglass")

            Text("Analisi parallela su più swarm, report aggregato. Opzione di applicare correzioni con coordinamento file.")
                .font(DesignSystem.Typography.caption)
                .foregroundStyle(DesignSystem.Colors.textTertiary)

            Toggle("Modalità --yolo (procedi senza conferma)", isOn: $codeReviewYolo)
                .font(DesignSystem.Typography.subheadline)
                .foregroundStyle(DesignSystem.Colors.textPrimary)
                .onChange(of: codeReviewYolo) { _, _ in syncCodeReview() }

            settingsField("Numero swarm/partizioni") {
                Stepper("\(codeReviewPartitions)", value: $codeReviewPartitions, in: 2...8)
                    .onChange(of: codeReviewPartitions) { _, _ in syncCodeReview() }
            }

            Toggle("Solo analisi (disabilita Fase 2)", isOn: $codeReviewAnalysisOnly)
                .font(DesignSystem.Typography.subheadline)
                .foregroundStyle(DesignSystem.Colors.textPrimary)
                .onChange(of: codeReviewAnalysisOnly) { _, _ in syncCodeReview() }
        }
    }

    // MARK: - Claude Content
    private var claudeContent: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
            sectionHeader("Claude Code CLI", icon: "sparkles")
            
            settingsField("Path") {
                TextField("Lascia vuoto per auto-detect", text: $claudePath)
                    .textFieldStyle(.plain)
                    .onChange(of: claudePath) { _, _ in syncClaude() }
            }
        }
    }
    
    // MARK: - Terminal Content
    private var terminalContent: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
            sectionHeader("Terminale", icon: "terminal.fill")
            
            Text("Per il terminale integrato con shell interattiva serve accesso al sistema.")
                .font(DesignSystem.Typography.caption)
                .foregroundStyle(DesignSystem.Colors.textTertiary)
            
            Button(action: openFullDiskAccessPreferences) {
                Label("Apri Impostazioni: Full Disk Access", systemImage: "lock.open")
                    .font(DesignSystem.Typography.subheadline)
            }
            .buttonStyle(SecondaryButtonStyle())
            
            Text("Aggiungi Codigo all'elenco e attiva l'interruttore. Riavvia l'app dopo la modifica.")
                .font(DesignSystem.Typography.caption)
                .foregroundStyle(DesignSystem.Colors.textTertiary)
        }
    }
    
    // MARK: - Appearance Content
    private var appearanceContent: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
            sectionHeader("Aspetto", icon: "paintbrush.fill")
            
            settingsField("Tema") {
                Picker("", selection: $appearance) {
                    Label("Sistema", systemImage: "circle.lefthalf.filled").tag("system")
                    Label("Chiaro", systemImage: "sun.max").tag("light")
                    Label("Scuro", systemImage: "moon").tag("dark")
                }
                .pickerStyle(.segmented)
            }
            
            Toggle("Auto-approvazione strumenti (Codex/Claude)", isOn: $fullAutoTools)
                .font(DesignSystem.Typography.subheadline)
                .foregroundStyle(DesignSystem.Colors.textPrimary)
        }
    }
    
    // MARK: - MCP Content
    private var mcpContent: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
            sectionHeader("MCP Servers", icon: "server.rack")
            
            MCPSettingsSection()
        }
    }
    
    // MARK: - Helper Views
    private func sectionHeader(_ title: String, icon: String) -> some View {
        HStack(spacing: DesignSystem.Spacing.sm) {
            Image(systemName: icon)
                .font(DesignSystem.Typography.subheadline)
                .foregroundStyle(DesignSystem.Colors.primary)
            Text(title)
                .font(DesignSystem.Typography.headline)
                .foregroundStyle(DesignSystem.Colors.textPrimary)
        }
    }
    
    private func settingsField<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
            Text(label)
                .font(DesignSystem.Typography.captionMedium)
                .foregroundStyle(DesignSystem.Colors.textTertiary)
            content()
                .padding(DesignSystem.Spacing.sm)
                .liquidGlass(cornerRadius: DesignSystem.CornerRadius.medium)
        }
    }
    
    private func statusBadge(_ status: StatusIndicator.Status, _ text: String) -> some View {
        HStack(spacing: DesignSystem.Spacing.xs) {
            Image(systemName: status.icon)
                .font(DesignSystem.Typography.caption2)
            Text(text)
                .font(DesignSystem.Typography.caption)
        }
        .foregroundStyle(status.color)
        .padding(.horizontal, DesignSystem.Spacing.sm)
        .padding(.vertical, DesignSystem.Spacing.xs)
        .liquidGlass(cornerRadius: DesignSystem.CornerRadius.small, tint: status.color)
    }
    
    // MARK: - Actions
    private func connectToCodex() {
        // Try to detect Codex and login
        if codexState.status.path != nil || CodexDetector.findCodexPath(customPath: codexPath.isEmpty ? nil : codexPath) != nil {
            if codexState.status.isLoggedIn {
                // Already logged in, just sync
                syncCodex()
            } else {
                // Show login
                showCodexLogin = true
            }
        }
    }
    
    private func syncProviders() {
        syncOpenAI()
        syncCodex()
        syncClaude()
        syncSwarm()
        syncCodeReview()
        syncPlanProvider()
    }
    
    private func syncPlanProvider() {
        let codex = providerRegistry.provider(for: "codex-cli") as? CodexCLIProvider
        let claude = providerRegistry.provider(for: "claude-cli") as? ClaudeCLIProvider
        guard codex != nil || claude != nil else { return }
        let planProvider = PlanModeProvider(codexProvider: codex, claudeProvider: claude)
        providerRegistry.unregister(id: "plan-mode")
        providerRegistry.register(planProvider)
    }
    
    private func syncOpenAI() {
        let effort = OpenAIAPIProvider.isReasoningModel(model) ? reasoningEffort : nil
        let provider = OpenAIAPIProvider(apiKey: apiKey, model: model, reasoningEffort: effort)
        providerRegistry.unregister(id: "openai-api")
        providerRegistry.register(provider)
    }
    
    private func syncCodex() {
        let sandbox: CodexSandboxMode = codexSessionFullAccess ? .dangerFullAccess : (CodexSandboxMode(rawValue: codexSandbox) ?? .workspaceWrite)
        let provider = CodexCLIProvider(
            codexPath: codexPath.isEmpty ? nil : codexPath,
            sandboxMode: sandbox,
            modelOverride: codexModelOverride.isEmpty ? nil : codexModelOverride,
            modelReasoningEffort: codexReasoningEffort.isEmpty ? nil : codexReasoningEffort
        )
        providerRegistry.unregister(id: "codex-cli")
        providerRegistry.register(provider)
    }
    
    private func openFullDiskAccessPreferences() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
            NSWorkspace.shared.open(url)
        }
    }
    
    private func syncClaude() {
        let provider = ClaudeCLIProvider(claudePath: claudePath.isEmpty ? nil : claudePath)
        providerRegistry.unregister(id: "claude-cli")
        providerRegistry.register(provider)
    }

    private func syncSwarm() {
        guard let codex = providerRegistry.provider(for: "codex-cli") as? CodexCLIProvider else { return }
        let backend: OrchestratorBackend = swarmOrchestrator == "codex" ? .codex : .openai
        let openAIClient: OpenAICompletionsClient? = backend == .openai && !apiKey.isEmpty
            ? OpenAICompletionsClient(apiKey: apiKey, model: model)
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

    private func syncCodeReview() {
        guard let codex = providerRegistry.provider(for: "codex-cli") as? CodexCLIProvider else { return }
        let sandbox: CodexSandboxMode = codexSessionFullAccess ? .dangerFullAccess : (CodexSandboxMode(rawValue: codexSandbox) ?? .workspaceWrite)
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
}
