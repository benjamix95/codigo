import SwiftUI
import AppKit
import CoderEngine

// MARK: - Model Lists

let openAIModels = [
    "gpt-5.3-codex", "gpt-5.2-instant", "gpt-5.2-thinking",
    "o3", "o3-pro", "o4-mini",
    "gpt-4o", "gpt-4o-mini", "gpt-4.5"
]

let anthropicModels = [
    "claude-opus-4-6", "claude-sonnet-4-6",
    "claude-haiku-4-5-20251001",
    "claude-opus-4", "claude-sonnet-4"
]

let googleModels = [
    "gemini-3-pro", "gemini-3-flash-preview",
    "gemini-2.5-pro", "gemini-2.5-flash", "gemini-2.5-flash-lite"
]

let openRouterPopularModels = [
    "anthropic/claude-opus-4-6", "anthropic/claude-sonnet-4-6",
    "google/gemini-3-pro", "google/gemini-2.5-pro",
    "minimax/minimax-m2.5",
    "z-ai/glm-5",
    "qwen/qwen3.5-plus-2025-01-25", "qwen/qwen3-coder-480b-a35b",
    "meta-llama/llama-4-maverick",
    "deepseek/deepseek-r1"
]

let openRouterFreeModels = [
    "z-ai/glm-4.5-air:free",
    "qwen/qwen3-next-80b:free",
    "deepseek/deepseek-r1-0528:free",
    "meta-llama/llama-3.3-70b-instruct:free",
    "google/gemma-3-27b-it:free",
    "mistralai/mistral-small-3.1-24b-instruct:free"
]

let minimaxModels = [
    "MiniMax-M2.5", "MiniMax-M2.1", "MiniMax-M2.1-lightning", "MiniMax-M2"
]

// MARK: - Settings Navigation

enum SettingsSection: String, CaseIterable, Identifiable {
    case openai = "OpenAI"
    case anthropic = "Anthropic"
    case google = "Google Gemini"
    case minimax = "MiniMax"
    case openrouter = "OpenRouter"
    case codex = "Codex CLI"
    case claudeCli = "Claude Code"
    case geminiCli = "Gemini CLI"
    case swarm = "Agent Swarm"
    case codeReview = "Code Review"
    case terminal = "Terminale"
    case behavior = "Comportamento"
    case appearance = "Aspetto"
    case mcp = "MCP"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .openai: return "brain.head.profile"
        case .anthropic: return "sparkle"
        case .google: return "globe"
        case .minimax: return "bolt.horizontal.fill"
        case .openrouter: return "arrow.triangle.branch"
        case .codex: return "terminal"
        case .claudeCli: return "sparkles"
        case .geminiCli: return "globe"
        case .swarm: return "ant.fill"
        case .codeReview: return "doc.text.magnifyingglass"
        case .terminal: return "terminal.fill"
        case .behavior: return "bolt.fill"
        case .appearance: return "paintbrush.fill"
        case .mcp: return "server.rack"
        }
    }

    static var providers: [SettingsSection] { [.openai, .anthropic, .google, .minimax, .openrouter] }
    static var tools: [SettingsSection] { [.codex, .claudeCli, .geminiCli, .swarm, .codeReview] }
    static var general: [SettingsSection] { [.terminal, .behavior, .appearance, .mcp] }
}

