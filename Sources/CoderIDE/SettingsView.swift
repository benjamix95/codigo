import SwiftUI
import AppKit
import CoderEngine

let openAIModels = [
    "gpt-4o-mini", "gpt-4o", "gpt-4.5", "o1", "o1-mini",
    "o1-preview", "o3", "o3-mini", "o4-mini", "gpt-4"
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
    @State private var showCodexLogin = false

    var body: some View {
        TabView {
            openAITab
            codexTab
            claudeTab
            swarmTab
            codeReviewTab
            terminalTab
            appearanceTab
            mcpTab
        }
        .frame(width: 560, height: 460)
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

    // MARK: - OpenAI Tab
    private var openAITab: some View {
        Form {
            Section("API") {
                SecureField("API Key", text: $apiKey, prompt: Text("sk-..."))
                Picker("Modello", selection: $model) {
                    ForEach(openAIModels, id: \.self) { m in Text(m).tag(m) }
                }
                if OpenAIAPIProvider.isReasoningModel(model) {
                    Picker("Reasoning Effort", selection: $reasoningEffort) {
                        Text("Low").tag("low")
                        Text("Medium").tag("medium")
                        Text("High").tag("high")
                    }
                    .pickerStyle(.segmented)
                }
            }
        }
        .formStyle(.grouped)
        .tabItem { Label("OpenAI", systemImage: "brain.head.profile") }
    }

    // MARK: - Codex Tab
    private var codexTab: some View {
        Form {
            Section("Connessione") {
                HStack {
                    Button(action: connectToCodex) {
                        Label(
                            codexState.status.isLoggedIn ? "Connesso" : "Connect",
                            systemImage: codexState.status.isLoggedIn ? "checkmark.circle.fill" : "bolt.fill"
                        )
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(codexState.status.isLoggedIn ? .green : .accentColor)
                    .disabled(codexState.status.isLoggedIn)

                    if codexState.status.isLoggedIn {
                        Text("Codex CLI connesso")
                            .font(.caption)
                            .foregroundStyle(.green)
                    }
                }

                if !codexState.status.isInstalled {
                    HStack(spacing: 4) {
                        Image(systemName: "exclamationmark.circle.fill")
                            .foregroundStyle(.red)
                            .font(.caption)
                        Text("Non installato — brew install codex")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section("Configurazione") {
                TextField("Path (vuoto per auto-detect)", text: $codexPath)
                    .onChange(of: codexPath) { _, _ in
                        codexState.refresh()
                        syncCodex()
                    }

                Picker("Sandbox", selection: $codexSandbox) {
                    Text("Read-only").tag("read-only")
                    Text("Workspace write").tag("workspace-write")
                    Text("Full access").tag("danger-full-access")
                }
                .pickerStyle(.segmented)
                .onChange(of: codexSandbox) { _, _ in syncCodex() }

                TextField("Modello Override (es. o3, o4-mini)", text: $codexModelOverride)
                    .onChange(of: codexModelOverride) { _, _ in syncCodex() }

                Picker("Backend Plan mode", selection: $planModeBackend) {
                    Text("Codex").tag("codex")
                    Text("Claude").tag("claude")
                }
                .pickerStyle(.segmented)
            }
        }
        .formStyle(.grouped)
        .tabItem { Label("Codex", systemImage: "terminal") }
    }

    // MARK: - Claude Tab
    private var claudeTab: some View {
        Form {
            Section("Claude Code CLI") {
                TextField("Path (vuoto per auto-detect)", text: $claudePath)
                    .onChange(of: claudePath) { _, _ in syncClaude() }
            }
        }
        .formStyle(.grouped)
        .tabItem { Label("Claude", systemImage: "sparkles") }
    }

    // MARK: - Swarm Tab
    private var swarmTab: some View {
        Form {
            Section {
                Text("Orchestratore: decide il piano e assegna task a Planner, Coder, Debugger, Reviewer, DocWriter, SecurityAuditor, TestWriter.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Picker("Backend Orchestratore", selection: $swarmOrchestrator) {
                    Text("OpenAI (leggero)").tag("openai")
                    Text("Codex").tag("codex")
                }
                .pickerStyle(.segmented)
                .onChange(of: swarmOrchestrator) { _, _ in syncSwarm() }

                Toggle("Pipeline QA dopo Coder (Reviewer + TestWriter + test)", isOn: $swarmAutoPostCodePipeline)
                    .onChange(of: swarmAutoPostCodePipeline) { _, _ in syncSwarm() }

                if swarmAutoPostCodePipeline {
                    Stepper("Max tentativi correzione: \(swarmMaxPostCodeRetries)", value: $swarmMaxPostCodeRetries, in: 1...50)
                        .onChange(of: swarmMaxPostCodeRetries) { _, _ in syncSwarm() }
                }
            } header: {
                Text("Agent Swarm")
            }
        }
        .formStyle(.grouped)
        .tabItem { Label("Swarm", systemImage: "ant.fill") }
    }

    // MARK: - Code Review Tab
    private var codeReviewTab: some View {
        Form {
            Section {
                Text("Analisi parallela su più swarm, report aggregato. Opzione di applicare correzioni.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Toggle("Modalità --yolo (procedi senza conferma)", isOn: $codeReviewYolo)
                    .onChange(of: codeReviewYolo) { _, _ in syncCodeReview() }

                Stepper("Numero swarm/partizioni: \(codeReviewPartitions)", value: $codeReviewPartitions, in: 2...8)
                    .onChange(of: codeReviewPartitions) { _, _ in syncCodeReview() }

                Toggle("Solo analisi (disabilita Fase 2)", isOn: $codeReviewAnalysisOnly)
                    .onChange(of: codeReviewAnalysisOnly) { _, _ in syncCodeReview() }
            } header: {
                Text("Code Review Multi-Swarm")
            }
        }
        .formStyle(.grouped)
        .tabItem { Label("Review", systemImage: "doc.text.magnifyingglass") }
    }

    // MARK: - Terminal Tab
    private var terminalTab: some View {
        Form {
            Section("Terminale") {
                Text("Per il terminale integrato serve accesso Full Disk Access.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Button(action: openFullDiskAccessPreferences) {
                    Label("Apri Impostazioni: Full Disk Access", systemImage: "lock.open")
                }

                Text("Aggiungi Codigo all'elenco e attiva l'interruttore. Riavvia dopo la modifica.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .tabItem { Label("Terminale", systemImage: "terminal.fill") }
    }

    // MARK: - Appearance Tab
    private var appearanceTab: some View {
        Form {
            Section("Aspetto") {
                Picker("Tema", selection: $appearance) {
                    Label("Sistema", systemImage: "circle.lefthalf.filled").tag("system")
                    Label("Chiaro", systemImage: "sun.max").tag("light")
                    Label("Scuro", systemImage: "moon").tag("dark")
                }
                .pickerStyle(.segmented)

                Toggle("Auto-approvazione strumenti (Codex/Claude)", isOn: $fullAutoTools)
            }
        }
        .formStyle(.grouped)
        .tabItem { Label("Aspetto", systemImage: "paintbrush.fill") }
    }

    // MARK: - MCP Tab
    private var mcpTab: some View {
        ScrollView {
            MCPSettingsSection()
                .padding()
        }
        .tabItem { Label("MCP", systemImage: "server.rack") }
    }

    // MARK: - Actions
    private func connectToCodex() {
        if codexState.status.path != nil || CodexDetector.findCodexPath(customPath: codexPath.isEmpty ? nil : codexPath) != nil {
            if codexState.status.isLoggedIn {
                syncCodex()
            } else {
                showCodexLogin = true
            }
        }
    }

    private func syncProviders() {
        syncOpenAI(); syncCodex(); syncClaude(); syncSwarm(); syncCodeReview(); syncPlanProvider()
    }

    private func syncPlanProvider() {
        let codex = providerRegistry.provider(for: "codex-cli") as? CodexCLIProvider
        let claude = providerRegistry.provider(for: "claude-cli") as? ClaudeCLIProvider
        guard codex != nil || claude != nil else { return }
        providerRegistry.unregister(id: "plan-mode")
        providerRegistry.register(PlanModeProvider(codexProvider: codex, claudeProvider: claude))
    }

    private func syncOpenAI() {
        let effort = OpenAIAPIProvider.isReasoningModel(model) ? reasoningEffort : nil
        providerRegistry.unregister(id: "openai-api")
        providerRegistry.register(OpenAIAPIProvider(apiKey: apiKey, model: model, reasoningEffort: effort))
    }

    private func syncCodex() {
        let sandbox: CodexSandboxMode = codexSessionFullAccess ? .dangerFullAccess : (CodexSandboxMode(rawValue: codexSandbox) ?? .workspaceWrite)
        providerRegistry.unregister(id: "codex-cli")
        providerRegistry.register(CodexCLIProvider(
            codexPath: codexPath.isEmpty ? nil : codexPath,
            sandboxMode: sandbox,
            modelOverride: codexModelOverride.isEmpty ? nil : codexModelOverride,
            modelReasoningEffort: codexReasoningEffort.isEmpty ? nil : codexReasoningEffort
        ))
    }

    private func openFullDiskAccessPreferences() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
            NSWorkspace.shared.open(url)
        }
    }

    private func syncClaude() {
        providerRegistry.unregister(id: "claude-cli")
        providerRegistry.register(ClaudeCLIProvider(claudePath: claudePath.isEmpty ? nil : claudePath))
    }

    private func syncSwarm() {
        guard let codex = providerRegistry.provider(for: "codex-cli") as? CodexCLIProvider else { return }
        let backend: OrchestratorBackend = swarmOrchestrator == "codex" ? .codex : .openai
        let openAIClient: OpenAICompletionsClient? = backend == .openai && !apiKey.isEmpty
            ? OpenAICompletionsClient(apiKey: apiKey, model: model) : nil
        let config = SwarmConfig(orchestratorBackend: backend, autoPostCodePipeline: swarmAutoPostCodePipeline, maxPostCodeRetries: swarmMaxPostCodeRetries)
        providerRegistry.unregister(id: "agent-swarm")
        providerRegistry.register(AgentSwarmProvider(config: config, openAIClient: openAIClient, codexProvider: codex))
    }

    private func syncCodeReview() {
        guard let codex = providerRegistry.provider(for: "codex-cli") as? CodexCLIProvider else { return }
        let sandbox: CodexSandboxMode = codexSessionFullAccess ? .dangerFullAccess : (CodexSandboxMode(rawValue: codexSandbox) ?? .workspaceWrite)
        let config = MultiSwarmReviewConfig(
            partitionCount: codeReviewPartitions, yoloMode: codeReviewYolo,
            enabledPhases: codeReviewAnalysisOnly ? ReviewPhase.analysisOnly : ReviewPhase.analysisAndExecution
        )
        let codexParams = CodexCreateParams(
            codexPath: codexPath.isEmpty ? nil : codexPath, sandboxMode: sandbox,
            modelOverride: codexModelOverride.isEmpty ? nil : codexModelOverride,
            modelReasoningEffort: codexReasoningEffort.isEmpty ? nil : codexReasoningEffort
        )
        providerRegistry.unregister(id: "multi-swarm-review")
        providerRegistry.register(MultiSwarmReviewProvider(config: config, codexProvider: codex, codexParams: codexParams))
    }
}