// MARK: - Settings View

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var providerRegistry: ProviderRegistry
    @EnvironmentObject var executionController: ExecutionController
    @EnvironmentObject var providerUsageStore: ProviderUsageStore
    @State private var selectedSection: SettingsSection = .openai

    // OpenAI
    @AppStorage("openai_api_key") private var openaiApiKey = ""
    @AppStorage("openai_model") private var openaiModel = "gpt-4o-mini"
    @AppStorage("reasoning_effort") private var reasoningEffort = "medium"

    // Anthropic
    @AppStorage("anthropic_api_key") private var anthropicApiKey = ""
    @AppStorage("anthropic_model") private var anthropicModel = "claude-sonnet-4-6"

    // Google
    @AppStorage("google_api_key") private var googleApiKey = ""
    @AppStorage("google_model") private var googleModel = "gemini-2.5-pro"

    // MiniMax
    @AppStorage("minimax_api_key") private var minimaxApiKey = ""
    @AppStorage("minimax_model") private var minimaxModel = "MiniMax-M2.5"

    // OpenRouter
    @AppStorage("openrouter_api_key") private var openrouterApiKey = ""
    @AppStorage("openrouter_model") private var openrouterModel = "anthropic/claude-sonnet-4-6"

    // Codex
    @AppStorage("codex_path") private var codexPath = ""
    @AppStorage("codex_sandbox") private var codexSandbox = "workspace-write"
    @AppStorage("codex_ask_for_approval") private var codexAskForApproval = "never"
    @AppStorage("codex_model_override") private var codexModelOverride = ""
    @AppStorage("codex_reasoning_effort") private var codexReasoningEffort = "xhigh"
    @AppStorage("codex_session_full_access") private var codexSessionFullAccess = false
    @AppStorage("plan_mode_backend") private var planModeBackend = "codex"

    // Codex advanced (config.toml)
    @AppStorage("codex_reasoning_summary") private var codexReasoningSummary = "auto"
    @AppStorage("codex_verbosity") private var codexVerbosity = "medium"
    @AppStorage("codex_personality") private var codexPersonality = "none"
    @AppStorage("codex_network_access") private var codexNetworkAccess = false
    @AppStorage("codex_additional_write_roots") private var codexAdditionalWriteRoots = ""
    @AppStorage("codex_developer_instructions") private var codexDeveloperInstructions = ""
    @AppStorage("codex_check_update") private var codexCheckUpdate = true

    // Claude CLI
    @AppStorage("claude_path") private var claudePath = ""
    @AppStorage("claude_model") private var claudeModel = "sonnet"
    @AppStorage("claude_allowed_tools") private var claudeAllowedTools = "Read,Edit,Bash,Write,Search"
    @AppStorage("gemini_cli_path") private var geminiCliPath = ""

    // Swarm
    @AppStorage("swarm_orchestrator") private var swarmOrchestrator = "openai"
    @AppStorage("swarm_worker_backend") private var swarmWorkerBackend = "codex"
    @AppStorage("swarm_auto_post_code_pipeline") private var swarmAutoPostCodePipeline = true
    @AppStorage("swarm_max_post_code_retries") private var swarmMaxPostCodeRetries = 10
    @AppStorage("swarm_max_review_loops") private var swarmMaxReviewLoops = 2
    @AppStorage("swarm_enabled_roles") private var swarmEnabledRoles = "planner,coder,debugger,reviewer,testWriter"

    // Code Review
    @AppStorage("global_yolo") private var globalYolo = false
    @AppStorage("summarize_threshold") private var summarizeThreshold = 0.8
    @AppStorage("summarize_keep_last") private var summarizeKeepLast = 6
    @AppStorage("summarize_provider") private var summarizeProvider = "openai-api"
    @AppStorage("code_review_partitions") private var codeReviewPartitions = 3
    @AppStorage("code_review_analysis_only") private var codeReviewAnalysisOnly = false
    @AppStorage("code_review_max_rounds") private var codeReviewMaxRounds = 3
    @AppStorage("code_review_analysis_backend") private var codeReviewAnalysisBackend = "codex"

    // General
    @AppStorage("appearance") private var appearance = "system"
    @AppStorage("full_auto_tools") private var fullAutoTools = true
    @AppStorage("agent_auto_delegate_swarm") private var agentAutoDelegateSwarm = true
    @AppStorage("flow_diagnostics_enabled") private var flowDiagnosticsEnabled = false

    @StateObject private var codexState = CodexStateStore()
    @StateObject private var cliAccountsStore = CLIAccountsStore.shared
    @StateObject private var cliUsageLedger = CLIAccountUsageLedgerStore.shared
    @StateObject private var accountLoginCoordinator = CLIAccountLoginCoordinator()
    @State private var showCodexLogin = false
    @State private var showOpenRouterLogin = false
    @State private var codexAgentsMd = ""
    @State private var claudeMdContent = ""
    @State private var newAccountLabelByProvider: [CLIProviderKind: String] = [:]
    @State private var newAccountKeyByProvider: [CLIProviderKind: String] = [:]
    @State private var newDailyLimitByProvider: [CLIProviderKind: String] = [:]
    @State private var newWeeklyLimitByProvider: [CLIProviderKind: String] = [:]
    @State private var newMonthlyLimitByProvider: [CLIProviderKind: String] = [:]
    @State private var accountTestResultById: [UUID: String] = [:]
    @State private var loginMethodByAccount: [UUID: CLIAccountLoginCoordinator.LoginMethod] = [:]

    var body: some View {
        NavigationSplitView {
            List(selection: $selectedSection) {
                Section("Provider AI") {
                    ForEach(SettingsSection.providers) { section in
                        Label(section.rawValue, systemImage: section.icon)
                            .tag(section)
                    }
                }
                Section("Strumenti") {
                    ForEach(SettingsSection.tools) { section in
                        Label(section.rawValue, systemImage: section.icon)
                            .tag(section)
                    }
                }
                Section("Generale") {
                    ForEach(SettingsSection.general) { section in
                        Label(section.rawValue, systemImage: section.icon)
                            .tag(section)
                    }
                }
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 240)
        } detail: {
            ScrollView {
                detailContent
                    .frame(maxWidth: 560)
                    .padding(24)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .frame(width: 760, height: 520)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Chiudi") { dismiss() }
                    .keyboardShortcut(.escape, modifiers: [])
            }
        }
        .onAppear {
            codexState.refresh()
            syncProviders()
            Task { await refreshUsageSnapshotsForSettings() }
        }
        .sheet(isPresented: $showCodexLogin) {
            if let path = codexState.status.path ?? CodexDetector.findCodexPath(customPath: codexPath.isEmpty ? nil : codexPath) {
                CodexLoginView(codexPath: path) {
                    codexState.refresh()
                    syncCodex()
                }
            }
        }
        .onChange(of: openaiApiKey) { _, _ in syncOpenAI() }
        .onChange(of: openaiModel) { _, _ in syncOpenAI() }
        .onChange(of: anthropicApiKey) { _, _ in syncAnthropic() }
        .onChange(of: anthropicModel) { _, _ in syncAnthropic() }
        .onChange(of: googleApiKey) { _, _ in syncGoogle() }
        .onChange(of: googleModel) { _, _ in syncGoogle() }
        .onChange(of: minimaxApiKey) { _, _ in syncMiniMax() }
        .onChange(of: minimaxModel) { _, _ in syncMiniMax() }
        .onChange(of: openrouterApiKey) { _, _ in syncOpenRouter() }
        .onChange(of: openrouterModel) { _, _ in syncOpenRouter() }
        .onChange(of: claudePath) { _, _ in syncClaude() }
        .onChange(of: claudeModel) { _, _ in syncClaude() }
        .onChange(of: claudeAllowedTools) { _, _ in syncClaude() }
        .onChange(of: geminiCliPath) { _, _ in syncGemini() }
    }

    // MARK: - Detail Router

    @ViewBuilder
    private var detailContent: some View {
        switch selectedSection {
        case .openai: openAISection
        case .anthropic: anthropicSection
        case .google: googleSection
        case .minimax: minimaxSection
        case .openrouter: openRouterSection
        case .codex: codexSection
        case .claudeCli: claudeSection
        case .geminiCli: geminiSection
        case .swarm: swarmSection
        case .codeReview: codeReviewSection
        case .terminal: terminalSection
        case .behavior: behaviorSection
        case .appearance: appearanceSection
        case .mcp: mcpSection
        }
    }

    // MARK: - OpenAI

    private var openAISection: some View {
        VStack(alignment: .leading, spacing: 20) {
            sectionHeader(title: "OpenAI", subtitle: "GPT-5, o3, o4-mini e modelli reasoning", icon: "brain.head.profile")

            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    fieldLabel("API Key")
                    SecureField("sk-...", text: $openaiApiKey)
                        .textFieldStyle(.roundedBorder)

                    fieldLabel("Modello")
                    Picker("", selection: $openaiModel) {
                        ForEach(openAIModels, id: \.self) { m in Text(m).tag(m) }
                    }
                    .labelsHidden()

                    if OpenAIAPIProvider.isReasoningModel(openaiModel) {
                        fieldLabel("Reasoning Effort")
                        Picker("", selection: $reasoningEffort) {
                            Text("Low").tag("low")
                            Text("Medium").tag("medium")
                            Text("High").tag("high")
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                    }
                }
                .padding(4)
            }

            statusBadge(
                connected: !openaiApiKey.isEmpty,
                label: openaiApiKey.isEmpty ? "API Key non configurata" : "Configurato — \(openaiModel)"
            )
        }
    }

    // MARK: - Anthropic

    private var anthropicSection: some View {
        VStack(alignment: .leading, spacing: 20) {
            sectionHeader(title: "Anthropic", subtitle: "Claude Opus 4.6, Sonnet 4.6, Haiku 4.5", icon: "sparkle")

            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    fieldLabel("API Key")
                    SecureField("sk-ant-...", text: $anthropicApiKey)
                        .textFieldStyle(.roundedBorder)

                    fieldLabel("Modello")
                    Picker("", selection: $anthropicModel) {
                        ForEach(anthropicModels, id: \.self) { m in Text(m).tag(m) }
                    }
                    .labelsHidden()
                }
                .padding(4)
            }

            statusBadge(
                connected: !anthropicApiKey.isEmpty,
                label: anthropicApiKey.isEmpty ? "API Key non configurata" : "Configurato — \(anthropicModel)"
            )

            hintBox("Per usare Claude direttamente via API. Per Claude Code CLI, vedi la sezione Strumenti → Claude Code.")
        }
    }

    // MARK: - Google Gemini

    private var googleSection: some View {
        VStack(alignment: .leading, spacing: 20) {
            sectionHeader(title: "Google Gemini", subtitle: "Gemini 3 Pro, 2.5 Pro/Flash", icon: "globe")

            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    fieldLabel("API Key")
                    SecureField("AIza...", text: $googleApiKey)
                        .textFieldStyle(.roundedBorder)

                    fieldLabel("Modello")
                    Picker("", selection: $googleModel) {
                        ForEach(googleModels, id: \.self) { m in Text(m).tag(m) }
                    }
                    .labelsHidden()
                }
                .padding(4)
            }

            statusBadge(
                connected: !googleApiKey.isEmpty,
                label: googleApiKey.isEmpty ? "API Key non configurata" : "Configurato — \(googleModel)"
            )
        }
    }

    // MARK: - MiniMax

    private var minimaxSection: some View {
        VStack(alignment: .leading, spacing: 20) {
            sectionHeader(title: "MiniMax", subtitle: "M2.5 — SWE-Bench 80.2%, agent coding avanzato", icon: "bolt.horizontal.fill")

            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    fieldLabel("API Key")
                    SecureField("Ottieni da platform.minimax.io", text: $minimaxApiKey)
                        .textFieldStyle(.roundedBorder)

                    fieldLabel("Modello")
                    Picker("", selection: $minimaxModel) {
                        ForEach(minimaxModels, id: \.self) { m in Text(m).tag(m) }
                    }
                    .labelsHidden()
                }
                .padding(4)
            }

            statusBadge(
                connected: !minimaxApiKey.isEmpty,
                label: minimaxApiKey.isEmpty ? "API Key non configurata" : "Configurato — \(minimaxModel)"
            )

            hintBox("Registrati su platform.minimax.io per ottenere una API key. MiniMax M2.5 offre performance top su coding e agentic tasks a costi molto bassi ($0.30/M input).")
        }
    }

    // MARK: - OpenRouter

    private var openRouterSection: some View {
        VStack(alignment: .leading, spacing: 20) {
            sectionHeader(title: "OpenRouter", subtitle: "Gateway unificato per 400+ modelli AI", icon: "arrow.triangle.branch")

            GroupBox("Accesso") {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Button(action: { showOpenRouterLogin = true }) {
                            Label(
                                openrouterApiKey.isEmpty ? "Accedi con OpenRouter" : "Connesso",
                                systemImage: openrouterApiKey.isEmpty ? "bolt.fill" : "checkmark.circle.fill"
                            )
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(openrouterApiKey.isEmpty ? .orange : .green)

                        if !openrouterApiKey.isEmpty {
                            Text("API key configurata")
                                .font(.caption)
                                .foregroundStyle(.green)
                            Spacer()
                            Button("Disconnetti") {
                                openrouterApiKey = ""
                            }
                            .font(.caption)
                            .foregroundStyle(.red)
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(4)
            }
            .sheet(isPresented: $showOpenRouterLogin) {
                OpenRouterLoginView(apiKey: $openrouterApiKey) {}
            }

            GroupBox("Modello") {
                VStack(alignment: .leading, spacing: 12) {
                    Picker("", selection: $openrouterModel) {
                        ForEach(openRouterPopularModels, id: \.self) { m in Text(m).tag(m) }
                    }
                    .labelsHidden()

                    TextField("Oppure inserisci manualmente (es. meta-llama/llama-4-scout)", text: $openrouterModel)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 11))
                }
                .padding(4)
            }

            GroupBox("Modelli Gratuiti") {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Seleziona un modello gratuito (20 req/min, 200 req/giorno)")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    ForEach(openRouterFreeModels, id: \.self) { model in
                        Button {
                            openrouterModel = model
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: openrouterModel == model ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(openrouterModel == model ? .green : .secondary)
                                    .font(.system(size: 12))
                                Text(model.replacingOccurrences(of: ":free", with: ""))
                                    .font(.system(size: 12, weight: .medium))
                                Spacer()
                                Text("FREE")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundStyle(.green)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(.green.opacity(0.12), in: Capsule())
                            }
                            .padding(.vertical, 3)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(4)
            }

            statusBadge(
                connected: !openrouterApiKey.isEmpty,
                label: openrouterApiKey.isEmpty ? "Non connesso" : "Configurato — \(openrouterModel)"
            )

            hintBox("Accedi con il tuo account OpenRouter per usare 400+ modelli. I modelli gratuiti non richiedono credito, basta un account.")
        }
    }

    // MARK: - Codex CLI

    private var codexSection: some View {
        VStack(alignment: .leading, spacing: 20) {
            sectionHeader(title: "Codex CLI", subtitle: "Agente di coding locale con sandbox", icon: "terminal")

            GroupBox("Connessione") {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Button(action: connectToCodex) {
                            Label(
                                codexState.status.isLoggedIn ? "Connesso" : "Connetti",
                                systemImage: codexState.status.isLoggedIn ? "checkmark.circle.fill" : "bolt.fill"
                            )
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(codexState.status.isLoggedIn ? .green : .accentColor)
                        .disabled(codexState.status.isLoggedIn)

                        if codexState.status.isLoggedIn {
                            Text("Codex CLI connesso").font(.caption).foregroundStyle(.green)
                        }
                    }

                    if !codexState.status.isInstalled {
                        Label("Non installato — brew install codex", systemImage: "exclamationmark.circle.fill")
                            .font(.caption).foregroundStyle(.red)
                    }
                }
                .padding(4)
            }

            GroupBox("Configurazione") {
                VStack(alignment: .leading, spacing: 12) {
                    fieldLabel("Path (vuoto per auto-detect)")
                    TextField("/usr/local/bin/codex", text: $codexPath)
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: codexPath) { _, _ in codexState.refresh(); syncCodex() }

                    fieldLabel("Sandbox")
                    Picker("", selection: $codexSandbox) {
                        Text("Read-only").tag("read-only")
                        Text("Workspace write").tag("workspace-write")
                        Text("Full access").tag("danger-full-access")
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .onChange(of: codexSandbox) { _, _ in syncCodex(); saveCodexToml() }

                    fieldLabel("Ask for approval")
                    Picker("", selection: $codexAskForApproval) {
                        Text("Mai").tag("never")
                        Text("On request").tag("on-request")
                        Text("Untrusted").tag("untrusted")
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .onChange(of: codexAskForApproval) { _, _ in syncCodex() }

                    fieldLabel("Modello Override")
                    TextField("es. o3, o4-mini", text: $codexModelOverride)
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: codexModelOverride) { _, _ in syncCodex(); saveCodexToml() }

                    fieldLabel("Backend Plan Mode")
                    Picker("", selection: $planModeBackend) {
                        Text("Codex").tag("codex")
                        Text("Claude").tag("claude")
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }
                .padding(4)
            }

            GroupBox("Modello Avanzato") {
                VStack(alignment: .leading, spacing: 12) {
                    fieldLabel("Reasoning Summary")
                    Picker("", selection: $codexReasoningSummary) {
                        Text("Auto").tag("auto")
                        Text("Concise").tag("concise")
                        Text("Detailed").tag("detailed")
                        Text("None").tag("none")
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .onChange(of: codexReasoningSummary) { _, _ in saveCodexToml() }

                    fieldLabel("Verbosity")
                    Picker("", selection: $codexVerbosity) {
                        Text("Low").tag("low")
                        Text("Medium").tag("medium")
                        Text("High").tag("high")
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .onChange(of: codexVerbosity) { _, _ in saveCodexToml() }

                    fieldLabel("Personality")
                    Picker("", selection: $codexPersonality) {
                        Text("None").tag("none")
                        Text("Friendly").tag("friendly")
                        Text("Pragmatic").tag("pragmatic")
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .onChange(of: codexPersonality) { _, _ in saveCodexToml() }
                }
                .padding(4)
            }

            GroupBox("Sandbox Avanzato") {
                VStack(alignment: .leading, spacing: 12) {
                    Toggle("Network access", isOn: $codexNetworkAccess)
                        .onChange(of: codexNetworkAccess) { _, _ in saveCodexToml() }

                    fieldLabel("Additional write roots (uno per riga)")
                    TextField("/tmp, /var/data", text: $codexAdditionalWriteRoots)
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: codexAdditionalWriteRoots) { _, _ in saveCodexToml() }

                    Toggle("Controlla aggiornamenti all'avvio", isOn: $codexCheckUpdate)
                        .onChange(of: codexCheckUpdate) { _, _ in saveCodexToml() }
                }
                .padding(4)
            }

            GroupBox("Istruzioni") {
                VStack(alignment: .leading, spacing: 12) {
                    fieldLabel("Developer Instructions")
                    TextEditor(text: $codexDeveloperInstructions)
                        .font(.system(size: 11, design: .monospaced))
                        .frame(height: 80)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color(nsColor: .separatorColor)))
                        .onChange(of: codexDeveloperInstructions) { _, _ in saveCodexToml() }

                    fieldLabel("AGENTS.md (globale — ~/.codex/AGENTS.md)")
                    TextEditor(text: $codexAgentsMd)
                        .font(.system(size: 11, design: .monospaced))
                        .frame(height: 120)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color(nsColor: .separatorColor)))
                        .onChange(of: codexAgentsMd) { _, _ in
                            CodexAgentsFile.saveGlobal(codexAgentsMd)
                        }
                }
                .padding(4)
            }

            multiAccountProviderSection(.codex)
        }
        .onAppear { loadCodexAdvanced() }
    }

    // MARK: - Claude CLI

    private var claudeSection: some View {
        VStack(alignment: .leading, spacing: 20) {
            sectionHeader(title: "Claude Code CLI", subtitle: "Agente Anthropic locale", icon: "sparkles")

            GroupBox("Connessione") {
                VStack(alignment: .leading, spacing: 12) {
                    fieldLabel("Path (vuoto per auto-detect)")
                    TextField("/usr/local/bin/claude", text: $claudePath)
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: claudePath) { _, _ in syncClaude() }
                }
                .padding(4)
            }

            GroupBox("Configurazione") {
                VStack(alignment: .leading, spacing: 12) {
                    fieldLabel("Modello")
                    Picker("", selection: $claudeModel) {
                        Text("Opus").tag("opus")
                        Text("Sonnet").tag("sonnet")
                        Text("Haiku").tag("haiku")
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()

                    fieldLabel("Allowed Tools")
                    let allTools = ["Read", "Edit", "Bash", "Write", "Search", "Glob", "Grep", "TodoRead", "TodoWrite"]
                    let selectedTools = Set(claudeAllowedTools.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) })
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 90))], spacing: 6) {
                        ForEach(allTools, id: \.self) { tool in
                            Toggle(tool, isOn: Binding(
                                get: { selectedTools.contains(tool) },
                                set: { isOn in
                                    var current = selectedTools
                                    if isOn { current.insert(tool) } else { current.remove(tool) }
                                    claudeAllowedTools = current.sorted().joined(separator: ",")
                                }
                            ))
                            .toggleStyle(.checkbox)
                            .font(.system(size: 11))
                        }
                    }
                }
                .padding(4)
            }

            GroupBox("Istruzioni") {
                VStack(alignment: .leading, spacing: 12) {
                    fieldLabel("CLAUDE.md (globale — ~/.claude/CLAUDE.md)")
                    TextEditor(text: $claudeMdContent)
                        .font(.system(size: 11, design: .monospaced))
                        .frame(height: 140)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color(nsColor: .separatorColor)))
                        .onChange(of: claudeMdContent) { _, _ in
                            ClaudeConfigLoader.saveClaudeMd(claudeMdContent)
                        }
                }
                .padding(4)
            }

            multiAccountProviderSection(.claude)
        }
        .onAppear {
            claudeMdContent = ClaudeConfigLoader.loadClaudeMd()
        }
    }

    // MARK: - Gemini CLI

    private var geminiSection: some View {
        VStack(alignment: .leading, spacing: 20) {
            sectionHeader(title: "Gemini CLI", subtitle: "Provider CLI Google Gemini locale", icon: "globe")

            GroupBox("Connessione") {
                VStack(alignment: .leading, spacing: 12) {
                    fieldLabel("Path (vuoto per auto-detect)")
                    TextField("/usr/local/bin/gemini", text: $geminiCliPath)
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: geminiCliPath) { _, _ in syncGemini() }
                }
                .padding(4)
            }

            multiAccountProviderSection(.gemini)
        }
    }

    // MARK: - Agent Swarm

    private var swarmSection: some View {
        VStack(alignment: .leading, spacing: 20) {
            sectionHeader(title: "Agent Swarm", subtitle: "Orchestratore multi-agente: Planner, Coder, Reviewer, Debugger", icon: "ant.fill")

            GroupBox("Orchestratore") {
                VStack(alignment: .leading, spacing: 12) {
                    fieldLabel("Backend che genera il piano di task")
                    Picker("", selection: $swarmOrchestrator) {
                        Text("OpenAI (leggero)").tag("openai")
                        Text("Codex CLI").tag("codex")
                        Text("Claude Code").tag("claude")
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .onChange(of: swarmOrchestrator) { _, _ in syncSwarm() }
                }
                .padding(4)
            }

            GroupBox("Worker") {
                VStack(alignment: .leading, spacing: 12) {
                    fieldLabel("Backend che esegue i task")
                    Picker("", selection: $swarmWorkerBackend) {
                        Text("Codex CLI").tag("codex")
                        Text("Claude Code").tag("claude")
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .onChange(of: swarmWorkerBackend) { _, _ in syncSwarm() }

                    hintBox("I worker usano internamente i propri subagent nativi (multi-agent Codex / Claude) per task complessi.")
                }
                .padding(4)
            }

            GroupBox("Ruoli abilitati") {
                VStack(alignment: .leading, spacing: 8) {
                    let allRoles = AgentRole.allCases
                    let selected = Set(swarmEnabledRoles.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) })
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 100))], spacing: 6) {
                        ForEach(allRoles, id: \.self) { role in
                            let isOn = selected.contains(role.rawValue)
                            Button {
                                var roles = Set(selected)
                                if isOn { roles.remove(role.rawValue) } else { roles.insert(role.rawValue) }
                                swarmEnabledRoles = roles.sorted().joined(separator: ",")
                                syncSwarm()
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                                    Text(role.displayName).font(.caption)
                                }
                                .foregroundStyle(isOn ? Color.accentColor : .secondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(4)
            }

            GroupBox("Pipeline QA") {
                VStack(alignment: .leading, spacing: 12) {
                    Toggle("Pipeline QA dopo Coder (Reviewer + TestWriter + test)", isOn: $swarmAutoPostCodePipeline)
                        .onChange(of: swarmAutoPostCodePipeline) { _, _ in syncSwarm() }

                    if swarmAutoPostCodePipeline {
                        Stepper("Max tentativi correzione test: \(swarmMaxPostCodeRetries)", value: $swarmMaxPostCodeRetries, in: 1...50)
                            .onChange(of: swarmMaxPostCodeRetries) { _, _ in syncSwarm() }
                    }
                    Stepper("Max loop Reviewer→Coder: \(swarmMaxReviewLoops)", value: $swarmMaxReviewLoops, in: 0...5)
                        .onChange(of: swarmMaxReviewLoops) { _, _ in syncSwarm() }
                }
                .padding(4)
            }
        }
    }

    // MARK: - Code Review

    private var codeReviewSection: some View {
        VStack(alignment: .leading, spacing: 20) {
            sectionHeader(title: "Code Review", subtitle: "Analisi parallela multi-swarm con report aggregato", icon: "doc.text.magnifyingglass")

            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    fieldLabel("Backend analisi Fase 1")
                    Picker("", selection: $codeReviewAnalysisBackend) {
                        Text("Codex").tag("codex")
                        Text("Claude").tag("claude")
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .onChange(of: codeReviewAnalysisBackend) { _, _ in syncCodeReview() }

                    Stepper("Max agenti contemporanei: \(codeReviewPartitions)", value: $codeReviewPartitions, in: 2...12)
                        .onChange(of: codeReviewPartitions) { _, _ in syncCodeReview() }

                    Stepper("Max iterazioni analisi→fix: \(codeReviewMaxRounds)", value: $codeReviewMaxRounds, in: 1...10)
                        .onChange(of: codeReviewMaxRounds) { _, _ in syncCodeReview() }

                    Toggle("Solo analisi (disabilita Fase 2 — esecuzione)", isOn: $codeReviewAnalysisOnly)
                        .onChange(of: codeReviewAnalysisOnly) { _, _ in syncCodeReview() }
                }
                .padding(4)
            }
        }
    }

    // MARK: - Terminal

    private var terminalSection: some View {
        VStack(alignment: .leading, spacing: 20) {
            sectionHeader(title: "Terminale", subtitle: "Terminale integrato nell'editor", icon: "terminal.fill")

            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Per il terminale integrato serve accesso Full Disk Access.")
                        .font(.callout).foregroundStyle(.secondary)

                    Button(action: openFullDiskAccessPreferences) {
                        Label("Apri Impostazioni: Full Disk Access", systemImage: "lock.open")
                    }

                    Text("Aggiungi Codigo all'elenco e attiva l'interruttore. Riavvia dopo la modifica.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .padding(4)
            }
        }
    }

    // MARK: - Behavior

    private var behaviorSection: some View {
        VStack(alignment: .leading, spacing: 20) {
            sectionHeader(title: "Comportamento", subtitle: "Procedi senza conferma su tutte le modalità", icon: "bolt.fill")

            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    Toggle("Yolo: procedi senza conferma (tutte le modalità)", isOn: $globalYolo)
                        .onChange(of: globalYolo) { _, _ in
                            syncCodex()
                            syncPlanProvider()
                            syncCodeReview()
                        }

                    hintBox("Quando attivo: Plan execute, Code Review Fase 2, Agent e Swarm procedono senza chiedere conferma.")
                }
                .padding(4)
            }

            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    Toggle("Consenti delega automatica allo swarm in Agent", isOn: $agentAutoDelegateSwarm)
                    hintBox("Se disattivo, Agent non inietta il marker invoke_swarm e resta in esecuzione singola.")
                    Toggle("Flow diagnostics in chat", isOn: $flowDiagnosticsEnabled)
                    hintBox("Mostra provider effettivo, stato flusso ed eventi normalizzati per debug runtime.")
                }
                .padding(4)
            }

            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    fieldLabel("Summarize chat automatico (stile Cursor)")
                    Toggle("Abilita", isOn: Binding(
                        get: { summarizeThreshold < 1.0 },
                        set: { summarizeThreshold = $0 ? 0.8 : 1.0 }
                    ))
                    if summarizeThreshold < 1.0 {
                        HStack {
                            Text("Soglia contesto")
                            Slider(value: $summarizeThreshold, in: 0.5...0.95, step: 0.05)
                            Text("\(Int(summarizeThreshold * 100))%")
                                .frame(width: 36, alignment: .trailing)
                                .foregroundStyle(.secondary)
                        }
                        Stepper(value: $summarizeKeepLast, in: 4...12) {
                            Text("Messaggi da mantenere: \(summarizeKeepLast)")
                        }
                        Picker("Provider per riassunto", selection: $summarizeProvider) {
                            Text("OpenAI API").tag("openai-api")
                            Text("Codex CLI").tag("codex-cli")
                            Text("Claude CLI").tag("claude-cli")
                        }
                    }
                    hintBox("Quando il contesto supera la soglia, i messaggi vecchi vengono compressi in un riassunto per liberare spazio.")
                    hintBox("Se selezioni Codex CLI come provider riassunto, viene usato il compact nativo di Codex (niente riscrittura custom della chat).")
                }
                .padding(4)
            }
        }
    }

    // MARK: - Appearance

    private var appearanceSection: some View {
        VStack(alignment: .leading, spacing: 20) {
            sectionHeader(title: "Aspetto", subtitle: "Tema e comportamento generale", icon: "paintbrush.fill")

            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    fieldLabel("Tema")
                    Picker("", selection: $appearance) {
                        Label("Sistema", systemImage: "circle.lefthalf.filled").tag("system")
                        Label("Chiaro", systemImage: "sun.max").tag("light")
                        Label("Scuro", systemImage: "moon").tag("dark")
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()

                    Toggle("Auto-approvazione strumenti (Codex/Claude)", isOn: $fullAutoTools)
                }
                .padding(4)
            }
        }
    }

    // MARK: - MCP

    private var mcpSection: some View {
        VStack(alignment: .leading, spacing: 20) {
            sectionHeader(title: "MCP", subtitle: "Model Context Protocol — server e strumenti", icon: "server.rack")

            MCPSettingsSection()
        }
    }

    // MARK: - Reusable Components

    private func sectionHeader(title: String, subtitle: String, icon: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(Color.accentColor)
                .frame(width: 36, height: 36)
                .background(Color.accentColor.opacity(0.1), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.title3.weight(.semibold))
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func fieldLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(.secondary)
    }

    private func statusBadge(connected: Bool, label: String) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(connected ? Color.green : Color.orange)
                .frame(width: 7, height: 7)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func hintBox(_ text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "info.circle")
                .foregroundStyle(.secondary)
                .font(.caption)
            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
    }

    @ViewBuilder
    private func multiAccountProviderSection(_ provider: CLIProviderKind) -> some View {
        GroupBox("Multi-account \(provider.displayName)") {
            VStack(alignment: .leading, spacing: 12) {
                Toggle("Abilita multi-account CLI", isOn: $cliAccountsStore.multiAccountEnabled)
                Text("Auto-switch su quota/rate limit e limiti locali giornalieri/settimanali/mensili.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                let providerAccounts = cliAccountsStore.accounts(for: provider)
                if providerAccounts.isEmpty {
                    Text("Nessun account configurato per \(provider.displayName).")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(providerAccounts) { account in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 8) {
                                TextField("Label", text: Binding(
                                    get: { account.label },
                                    set: { newValue in
                                        var updated = account
                                        updated.label = newValue
                                        cliAccountsStore.update(updated)
                                    }
                                ))
                                Toggle("Attivo", isOn: Binding(
                                    get: { account.isEnabled },
                                    set: { newValue in
                                        var updated = account
                                        updated.isEnabled = newValue
                                        cliAccountsStore.update(updated)
                                    }
                                ))
                                .toggleStyle(.checkbox)
                                Stepper("Priorità \(account.priority)", value: Binding(
                                    get: { account.priority },
                                    set: { newValue in
                                        var updated = account
                                        updated.priority = max(0, newValue)
                                        cliAccountsStore.update(updated)
                                    }
                                ), in: 0...99)
                            }

                            HStack(spacing: 10) {
                                statusBadge(
                                    connected: accountAuthStatus(account).isLoggedIn,
                                    label: accountStatusLabel(account)
                                )
                                let day = cliUsageLedger.totals(accountId: account.id, period: .day)
                                let week = cliUsageLedger.totals(accountId: account.id, period: .weekOfYear)
                                let month = cliUsageLedger.totals(accountId: account.id, period: .month)
                                Text("Oggi $\(day.cost, specifier: "%.2f")")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                Text("W $\(week.cost, specifier: "%.2f")")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                Text("M $\(month.cost, specifier: "%.2f")")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            HStack(spacing: 10) {
                                let day = cliUsageLedger.totals(accountId: account.id, period: .day)
                                let week = cliUsageLedger.totals(accountId: account.id, period: .weekOfYear)
                                let month = cliUsageLedger.totals(accountId: account.id, period: .month)
                                Text("Tok D \(day.tokens)")
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                                Text("W \(week.tokens)")
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                                Text("M \(month.tokens)")
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                                if provider == .codex {
                                    Text(codexCreditsLabel())
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }

                            HStack(spacing: 8) {
                                Picker(
                                    "",
                                    selection: Binding(
                                        get: { loginMethodByAccount[account.id] ?? .browserOAuth },
                                        set: { loginMethodByAccount[account.id] = $0 }
                                    )
                                ) {
                                    ForEach(CLIAccountLoginCoordinator.LoginMethod.allCases) { method in
                                        Text(method.title).tag(method)
                                    }
                                }
                                .labelsHidden()
                                .frame(width: 160)
                                Button("Connetti account") {
                                    connectAccount(account)
                                }
                                .buttonStyle(.borderedProminent)
                                .disabled(accountLoginCoordinator.isRunningByAccount[account.id] == true)
                                Button("Disconnetti account") {
                                    disconnectAccount(account)
                                }
                                .buttonStyle(.bordered)
                                Button("Test account") {
                                    testAccount(account)
                                }
                                .buttonStyle(.bordered)
                                Button("Elimina", role: .destructive) {
                                    cliAccountsStore.delete(accountId: account.id)
                                }
                                .buttonStyle(.bordered)
                                if let result = accountTestResultById[account.id] {
                                    Text(result)
                                        .font(.caption)
                                        .foregroundStyle(result.contains("OK") ? .green : .red)
                                }
                                if let status = accountLoginCoordinator.statusByAccount[account.id], !status.isEmpty {
                                    Text(status)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                            }
                        }
                        .padding(10)
                        .background(Color(nsColor: .controlBackgroundColor).opacity(0.45), in: RoundedRectangle(cornerRadius: 8))
                    }
                }

                Divider()
                fieldLabel("Aggiungi account")
                HStack(spacing: 8) {
                    TextField("Label", text: Binding(
                        get: { newAccountLabelByProvider[provider, default: ""] },
                        set: { newAccountLabelByProvider[provider] = $0 }
                    ))
                    SecureField("API key (opzionale)", text: Binding(
                        get: { newAccountKeyByProvider[provider, default: ""] },
                        set: { newAccountKeyByProvider[provider] = $0 }
                    ))
                }
                HStack(spacing: 8) {
                    TextField("Limit giornaliero $", text: Binding(
                        get: { newDailyLimitByProvider[provider, default: ""] },
                        set: { newDailyLimitByProvider[provider] = $0 }
                    ))
                    TextField("Limit settimanale $", text: Binding(
                        get: { newWeeklyLimitByProvider[provider, default: ""] },
                        set: { newWeeklyLimitByProvider[provider] = $0 }
                    ))
                    TextField("Limit mensile $", text: Binding(
                        get: { newMonthlyLimitByProvider[provider, default: ""] },
                        set: { newMonthlyLimitByProvider[provider] = $0 }
                    ))
                }
                HStack(spacing: 8) {
                    Button("Aggiungi account") {
                        addAccount(provider)
                    }
                    .buttonStyle(.borderedProminent)
                    Button("Reset stato limiti/salute") {
                        cliAccountsStore.resetHealth(provider: provider)
                    }
                    .buttonStyle(.bordered)
                }
            }
            .padding(4)
        }
    }

    // MARK: - Actions

    private func accountStatusLabel(_ account: CLIAccount) -> String {
        let auth = accountAuthStatus(account)
        if account.health.isExhaustedLocally {
            return "Exhausted (limite locale)"
        }
        if let until = account.health.cooldownUntil, until > Date() {
            return "Cooldown fino alle \(until.formatted(date: .omitted, time: .shortened))"
        }
        switch auth {
        case .loggedIn(let method):
            return "Connesso (\(method.rawValue))"
        case .notLoggedIn:
            return "Non connesso"
        case .notInstalled:
            return "CLI non installato"
        case .error(let message):
            return "Errore auth: \(message)"
        }
    }

    private func codexCreditsLabel() -> String {
        guard let usage = providerUsageStore.codexUsage,
              let balance = usage.creditsBalance else {
            return "Crediti: N/D"
        }
        let currency = usage.creditsCurrency ?? "USD"
        return String(format: "Crediti: %.2f %@", balance, currency)
    }

    private func addAccount(_ provider: CLIProviderKind) {
        let label = newAccountLabelByProvider[provider, default: ""].trimmingCharacters(in: .whitespacesAndNewlines)
        let secret = newAccountKeyByProvider[provider, default: ""].trimmingCharacters(in: .whitespacesAndNewlines)
        let quota = CLIAccountQuotaPolicy(
            dailyLimitUSD: Double(newDailyLimitByProvider[provider, default: ""].replacingOccurrences(of: ",", with: ".")),
            weeklyLimitUSD: Double(newWeeklyLimitByProvider[provider, default: ""].replacingOccurrences(of: ",", with: ".")),
            monthlyLimitUSD: Double(newMonthlyLimitByProvider[provider, default: ""].replacingOccurrences(of: ",", with: ".")),
            dailyTokenLimit: nil,
            weeklyTokenLimit: nil,
            monthlyTokenLimit: nil
        )
        cliAccountsStore.addAccount(
            provider: provider,
            label: label,
            apiKey: secret.isEmpty ? nil : secret,
            quota: quota
        )
        newAccountLabelByProvider[provider] = ""
        newAccountKeyByProvider[provider] = ""
        newDailyLimitByProvider[provider] = ""
        newWeeklyLimitByProvider[provider] = ""
        newMonthlyLimitByProvider[provider] = ""
    }

    private func testAccount(_ account: CLIAccount) {
        let secret = cliAccountsStore.secret(for: account.id)
        let env = CLIProfileProvisioner.environmentOverrides(
            provider: account.provider,
            profilePath: account.profilePath,
            secret: secret
        )

        let executable: String
        let args: [String]
        switch account.provider {
        case .codex:
            executable = codexPath.isEmpty ? (CodexDetector.findCodexPath(customPath: nil) ?? "/opt/homebrew/bin/codex") : codexPath
            args = ["--version"]
        case .claude:
            executable = claudePath.isEmpty ? (PathFinder.find(executable: "claude") ?? "/opt/homebrew/bin/claude") : claudePath
            args = ["--version"]
        case .gemini:
            executable = geminiCliPath.isEmpty ? (PathFinder.find(executable: "gemini") ?? "/opt/homebrew/bin/gemini") : geminiCliPath
            args = ["--version"]
        }

        Task.detached {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = args
            var shell = CodexDetector.shellEnvironment()
            shell.merge(env) { _, new in new }
            process.environment = shell
            do {
                try process.run()
                process.waitUntilExit()
                let ok = process.terminationStatus == 0
                await MainActor.run {
                    accountTestResultById[account.id] = ok ? "OK" : "Errore exit \(process.terminationStatus)"
                }
            } catch {
                await MainActor.run {
                    accountTestResultById[account.id] = "Errore: \(error.localizedDescription)"
                }
            }
        }
    }

    private func connectAccount(_ account: CLIAccount) {
        let method = loginMethodByAccount[account.id] ?? .browserOAuth
        let providerPath = providerPath(for: account.provider)
        let apiKey = cliAccountsStore.secret(for: account.id)
        accountLoginCoordinator.startLogin(
            account: account,
            providerPath: providerPath,
            method: method,
            apiKey: apiKey
        )
        Task {
            try? await Task.sleep(for: .seconds(1))
            let status = accountAuthStatus(account)
            await MainActor.run {
                cliAccountsStore.updateAuthStatus(accountId: account.id, status: status)
            }
        }
    }

    private func disconnectAccount(_ account: CLIAccount) {
        accountLoginCoordinator.disconnect(account: account)
        let status = accountAuthStatus(account)
        cliAccountsStore.updateAuthStatus(accountId: account.id, status: status)
    }

    private func accountAuthStatus(_ account: CLIAccount) -> CLIAccountAuthStatus {
        CLIAccountAuthDetector.detect(
            account: account,
            providerPath: providerPath(for: account.provider)
        )
    }

    private func providerPath(for provider: CLIProviderKind) -> String? {
        switch provider {
        case .codex:
            return codexPath
        case .claude:
            return claudePath
        case .gemini:
            return geminiCliPath
        }
    }

    private func connectToCodex() {
        if codexState.status.path != nil || CodexDetector.findCodexPath(customPath: codexPath.isEmpty ? nil : codexPath) != nil {
            if codexState.status.isLoggedIn {
                syncCodex()
            } else {
                showCodexLogin = true
            }
        }
    }

    private func refreshUsageSnapshotsForSettings() async {
        let codexBin = codexPath.isEmpty ? (PathFinder.find(executable: "codex") ?? "") : codexPath
        let claudeBin = claudePath.isEmpty ? (PathFinder.find(executable: "claude") ?? "") : claudePath
        let geminiBin = geminiCliPath.isEmpty ? (PathFinder.find(executable: "gemini") ?? "") : geminiCliPath
        await providerUsageStore.fetchCodexUsage(codexPath: codexBin, workingDirectory: nil)
        await providerUsageStore.fetchClaudeUsage(claudePath: claudeBin, workingDirectory: nil)
        await providerUsageStore.fetchGeminiUsage(geminiPath: geminiBin, workingDirectory: nil)
    }

    private func syncProviders() {
        syncOpenAI()
        syncAnthropic()
        syncGoogle()
        syncMiniMax()
        syncOpenRouter()
        syncCodex()
        syncClaude()
        syncGemini()
        syncSwarm()
        syncCodeReview()
        syncPlanProvider()
    }

    private func syncPlanProvider() {
        let codex = providerRegistry.provider(for: "codex-cli") as? CodexCLIProvider
        let claude = providerRegistry.provider(for: "claude-cli") as? ClaudeCLIProvider
        guard codex != nil || claude != nil else { return }
        providerRegistry.unregister(id: "plan-mode")
        providerRegistry.register(ProviderFactory.planProvider(config: providerFactoryConfig(), codex: codex, claude: claude, executionController: executionController))
    }

    private func syncOpenAI() {
        let effort = OpenAIAPIProvider.isReasoningModel(openaiModel) ? reasoningEffort : nil
        providerRegistry.unregister(id: "openai-api")
        providerRegistry.register(OpenAIAPIProvider(apiKey: openaiApiKey, model: openaiModel, reasoningEffort: effort))
    }

    private func syncAnthropic() {
        providerRegistry.unregister(id: "anthropic-api")
        providerRegistry.register(AnthropicAPIProvider(
            apiKey: anthropicApiKey,
            model: anthropicModel,
            displayName: "Anthropic"
        ))
    }

    private func syncGoogle() {
        providerRegistry.unregister(id: "google-api")
        providerRegistry.register(OpenAIAPIProvider(
            apiKey: googleApiKey,
            model: googleModel,
            id: "google-api",
            displayName: "Google Gemini",
            baseURL: "https://generativelanguage.googleapis.com/v1beta/openai/chat/completions"
        ))
    }

    private func syncCodex() {
        providerRegistry.unregister(id: "codex-cli")
        providerRegistry.register(ProviderFactory.codexProvider(config: providerFactoryConfig(), executionController: executionController))
    }

    private func openFullDiskAccessPreferences() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
            NSWorkspace.shared.open(url)
        }
    }

    private func syncMiniMax() {
        providerRegistry.unregister(id: "minimax-api")
        providerRegistry.register(OpenAIAPIProvider(
            apiKey: minimaxApiKey,
            model: minimaxModel,
            id: "minimax-api",
            displayName: "MiniMax",
            baseURL: "https://api.minimax.io/v1/chat/completions"
        ))
    }

    private func syncOpenRouter() {
        providerRegistry.unregister(id: "openrouter-api")
        providerRegistry.register(OpenAIAPIProvider(
            apiKey: openrouterApiKey,
            model: openrouterModel,
            id: "openrouter-api",
            displayName: "OpenRouter",
            baseURL: "https://openrouter.ai/api/v1/chat/completions",
            extraHeaders: ["HTTP-Referer": "https://codigo.app", "X-Title": "Codigo"]
        ))
    }

    private func syncClaude() {
        providerRegistry.unregister(id: "claude-cli")
        providerRegistry.register(ProviderFactory.claudeProvider(config: providerFactoryConfig(), executionController: executionController))
        syncSwarm()
        syncPlanProvider()
    }

    private func syncGemini() {
        providerRegistry.unregister(id: "gemini-cli")
        providerRegistry.register(ProviderFactory.geminiProvider(config: providerFactoryConfig(), executionController: executionController))
    }

    private func syncSwarm() {
        guard let codex = providerRegistry.provider(for: "codex-cli") as? CodexCLIProvider else { return }
        let claude = providerRegistry.provider(for: "claude-cli") as? ClaudeCLIProvider
        providerRegistry.unregister(id: "agent-swarm")
        providerRegistry.register(ProviderFactory.swarmProvider(config: providerFactoryConfig(), codex: codex, claude: claude, executionController: executionController))
    }

    private func loadCodexAdvanced() {
        let cfg = CodexConfigLoader.load()
        // Configurazione principale da config.toml (sorgente unica per Codex CLI)
        codexSandbox = cfg.sandboxMode ?? ""
        codexModelOverride = cfg.model ?? ""
        codexReasoningEffort = cfg.modelReasoningEffort ?? "xhigh"
        // Modello avanzato
        codexReasoningSummary = cfg.modelReasoningSummary ?? "auto"
        codexVerbosity = cfg.modelVerbosity ?? "medium"
        let validPersonalities = ["none", "friendly", "pragmatic"]
        codexPersonality = validPersonalities.contains(cfg.personality ?? "none") ? (cfg.personality ?? "none") : "none"
        codexNetworkAccess = cfg.networkAccess ?? false
        codexAdditionalWriteRoots = cfg.additionalWriteRoots.joined(separator: ", ")
        codexDeveloperInstructions = cfg.developerInstructions ?? ""
        codexCheckUpdate = cfg.checkForUpdateOnStartup ?? true
        codexAgentsMd = CodexAgentsFile.loadGlobal()
    }

    private func saveCodexToml() {
        var cfg = CodexConfigLoader.load()
        // Configurazione principale → config.toml (uso globale Codex CLI)
        if !codexSandbox.isEmpty { cfg.sandboxMode = codexSandbox }
        if !codexModelOverride.isEmpty { cfg.model = codexModelOverride }
        if !codexReasoningEffort.isEmpty { cfg.modelReasoningEffort = codexReasoningEffort }
        // Modello avanzato
        cfg.modelReasoningSummary = codexReasoningSummary == "auto" ? nil : codexReasoningSummary
        cfg.modelVerbosity = codexVerbosity == "medium" ? nil : codexVerbosity
        cfg.personality = codexPersonality == "none" ? nil : codexPersonality
        cfg.networkAccess = codexNetworkAccess ? true : nil
        cfg.additionalWriteRoots = codexAdditionalWriteRoots.components(separatedBy: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        cfg.developerInstructions = codexDeveloperInstructions.isEmpty ? nil : codexDeveloperInstructions
        cfg.checkForUpdateOnStartup = codexCheckUpdate ? nil : false
        CodexConfigLoader.save(cfg)
    }

    private func syncCodeReview() {
        guard let codex = providerRegistry.provider(for: "codex-cli") as? CodexCLIProvider else { return }
        let claude = providerRegistry.provider(for: "claude-cli") as? ClaudeCLIProvider
        providerRegistry.unregister(id: "multi-swarm-review")
        providerRegistry.register(ProviderFactory.codeReviewProvider(config: providerFactoryConfig(), codex: codex, claude: claude))
    }

    private func parseSwarmEnabledRoles() -> Set<AgentRole> {
        var roles = Set<AgentRole>()
        for raw in swarmEnabledRoles.components(separatedBy: ",") {
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { continue }
            if let role = AgentRole(rawValue: trimmed) {
                roles.insert(role)
            }
        }
        return roles
    }

    private func parseClaudeAllowedTools() -> [String] {
        var seen = Set<String>()
        var tools: [String] = []
        for raw in claudeAllowedTools.components(separatedBy: ",") {
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { continue }
            if seen.insert(trimmed).inserted {
                tools.append(trimmed)
            }
        }
        return tools
    }

    private func providerFactoryConfig() -> ProviderFactoryConfig {
        ProviderFactoryConfig(
            openaiApiKey: openaiApiKey,
            openaiModel: openaiModel,
            anthropicApiKey: anthropicApiKey,
            anthropicModel: anthropicModel,
            googleApiKey: googleApiKey,
            googleModel: googleModel,
            minimaxApiKey: minimaxApiKey,
            minimaxModel: minimaxModel,
            openrouterApiKey: openrouterApiKey,
            openrouterModel: openrouterModel,
            codexPath: codexPath,
            codexSandbox: codexSandbox,
            codexSessionFullAccess: codexSessionFullAccess,
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
            claudeAllowedTools: parseClaudeAllowedTools(),
            geminiCliPath: geminiCliPath
        )
    }
}
