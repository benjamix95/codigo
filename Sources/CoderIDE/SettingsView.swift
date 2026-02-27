import AppKit
import CoderEngine
import SwiftUI

// MARK: - Settings Navigation

enum SettingsSection: String, CaseIterable, Identifiable {
    case apiKeys = "API Keys"
    case cliTools = "CLI Tools"
    case mcp = "MCP Servers"
    case skillsPlugins = "Skills & Plugins"
    case rules = "Rules"
    case codebaseIndex = "Codebase Index"
    case behavior = "Behavior"
    case appearance = "Appearance"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .apiKeys: return "key.fill"
        case .cliTools: return "terminal"
        case .mcp: return "server.rack"
        case .skillsPlugins: return "puzzlepiece.fill"
        case .rules: return "doc.text.fill"
        case .codebaseIndex: return "text.magnifyingglass"
        case .behavior: return "bolt.fill"
        case .appearance: return "paintbrush.fill"
        }
    }

    static var providerAI: [SettingsSection] { [.apiKeys] }
    static var tools: [SettingsSection] { [.cliTools, .mcp, .skillsPlugins] }
    static var general: [SettingsSection] { [.rules, .codebaseIndex, .behavior, .appearance] }
}

// MARK: - Settings View

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var workspaceStore: WorkspaceStore
    @EnvironmentObject var providerRegistry: ProviderRegistry
    @EnvironmentObject var executionController: ExecutionController
    @EnvironmentObject var providerUsageStore: ProviderUsageStore
    @EnvironmentObject var appUpdateCenter: AppUpdateCenter
    @State private var selectedSection: SettingsSection = .apiKeys

    // MARK: - Provider API Keys
    @AppStorage("openai_api_key") private var openaiApiKey = ""
    @AppStorage("openai_model") private var openaiModel = "gpt-4o-mini"
    @AppStorage("reasoning_effort") private var reasoningEffort = "medium"
    @AppStorage("anthropic_api_key") private var anthropicApiKey = ""
    @AppStorage("anthropic_admin_api_key") private var anthropicAdminApiKey = ""
    @AppStorage("anthropic_model") private var anthropicModel = "claude-sonnet-4-6"
    @AppStorage("google_api_key") private var googleApiKey = ""
    @AppStorage("google_model") private var googleModel = "gemini-2.5-pro"
    @AppStorage("minimax_api_key") private var minimaxApiKey = ""
    @AppStorage("minimax_model") private var minimaxModel = "MiniMax-M2.5"
    @AppStorage("openrouter_api_key") private var openrouterApiKey = ""
    @AppStorage("openrouter_model") private var openrouterModel = "anthropic/claude-sonnet-4-6"
    @AppStorage("grok_api_key") private var grokApiKey = ""
    @AppStorage("grok_model") private var grokModel = "grok-4-1-fast-reasoning"
    @AppStorage("web_search_provider") private var webSearchProvider = "duckduckgo"
    @AppStorage("brave_search_api_key") private var braveSearchApiKey = ""
    @AppStorage("tavily_api_key") private var tavilyApiKey = ""
    @AppStorage("serper_api_key") private var serperApiKey = ""

    // MARK: - CLI Tools
    @AppStorage("codex_path") private var codexPath = ""
    @AppStorage("codex_sandbox") private var codexSandbox = "workspace-write"
    @AppStorage("codex_ask_for_approval") private var codexAskForApproval = "never"
    @AppStorage("codex_model_override") private var codexModelOverride = ""
    @AppStorage("codex_reasoning_effort") private var codexReasoningEffort = "low"
    @AppStorage("codex_model_provider") private var codexModelProvider = ""
    @AppStorage("codex_prefer_responses_wire_api")
    private var codexPreferResponsesWireAPI = false
    @AppStorage("codex_session_full_access") private var codexSessionFullAccess = false
    @AppStorage("codex_network_access") private var codexNetworkAccess = false
    @AppStorage("codex_additional_write_roots") private var codexAdditionalWriteRoots = ""
    @AppStorage("codex_check_update") private var codexCheckUpdate = true
    @AppStorage("codex_developer_instructions") private var codexDeveloperInstructions = ""
    @AppStorage("claude_path") private var claudePath = ""
    @AppStorage("claude_model") private var claudeModel = "claude-sonnet-4-6"
    @AppStorage("claude_allowed_tools") private var claudeAllowedTools = "Read,Edit,Bash,Write,Search"
    @AppStorage("gemini_cli_path") private var geminiCliPath = ""
    @AppStorage("gemini_model_override") private var geminiModelOverride = ""
    @AppStorage("unified_tool_runtime_enabled") private var unifiedToolRuntimeEnabled = true
    @AppStorage("agents_hard_block_enabled") private var agentsHardBlockEnabled = true

    // MARK: - Hidden runtime keys (no UI, consumed by ProviderFactoryConfig)
    @AppStorage("plan_mode_backend") private var planModeBackend = "codex"
    @AppStorage("swarm_orchestrator") private var swarmOrchestrator = "auto"
    @AppStorage("swarm_worker_backend") private var swarmWorkerBackend = "auto"
    @AppStorage("swarm_auto_post_code_pipeline") private var swarmAutoPostCodePipeline = true
    @AppStorage("swarm_max_post_code_retries") private var swarmMaxPostCodeRetries = 10
    @AppStorage("swarm_max_review_loops") private var swarmMaxReviewLoops = 2
    @AppStorage("swarm_enabled_roles") private var swarmEnabledRoles = "planner,coder,debugger,reviewer,testWriter"
    @AppStorage("code_review_partitions") private var codeReviewPartitions = 3
    @AppStorage("code_review_analysis_only") private var codeReviewAnalysisOnly = false
    @AppStorage("code_review_max_rounds") private var codeReviewMaxRounds = 3
    @AppStorage("code_review_analysis_backend") private var codeReviewAnalysisBackend = "codex-cli"
    @AppStorage("code_review_execution_backend") private var codeReviewExecutionBackend = "codex-cli"
    @AppStorage("code_review_quick_commands_custom_json") private var codeReviewQuickCommandsCustomJSON = ""
    @AppStorage("codex_reasoning_summary") private var codexReasoningSummary = "auto"
    @AppStorage("codex_verbosity") private var codexVerbosity = "medium"
    @AppStorage("codex_personality") private var codexPersonality = "none"

    // MARK: - Behavior
    @AppStorage("global_yolo") private var globalYolo = false
    @AppStorage("agent_auto_delegate_swarm") private var agentAutoDelegateSwarm = true
    @AppStorage("swarm_fallback_auto_evaluate") private var swarmFallbackAutoEvaluate = true
    @AppStorage("terminal_auto_follow_output") private var terminalAutoFollowOutput = true
    @AppStorage("summarize_threshold") private var summarizeThreshold = 0.8
    @AppStorage("summarize_keep_last") private var summarizeKeepLast = 6
    @AppStorage("summarize_provider") private var summarizeProvider = "openai-api"
    @AppStorage("full_auto_tools") private var fullAutoTools = true
    @AppStorage(planHistoryMaxEntriesPreferenceKey) private var planHistoryMaxEntries = 200
    @AppStorage(planHistoryMaxMarkdownLengthPreferenceKey) private var planHistoryMaxMarkdownLength = 65_536
    @AppStorage("app_update_check_enabled") private var appUpdateCheckEnabled = true
    @AppStorage("app_update_manifest_url") private var appUpdateManifestURL = AppUpdateCenter.defaultManifestURL

    // MARK: - Appearance
    @AppStorage("appearance") private var appearance = "system"
    @AppStorage("chat_background_style") private var chatBackgroundStyle = ChatBackgroundStyle.defaultRawValue
    @AppStorage("ui_sans_font_family") private var uiSansFontFamily = FontPreferences.defaultSansFamily
    @AppStorage("ui_sans_font_size") private var uiSansFontSize = FontPreferences.defaultSansSize
    @AppStorage("ui_code_font_family") private var uiCodeFontFamily = FontPreferences.defaultCodeFamily
    @AppStorage("ui_code_font_size") private var uiCodeFontSize = FontPreferences.defaultCodeSize

    // MARK: - Codebase Index
    @AppStorage("codebase_index_enabled") private var codebaseIndexEnabled = true
    @AppStorage("codebase_index_excluded_paths") private var codebaseIndexExcludedPaths = ""
    @AppStorage("codebase_index_respect_gitignore") private var codebaseIndexRespectGitignore = true
    @AppStorage("codebase_index_excluded_file_patterns") private var codebaseIndexExcludedFilePatterns = ""

    // MARK: - State Objects
    @StateObject private var codexState = CodexStateStore()
    @StateObject private var codexMCPHealth = CodexMCPHealthStore.shared
    @StateObject private var geminiState = GeminiStateStore()
    @StateObject private var cliAccountsStore = CLIAccountsStore.shared
    @StateObject private var cliUsageLedger = CLIAccountUsageLedgerStore.shared
    @StateObject private var accountLoginCoordinator = CLIAccountLoginCoordinator()

    // MARK: - UI State
    @State private var showOpenRouterLogin = false
    @State private var codexAgentsMd = ""
    @State private var claudeMdContent = ""
    @State private var globalRuleDocs: [CoderRuleDocument] = []
    @State private var projectRuleDocs: [CoderRuleDocument] = []
    @State private var selectedGlobalRuleName: String = ""
    @State private var selectedProjectRuleName: String = ""
    @State private var newGlobalRuleName: String = ""
    @State private var newProjectRuleName: String = ""
    @State private var globalRuleContentDraft: String = ""
    @State private var projectRuleContentDraft: String = ""
    @State private var loginSheetAccount: CLIAccount?
    @State private var showDeleteConfirmation: UUID?
    @State private var pendingLoginAccountIds: Set<UUID> = []
    @State private var indexStatusText: String = "Loading..."
    @State private var indexStatsText: String = ""
    @State private var statusRefreshTask: Task<Void, Never>?

    private var availableSansFontFamilies: [String] {
        FontPreferences.availableSansFamilies()
    }

    private var availableMonoFontFamilies: [String] {
        FontPreferences.availableMonoFamilies()
    }

    // MARK: - Body

    var body: some View {
        applyBehaviorSyncs(applyCLISyncs(applyProviderSyncs(settingsContent)))
    }

    private var settingsContent: some View {
        NavigationSplitView {
            List(selection: $selectedSection) {
                Section("Provider AI") {
                    ForEach(SettingsSection.providerAI) { section in
                        Label(section.rawValue, systemImage: section.icon).tag(section)
                    }
                }
                Section("Tools") {
                    ForEach(SettingsSection.tools) { section in
                        Label(section.rawValue, systemImage: section.icon).tag(section)
                    }
                }
                Section("General") {
                    ForEach(SettingsSection.general) { section in
                        Label(section.rawValue, systemImage: section.icon).tag(section)
                    }
                }
            }
            .listStyle(.sidebar)
            .frame(minWidth: 180)
        } detail: {
            ScrollView {
                detailContent
                    .frame(maxWidth: 560, alignment: .leading)
                    .padding(24)
            }
        }
        .frame(width: 760, height: 520)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Close") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
        }
        .onAppear {
            FontPreferences.registerBundledFonts()
            cliAccountsStore.bootstrapAccountsIfNeeded()
            normalizeStoredSelections()
            loadCodexAdvanced()
            codexMCPHealth.refresh()
            syncProviders()
            reloadRulesFromDisk()
            appUpdateCenter.setUpdateCheckEnabled(appUpdateCheckEnabled)
            appUpdateCenter.setManifestURL(appUpdateManifestURL)
        }
    }

    // MARK: - onChange Handlers (split to help type-checker)

    private func applyProviderSyncs<V: View>(_ content: V) -> some View {
        content
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
            .onChange(of: grokApiKey) { _, _ in syncGrok() }
            .onChange(of: grokModel) { _, _ in syncGrok() }
    }

    private func applyCLISyncs<V: View>(_ content: V) -> some View {
        content
            .onChange(of: codexPath) { _, _ in codexState.refresh(); syncCodex() }
            .onChange(of: codexSandbox) { _, _ in syncCodex(); saveCodexToml() }
            .onChange(of: codexAskForApproval) { _, _ in syncCodex() }
            .onChange(of: codexModelOverride) { _, _ in syncCodex(); saveCodexToml() }
            .onChange(of: codexModelProvider) { _, _ in syncCodex(); saveCodexToml() }
            .onChange(of: codexPreferResponsesWireAPI) { _, _ in syncCodex() }
            .onChange(of: codexNetworkAccess) { _, _ in saveCodexToml() }
            .onChange(of: codexAdditionalWriteRoots) { _, _ in saveCodexToml() }
            .onChange(of: codexCheckUpdate) { _, _ in saveCodexToml() }
            .onChange(of: codexDeveloperInstructions) { _, _ in saveCodexToml() }
            .onChange(of: claudePath) { _, _ in syncClaude() }
            .onChange(of: claudeModel) { _, _ in syncClaude() }
            .onChange(of: claudeAllowedTools) { _, _ in syncClaude() }
            .onChange(of: geminiCliPath) { _, _ in syncGemini() }
    }

    private func applyBehaviorSyncs<V: View>(_ content: V) -> some View {
        content
            .onChange(of: globalYolo) { _, _ in syncCodex(); syncPlanProvider(); syncCodeReview() }
            .onChange(of: appUpdateCheckEnabled) { _, isEnabled in
                appUpdateCenter.setUpdateCheckEnabled(isEnabled)
            }
            .onChange(of: appUpdateManifestURL) { _, newURL in
                appUpdateCenter.setManifestURL(newURL)
            }
            .onChange(of: codebaseIndexEnabled) { _, _ in
                workspaceStore.indexActiveWorkspace()
                Task { await refreshIndexStatus() }
            }
            .onChange(of: codebaseIndexExcludedPaths) { _, _ in
                workspaceStore.indexActiveWorkspace()
            }
            .onChange(of: uiSansFontSize) { _, newValue in
                uiSansFontSize = Double(FontPreferences.sanitizeSize(newValue, kind: .sans))
            }
            .onChange(of: uiCodeFontSize) { _, newValue in
                uiCodeFontSize = Double(FontPreferences.sanitizeSize(newValue, kind: .code))
            }
    }

    // MARK: - Detail Router

    @ViewBuilder
    private var detailContent: some View {
        switch selectedSection {
        case .apiKeys: apiKeysSection
        case .cliTools: cliToolsSection
        case .mcp: mcpSection
        case .skillsPlugins: SkillsPluginsSection()
        case .rules: rulesSection
        case .codebaseIndex: codebaseIndexSection
        case .behavior: behaviorSection
        case .appearance: appearanceSection
        }
    }

    // MARK: - API Keys

    private var apiKeysSection: some View {
        VStack(alignment: .leading, spacing: 20) {
            sectionHeader(title: "API Keys", subtitle: "API keys for AI providers", icon: "key.fill")

            GroupBox("OpenAI") {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        SecureField("sk-...", text: $openaiApiKey).textFieldStyle(.roundedBorder)
                        statusBadge(connected: !openaiApiKey.isEmpty, label: openaiApiKey.isEmpty ? "Not configured" : "Configured")
                    }
                }.padding(4)
            }

            GroupBox("Anthropic") {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        SecureField("sk-ant-...", text: $anthropicApiKey).textFieldStyle(.roundedBorder)
                        statusBadge(connected: !anthropicApiKey.isEmpty, label: anthropicApiKey.isEmpty ? "Not configured" : "Configured")
                    }
                    HStack {
                        fieldLabel("Admin key (usage online)")
                        SecureField("sk-ant-admin-...", text: $anthropicAdminApiKey).textFieldStyle(.roundedBorder)
                        statusBadge(
                            connected: !anthropicAdminApiKey.isEmpty,
                            label: anthropicAdminApiKey.isEmpty ? "Optional" : "Configured"
                        )
                    }
                    hintBox("Used only to fetch online Claude usage via Anthropic Admin API. Fallback remains local session usage.")
                }.padding(4)
            }

            GroupBox("Google Gemini") {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        SecureField("AIza...", text: $googleApiKey).textFieldStyle(.roundedBorder)
                        statusBadge(connected: !googleApiKey.isEmpty, label: googleApiKey.isEmpty ? "Not configured" : "Configured")
                    }
                }.padding(4)
            }

            GroupBox("MiniMax") {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        SecureField("API Key", text: $minimaxApiKey).textFieldStyle(.roundedBorder)
                        statusBadge(connected: !minimaxApiKey.isEmpty, label: minimaxApiKey.isEmpty ? "Not configured" : "Configured")
                    }
                }.padding(4)
            }

            GroupBox("OpenRouter") {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        SecureField("sk-or-...", text: $openrouterApiKey).textFieldStyle(.roundedBorder)
                        statusBadge(connected: !openrouterApiKey.isEmpty, label: openrouterApiKey.isEmpty ? "Not configured" : "Configured")
                    }
                    hintBox("OpenRouter lets you use models from different providers with a single API key. Models are selected in chat.")
                }.padding(4)
            }

            GroupBox("Grok (xAI)") {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        SecureField("xai-...", text: $grokApiKey).textFieldStyle(.roundedBorder)
                        statusBadge(connected: !grokApiKey.isEmpty, label: grokApiKey.isEmpty ? "Not configured" : "Configured")
                    }
                }.padding(4)
            }

            GroupBox("Web Search") {
                VStack(alignment: .leading, spacing: 10) {
                    fieldLabel("Search provider")
                    Picker("", selection: $webSearchProvider) {
                        Text("DuckDuckGo (Free)").tag("duckduckgo")
                        Text("Brave Search").tag("brave")
                        Text("Tavily").tag("tavily")
                        Text("Serper (Google)").tag("serper")
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)

                    // Provider-specific API key fields
                    if webSearchProvider == "brave" {
                        HStack {
                            SecureField("BSA...", text: $braveSearchApiKey).textFieldStyle(.roundedBorder)
                            statusBadge(connected: !braveSearchApiKey.isEmpty, label: braveSearchApiKey.isEmpty ? "Key required" : "Configured")
                        }
                        hintBox("Free tier: 2,000 queries/month. Get a key at brave.com/search/api")
                    } else if webSearchProvider == "tavily" {
                        HStack {
                            SecureField("tvly-...", text: $tavilyApiKey).textFieldStyle(.roundedBorder)
                            statusBadge(connected: !tavilyApiKey.isEmpty, label: tavilyApiKey.isEmpty ? "Key required" : "Configured")
                        }
                        hintBox("Free tier: 1,000 queries/month. AI-optimized search. Get a key at tavily.com")
                    } else if webSearchProvider == "serper" {
                        HStack {
                            SecureField("API Key", text: $serperApiKey).textFieldStyle(.roundedBorder)
                            statusBadge(connected: !serperApiKey.isEmpty, label: serperApiKey.isEmpty ? "Key required" : "Configured")
                        }
                        hintBox("Free tier: 2,500 queries/month. Google Search results. Get a key at serper.dev")
                    } else {
                        hintBox("DuckDuckGo is free and requires no API key. Results are extracted via HTML scraping.")
                    }
                }.padding(4)
            }

            hintBox("Models are selected directly from the chat bar, not from settings.")
        }
    }

    // MARK: - CLI Tools

    private var cliToolsSection: some View {
        VStack(alignment: .leading, spacing: 20) {
            sectionHeader(title: "CLI Tools", subtitle: "Codex, Claude Code, and Gemini CLI", icon: "terminal")

            // Codex CLI
            GroupBox("Codex CLI") {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        fieldLabel("Path")
                        TextField("Auto-detect", text: $codexPath).textFieldStyle(.roundedBorder)
                        statusBadge(
                            connected: codexState.status.isLoggedIn,
                            label: codexState.status.isLoggedIn ? "Connected" : "Not connected"
                        )
                    }
                    Button("Connect to Codex") { connectToCodex() }
                        .buttonStyle(.borderedProminent).controlSize(.small)

                    HStack(spacing: 8) {
                        statusBadge(
                            connected: codexMCPHealth.isHealthy,
                            label: codexMCPHealth.statusLabel
                        )
                        Spacer()
                        Button("Re-check") {
                            codexMCPHealth.refresh()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)

                        if codexMCPHealth.canRepair {
                            Button("Repair profiles") {
                                codexMCPHealth.repairProfiles()
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                        }
                    }

                    Divider()
                    fieldLabel("Sandbox")
                    Picker("", selection: $codexSandbox) {
                        Text("Read Only").tag("read-only")
                        Text("Workspace Write").tag("workspace-write")
                        Text("Full Access").tag("danger-full-access")
                    }.labelsHidden().pickerStyle(.segmented)

                    fieldLabel("Approval")
                    Picker("", selection: $codexAskForApproval) {
                        Text("Never").tag("never")
                        Text("On request").tag("on-request")
                        Text("Untrusted").tag("untrusted")
                    }.labelsHidden().pickerStyle(.segmented)

                    Toggle("Prefer OpenAI Responses wire API", isOn: $codexPreferResponsesWireAPI)
                    hintBox(
                        "When enabled, Codex CLI runs with `model_providers.openai.wire_api=\"responses\"`."
                    )

                    Toggle("Network access", isOn: $codexNetworkAccess)
                    Toggle("Check for updates", isOn: $codexCheckUpdate)
                }.padding(4)
            }

            multiAccountProviderSection(.codex)

            // Claude Code
            GroupBox("Claude Code") {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        fieldLabel("Path")
                        TextField("Auto-detect", text: $claudePath).textFieldStyle(.roundedBorder)
                        let claudeInstalled = !claudePath.isEmpty || PathFinder.find(executable: "claude") != nil
                        statusBadge(connected: claudeInstalled, label: claudeInstalled ? "Installed" : "Not found")
                    }

                    Divider()
                    fieldLabel("Allowed tools")
                    let allTools = ["Read", "Edit", "Bash", "Write", "Search", "Glob", "Grep", "TodoRead", "TodoWrite"]
                    let selectedTools = parseClaudeAllowedTools()
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 90))], spacing: 6) {
                        ForEach(allTools, id: \.self) { tool in
                            let isOn = selectedTools.contains(tool)
                            Button {
                                var set = Set(selectedTools)
                                if isOn { set.remove(tool) } else { set.insert(tool) }
                                claudeAllowedTools = allTools.filter { set.contains($0) }.joined(separator: ",")
                            } label: {
                                Text(tool)
                                    .font(.system(size: 10, weight: isOn ? .semibold : .regular))
                                    .padding(.horizontal, 8).padding(.vertical, 4)
                                    .background(isOn ? Color.accentColor.opacity(0.15) : Color.clear, in: Capsule())
                                    .overlay(Capsule().strokeBorder(isOn ? Color.accentColor : Color.secondary.opacity(0.3)))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }.padding(4)
            }

            multiAccountProviderSection(.claude)

            // Gemini CLI
            GroupBox("Gemini CLI") {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        fieldLabel("Path")
                        TextField("Auto-detect", text: $geminiCliPath).textFieldStyle(.roundedBorder)
                        statusBadge(
                            connected: geminiState.status.isInstalled,
                            label: geminiState.status.isInstalled ? "Installed" : "Not found"
                        )
                    }
                    if !geminiState.status.isInstalled {
                        Button("Connect to Gemini") {
                            geminiState.refresh()
                            if geminiState.status.isInstalled { syncGemini() }
                        }
                        .buttonStyle(.borderedProminent).controlSize(.small)
                    }
                }.padding(4)
            }
            .onAppear { geminiState.refresh() }

            multiAccountProviderSection(.gemini)
        }
        .sheet(item: $loginSheetAccount) { account in
            CLIAccountLoginSheet(
                account: account,
                providerPath: providerPath(for: account.provider),
                onDismiss: {
                    handleLoginSheetDismiss(for: account)
                }
            )
        }
    }

    // MARK: - MCP

    private var mcpSection: some View {
        VStack(alignment: .leading, spacing: 20) {
            sectionHeader(title: "MCP Servers", subtitle: "Model Context Protocol — servers and tools", icon: "server.rack")
            MCPSettingsSection()
        }
    }

    // MARK: - Rules

    private var rulesSection: some View {
        VStack(alignment: .leading, spacing: 20) {
            sectionHeader(title: "Rules", subtitle: "Instructions and rules for all providers", icon: "doc.text.fill")

            hintBox("Rules are automatically applied to ALL AI providers (API and CLI). Use global rules for general guidance and project rules for workspace-specific constraints.")

            // Global rules
            GroupBox("Global rules (~/.codigo/rules/global/)") {
                VStack(alignment: .leading, spacing: 10) {
                    if globalRuleDocs.isEmpty {
                        Text("No global rules found. Create one to get started.")
                            .font(.caption).foregroundStyle(.secondary)
                    } else {
                        Picker("Rule", selection: $selectedGlobalRuleName) {
                            ForEach(globalRuleDocs, id: \.name) { doc in
                                Text(doc.name).tag(doc.name)
                            }
                        }
                        .onChange(of: selectedGlobalRuleName) { _, name in
                            globalRuleContentDraft = globalRuleDocs.first(where: { $0.name == name })?.content ?? ""
                        }
                        TextEditor(text: $globalRuleContentDraft)
                            .font(.system(size: 11, design: .monospaced))
                            .frame(height: 140)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color(nsColor: .separatorColor)))
                        HStack(spacing: 8) {
                            Button("Save") { saveSelectedGlobalRule() }.buttonStyle(.borderedProminent).controlSize(.small)
                            Button("Delete", role: .destructive) { deleteSelectedGlobalRule() }.buttonStyle(.bordered).controlSize(.small)
                        }
                    }

                    Divider()
                    fieldLabel("New global rule")
                    HStack(spacing: 8) {
                        TextField("Name (e.g. coding-style.md)", text: $newGlobalRuleName).textFieldStyle(.roundedBorder)
                        Button("Create") { createGlobalRule() }.buttonStyle(.borderedProminent).controlSize(.small)
                    }
                }.padding(4)
            }

            // Project rules
            GroupBox("Project rules (.codigo/rules/project/)") {
                VStack(alignment: .leading, spacing: 10) {
                    if currentProjectRootPath == nil {
                        Text("No active workspace. Open a project to manage project rules.")
                            .font(.caption).foregroundStyle(.secondary)
                    } else if projectRuleDocs.isEmpty {
                        Text("No project rules found. Create one to get started.")
                            .font(.caption).foregroundStyle(.secondary)
                    } else {
                        Picker("Rule", selection: $selectedProjectRuleName) {
                            ForEach(projectRuleDocs, id: \.name) { doc in
                                Text(doc.name).tag(doc.name)
                            }
                        }
                        .onChange(of: selectedProjectRuleName) { _, name in
                            projectRuleContentDraft = projectRuleDocs.first(where: { $0.name == name })?.content ?? ""
                        }
                        TextEditor(text: $projectRuleContentDraft)
                            .font(.system(size: 11, design: .monospaced))
                            .frame(height: 140)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color(nsColor: .separatorColor)))
                        HStack(spacing: 8) {
                            Button("Save") { saveSelectedProjectRule() }.buttonStyle(.borderedProminent).controlSize(.small)
                            Button("Delete", role: .destructive) { deleteSelectedProjectRule() }.buttonStyle(.bordered).controlSize(.small)
                        }
                    }

                    if currentProjectRootPath != nil {
                        Divider()
                        fieldLabel("New project rule")
                        HStack(spacing: 8) {
                            TextField("Name (e.g. api-guidelines.md)", text: $newProjectRuleName).textFieldStyle(.roundedBorder)
                            Button("Create") { createProjectRule() }.buttonStyle(.borderedProminent).controlSize(.small)
                        }
                    }
                }.padding(4)
            }
        }
    }

    // MARK: - Codebase Index

    private var codebaseIndexSection: some View {
        VStack(alignment: .leading, spacing: 20) {
            sectionHeader(title: "Codebase Index", subtitle: "Symbol indexing and semantic search", icon: "text.magnifyingglass")

            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    Toggle("Automatic indexing", isOn: $codebaseIndexEnabled).toggleStyle(.switch)
                    hintBox("When enabled, the active workspace is indexed automatically on startup. The index provides symbol search, navigation, and context to AI providers.")
                }
            }

            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    fieldLabel("Index status")
                    if let progress = workspaceStore.indexProgress {
                        HStack(spacing: 8) {
                            ProgressView()
                                .controlSize(.small)
                            Text("Indexing... \(progress.current)/\(progress.total) files (\(progress.percentText))")
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                        ProgressView(value: progress.fraction)
                            .progressViewStyle(.linear)
                    } else {
                        Text(indexStatusText)
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    if !indexStatsText.isEmpty && workspaceStore.indexProgress == nil {
                        Text(indexStatsText)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.tertiary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    Button("Reindex") {
                        Task {
                            indexStatusText = "Reindexing..."
                            workspaceStore.indexActiveWorkspace()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(workspaceStore.indexProgress != nil)
                }
            }

            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    fieldLabel("Excluded paths")
                    TextField("node_modules, .git, build, dist", text: $codebaseIndexExcludedPaths).textFieldStyle(.roundedBorder)
                    hintBox("Comma-separated list of directories to exclude. Default directories (node_modules, .git, build, etc.) are always excluded.")
                }
            }

            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    Toggle("Respect .gitignore", isOn: $codebaseIndexRespectGitignore)
                        .toggleStyle(.switch)
                        .onChange(of: codebaseIndexRespectGitignore) {
                            workspaceStore.indexActiveWorkspace()
                        }
                    hintBox("When enabled, files and directories listed in .gitignore are excluded from indexing.")
                }
            }

            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    fieldLabel("Excluded file patterns")
                    TextField("*.generated.swift, *.pb.swift, *.min.js", text: $codebaseIndexExcludedFilePatterns)
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: codebaseIndexExcludedFilePatterns) {
                            // Debounce: only re-index after a short pause
                        }
                    hintBox("Comma-separated glob patterns for files to exclude (e.g. *.generated.swift, *.pb.swift).")
                    Button("Apply") {
                        workspaceStore.indexActiveWorkspace()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
        }
        .onAppear {
            Task { await refreshIndexStatus() }
            statusRefreshTask = Task {
                while !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: 2_000_000_000) // 2s
                    guard !Task.isCancelled else { break }
                    await refreshIndexStatus()
                }
            }
        }
        .onDisappear {
            statusRefreshTask?.cancel()
            statusRefreshTask = nil
        }
    }

    // MARK: - Behavior

    private var behaviorSection: some View {
        let historyEntryLimits = [50, 100, 200]
        let historyMarkdownLimits = [32_768, 49_152, 65_536]
        return VStack(alignment: .leading, spacing: 20) {
            sectionHeader(title: "Behavior", subtitle: "Agent and terminal behavior", icon: "bolt.fill")

            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    Toggle("YOLO Mode (full auto)", isOn: $globalYolo)
                    hintBox("When enabled, the agent runs commands and edits files without confirmation. Useful for automation, but potentially destructive.")
                }
            }

            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    Toggle("Auto-delegate to Agent Swarm", isOn: $agentAutoDelegateSwarm)
                    hintBox("Allows the single agent to automatically delegate complex tasks to the multi-agent swarm.")
                    Toggle("Swarm fallback auto-evaluate", isOn: $swarmFallbackAutoEvaluate)
                    hintBox("When the LLM does not emit a swarm marker, automatically evaluate the response with the delegation policy and delegate if complex enough.")
                }
            }

            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    Toggle("Auto-follow terminal output", isOn: $terminalAutoFollowOutput)
                    hintBox("Automatically follows terminal output while commands are running.")
                }
            }

            GroupBox("Automatic chat summary") {
                VStack(alignment: .leading, spacing: 12) {
                    Toggle("Enable automatic summary", isOn: Binding(
                        get: { summarizeThreshold < 1.0 },
                        set: { summarizeThreshold = $0 ? 0.8 : 1.0 }
                    ))
                    if summarizeThreshold < 1.0 {
                        HStack {
                            fieldLabel("Context threshold")
                            Slider(value: $summarizeThreshold, in: 0.3...0.95, step: 0.05)
                            Text("\(Int(summarizeThreshold * 100))%").font(.caption).foregroundStyle(.secondary)
                        }
                        Stepper("Keep last \(summarizeKeepLast) messages", value: $summarizeKeepLast, in: 2...20)
                    }
                    hintBox("Automatically summarizes chat when context exceeds the threshold, keeping the latest messages untouched.")
                }.padding(4)
            }

            GroupBox("Application updates") {
                VStack(alignment: .leading, spacing: 12) {
                    Toggle("Controlla aggiornamenti all'avvio", isOn: $appUpdateCheckEnabled)
                    TextField("URL manifest aggiornamenti", text: $appUpdateManifestURL)
                        .textFieldStyle(.roundedBorder)
                    HStack(spacing: 8) {
                        Button("Ripristina URL predefinito") {
                            appUpdateManifestURL = AppUpdateCenter.defaultManifestURL
                            appUpdateCenter.setManifestURL(appUpdateManifestURL)
                        }
                        Button("Controlla ora") {
                            Task {
                                appUpdateCenter.setManifestURL(appUpdateManifestURL)
                                appUpdateCenter.setUpdateCheckEnabled(appUpdateCheckEnabled)
                                await appUpdateCenter.checkForUpdates(force: true)
                            }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                    switch appUpdateCenter.state {
                    case .idle:
                        Text(appUpdateCenter.statusSummary)
                    case .checking:
                        Text(appUpdateCenter.statusSummary)
                    case .disabled:
                        Text(appUpdateCenter.statusSummary)
                    case .upToDate:
                        Text(appUpdateCenter.statusSummary)
                    case .available(let manifest):
                        Text("Nuovo aggiornamento: \(manifest.version) (\(manifest.displayBuild))")
                    case .failed(let error):
                        Text(error).foregroundStyle(.red)
                    }
                    if let last = appUpdateCenter.lastCheckedAt {
                        Text("Ultimo controllo: \(last.formatted(date: .abbreviated, time: .shortened))")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }.padding(4)
            }

            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    Toggle("Auto-approve tools", isOn: $fullAutoTools)
                    hintBox("Automatically approves tool calls (files, terminal, etc.) without interactive confirmation.")
                }
            }

            GroupBox("Plan history limits") {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        fieldLabel("Max entries")
                        Spacer()
                        Picker("Max entries", selection: $planHistoryMaxEntries) {
                            ForEach(historyEntryLimits, id: \.self) { limit in
                                Text("\(limit)").tag(limit)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 110)
                    }

                    HStack {
                        fieldLabel("Max markdown chars")
                        Spacer()
                        Picker("Max markdown chars", selection: $planHistoryMaxMarkdownLength) {
                            ForEach(historyMarkdownLimits, id: \.self) { limit in
                                Text("\(limit)").tag(limit)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 130)
                    }

                    hintBox("Controls how many plan snapshots are retained and their maximum markdown size. Existing history is trimmed immediately when lowering limits.")
                }
            }
        }
    }

    // MARK: - Appearance

    private var appearanceSection: some View {
        VStack(alignment: .leading, spacing: 20) {
            sectionHeader(title: "Appearance", subtitle: "Theme and interface appearance", icon: "paintbrush.fill")

            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    fieldLabel("Theme")
                    Picker("", selection: $appearance) {
                        Text("System").tag("system")
                        Text("Light").tag("light")
                        Text("Dark").tag("dark")
                    }.labelsHidden().pickerStyle(.segmented)
                }
            }

            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    fieldLabel("Chat background")
                    Picker("", selection: $chatBackgroundStyle) {
                        ForEach(ChatBackgroundStyle.allCases) { (style: ChatBackgroundStyle) in
                            Text(style.label).tag(style.rawValue)
                        }
                    }.labelsHidden()
                }
            }

            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    fieldLabel("Sans font family")
                    HStack(spacing: 12) {
                        Stepper(
                            value: Binding(
                                get: { Int(FontPreferences.sanitizeSize(uiSansFontSize, kind: .sans)) },
                                set: { uiSansFontSize = Double($0) }
                            ),
                            in: Int(FontPreferences.sansSizeRange.lowerBound)...Int(FontPreferences.sansSizeRange.upperBound)
                        ) {
                            Text("\(Int(FontPreferences.sanitizeSize(uiSansFontSize, kind: .sans))) px")
                                .frame(width: 58, alignment: .leading)
                        }
                        Picker("Sans family", selection: $uiSansFontFamily) {
                            Text("System Default").tag(FontPreferences.systemSansToken)
                            ForEach(availableSansFontFamilies, id: \.self) { family in
                                Text(family).tag(family)
                            }
                        }
                        .labelsHidden()
                    }
                    Text("Adjust the font used for the app UI.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    fieldLabel("Code font")
                    HStack(spacing: 12) {
                        Stepper(
                            value: Binding(
                                get: { Int(FontPreferences.sanitizeSize(uiCodeFontSize, kind: .code)) },
                                set: { uiCodeFontSize = Double($0) }
                            ),
                            in: Int(FontPreferences.codeSizeRange.lowerBound)...Int(FontPreferences.codeSizeRange.upperBound)
                        ) {
                            Text("\(Int(FontPreferences.sanitizeSize(uiCodeFontSize, kind: .code))) px")
                                .frame(width: 58, alignment: .leading)
                        }
                        Picker("Code family", selection: $uiCodeFontFamily) {
                            Text("System Monospace").tag(FontPreferences.systemMonoToken)
                            ForEach(availableMonoFontFamilies, id: \.self) { family in
                                Text(family).tag(family)
                            }
                        }
                        .labelsHidden()
                    }
                    Text("Adjust font and size used for code across chats and technical panels.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
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
        Text(text).font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
    }

    private func statusBadge(connected: Bool, label: String) -> some View {
        HStack(spacing: 6) {
            Circle().fill(connected ? Color.green : Color.orange).frame(width: 7, height: 7)
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
    }

    private func hintBox(_ text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "info.circle").foregroundStyle(.secondary).font(.caption)
            Text(text).font(.caption).foregroundStyle(.secondary)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Multi-Account

    @ViewBuilder
    private func multiAccountProviderSection(_ provider: CLIProviderKind) -> some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label("Accounts", systemImage: "person.2")
                        .font(.system(size: 12, weight: .semibold))
                    Spacer()
                    Toggle("Multi-account", isOn: $cliAccountsStore.multiAccountEnabled)
                        .toggleStyle(.switch)
                        .controlSize(.mini)
                }

                let providerAccounts = cliAccountsStore.accounts(for: provider)
                if providerAccounts.isEmpty {
                    HStack {
                        Spacer()
                        VStack(spacing: 6) {
                            Image(systemName: "person.badge.plus")
                                .font(.system(size: 20))
                                .foregroundStyle(.tertiary)
                            Text("No accounts yet")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 12)
                        Spacer()
                    }
                } else {
                    ForEach(providerAccounts) { account in
                        accountCard(account, provider: provider)
                    }
                }

                Button {
                    let account = cliAccountsStore.addAccountQuick(provider: provider)
                    pendingLoginAccountIds.insert(account.id)
                    loginSheetAccount = account
                } label: {
                    Label("Add Account", systemImage: "plus")
                        .font(.system(size: 12, weight: .medium))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            .padding(4)
        } label: {
            Text("\(provider.displayName) Accounts")
        }
    }

    @ViewBuilder
    private func accountCard(_ account: CLIAccount, provider: CLIProviderKind) -> some View {
        let isConnected = accountAuthStatus(account).isLoggedIn
        let identity = CLIAccountAuthDetector.identity(account: account)

        VStack(alignment: .leading, spacing: 8) {
            // Row 1: Avatar + Label + Enabled toggle
            HStack(spacing: 10) {
                accountAvatar(account)

                TextField("Label", text: Binding(
                    get: { account.label },
                    set: { var u = account; u.label = $0; cliAccountsStore.update(u) }
                ))
                .textFieldStyle(.plain)
                .font(.system(size: 12, weight: .medium))

                Spacer()

                Toggle("", isOn: Binding(
                    get: { account.isEnabled },
                    set: { var u = account; u.isEnabled = $0; cliAccountsStore.update(u) }
                ))
                .toggleStyle(.switch)
                .controlSize(.mini)
                .labelsHidden()
            }

            if let displayName = identity?.displayName, !displayName.isEmpty {
                Text(displayName)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            if let email = identity?.email, !email.isEmpty {
                Text(email)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            // Row 2: Status + usage
            HStack(spacing: 8) {
                statusBadge(connected: isConnected, label: accountStatusLabel(account))

                Spacer()

                let day = cliUsageLedger.totals(accountId: account.id, period: .day)
                let month = cliUsageLedger.totals(accountId: account.id, period: .month)
                Text("$\(day.cost, specifier: "%.2f")/d")
                    .font(.system(size: 10)).foregroundStyle(.tertiary)
                Text("$\(month.cost, specifier: "%.2f")/m")
                    .font(.system(size: 10)).foregroundStyle(.tertiary)
            }

            // Row 3: Actions
            HStack(spacing: 6) {
                if !isConnected {
                    Button("Sign In") {
                        loginSheetAccount = account
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                } else {
                    Button("Disconnect") { disconnectAccount(account) }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }

                Spacer()

                Button(role: .destructive) {
                    showDeleteConfirmation = account.id
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 10))
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .alert("Delete Account",
                       isPresented: Binding(
                        get: { showDeleteConfirmation == account.id },
                        set: { if !$0 { showDeleteConfirmation = nil } }
                       )
                ) {
                    Button("Delete", role: .destructive) {
                        cliAccountsStore.delete(accountId: account.id)
                    }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("Remove \"\(account.label)\"? This will delete the profile directory and credentials.")
                }
            }
        }
        .padding(10)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(isConnected ? Color.green.opacity(0.3) : Color.clear, lineWidth: 1)
        )
    }

    private func accountAvatar(_ account: CLIAccount) -> some View {
        let fallback = account.label.trimmingCharacters(in: .whitespacesAndNewlines)
        let identity = CLIAccountAuthDetector.identity(account: account)
        let displayName = identity?.displayName ?? ""
        let email = identity?.email ?? ""
        let seed = !displayName.isEmpty ? displayName : (email.isEmpty ? fallback : email)
        let initial = seed.isEmpty ? "?" : String(seed.prefix(1)).uppercased()

        return ZStack {
            Circle()
                .fill(providerAvatarColor(account.provider))
                .frame(width: 28, height: 28)
            Text(initial)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white)
        }
    }

    private func providerAvatarColor(_ provider: CLIProviderKind) -> Color {
        switch provider {
        case .codex: return .green
        case .claude: return .orange
        case .gemini: return .blue
        }
    }

    // MARK: - Account Actions

    private func accountStatusLabel(_ account: CLIAccount) -> String {
        let auth = accountAuthStatus(account)
        if account.health.isExhaustedLocally { return "Exhausted (local limit)" }
        if let until = account.health.cooldownUntil, until > Date() {
            return "Cooldown until \(until.formatted(date: .omitted, time: .shortened))"
        }
        switch auth {
        case .loggedIn(let method): return "Connected (\(method.rawValue))"
        case .notLoggedIn: return "Not connected"
        case .notInstalled: return "CLI not installed"
        case .error(let message): return "Auth error: \(message)"
        }
    }

    private func codexCreditsLabel() -> String {
        guard let usage = providerUsageStore.codexUsage, let balance = usage.creditsBalance else { return "Credits: N/A" }
        let currency = usage.creditsCurrency ?? "USD"
        return String(format: "Credits: %.2f %@", balance, currency)
    }

    private func disconnectAccount(_ account: CLIAccount) {
        accountLoginCoordinator.disconnect(account: account)
        let status = accountAuthStatus(account)
        cliAccountsStore.updateAuthStatus(accountId: account.id, status: status)
    }

    private func accountAuthStatus(_ account: CLIAccount) -> CLIAccountAuthStatus {
        CLIAccountAuthDetector.detect(account: account, providerPath: providerPath(for: account.provider))
    }

    private func providerPath(for provider: CLIProviderKind) -> String? {
        switch provider {
        case .codex: return codexPath
        case .claude: return claudePath
        case .gemini: return geminiCliPath
        }
    }

    private func connectToCodex() {
        guard codexState.status.path != nil || CodexDetector.findCodexPath(customPath: codexPath.isEmpty ? nil : codexPath) != nil else { return }
        if codexState.status.isLoggedIn {
            syncCodex()
        } else {
            // Create a quick account and open the login sheet
            let existingAccounts = cliAccountsStore.accounts(for: .codex)
            if let first = existingAccounts.first {
                loginSheetAccount = first
            } else {
                let account = cliAccountsStore.addAccountQuick(provider: .codex)
                pendingLoginAccountIds.insert(account.id)
                loginSheetAccount = account
            }
        }
    }

    private func handleLoginSheetDismiss(for account: CLIAccount) {
        defer {
            pendingLoginAccountIds.remove(account.id)
            syncProviders()
        }
        guard cliAccountsStore.accounts.contains(where: { $0.id == account.id }) else { return }

        let status = accountAuthStatus(account)
        cliAccountsStore.updateAuthStatus(accountId: account.id, status: status)

        if status.isLoggedIn {
            let primaryId = cliAccountsStore.finalizePostLogin(
                accountId: account.id,
                preferredActiveAccountId: CLIAccountRouter.shared.currentActiveAccountByProvider[account.provider]
            ) ?? account.id
            CLIAccountRouter.shared.markAccountSelected(
                accountId: primaryId,
                provider: account.provider,
                reason: "login_success"
            )
            return
        }

        if pendingLoginAccountIds.contains(account.id) {
            cliAccountsStore.delete(accountId: account.id)
        }
    }

    // MARK: - Sync Functions

    private func syncProviders() {
        syncOpenAI(); syncAnthropic(); syncGoogle(); syncMiniMax(); syncOpenRouter(); syncGrok()
        syncCodex(); syncClaude(); syncGemini()
        syncSwarm(); syncCodeReview(); syncPlanProvider()
    }

    private func syncPlanProvider() {}
    private func syncSwarm() {}
    private func syncCodeReview() {}

    private func syncOpenAI() {
        let effort = OpenAIAPIProvider.isReasoningModel(openaiModel) ? reasoningEffort : nil
        reregisterProviderPreservingSelection(id: "openai-api", provider:
            ProviderFactory.openAIAPIProvider(
                config: providerFactoryConfig(),
                reasoningEffort: effort,
                executionController: executionController,
                codebaseIndex: workspaceStore.codebaseIndex,
                workspacePaths: workspaceStore.activeWorkspacePaths
            ))
    }

    private func syncAnthropic() {
        reregisterProviderPreservingSelection(id: "anthropic-api", provider:
            ProviderFactory.anthropicAPIProvider(
                config: providerFactoryConfig(),
                executionController: executionController,
                codebaseIndex: workspaceStore.codebaseIndex,
                workspacePaths: workspaceStore.activeWorkspacePaths
            ))
    }

    private func syncGoogle() {
        reregisterProviderPreservingSelection(id: "google-api", provider:
            ProviderFactory.googleAPIProvider(
                config: providerFactoryConfig(),
                executionController: executionController,
                codebaseIndex: workspaceStore.codebaseIndex,
                workspacePaths: workspaceStore.activeWorkspacePaths
            ))
    }

    private func syncMiniMax() {
        reregisterProviderPreservingSelection(id: "minimax-api", provider:
            ProviderFactory.miniMaxAPIProvider(
                config: providerFactoryConfig(),
                executionController: executionController,
                codebaseIndex: workspaceStore.codebaseIndex,
                workspacePaths: workspaceStore.activeWorkspacePaths
            ))
    }

    private func syncOpenRouter() {
        reregisterProviderPreservingSelection(id: "openrouter-api", provider:
            ProviderFactory.openRouterAPIProvider(
                config: providerFactoryConfig(),
                executionController: executionController,
                codebaseIndex: workspaceStore.codebaseIndex,
                workspacePaths: workspaceStore.activeWorkspacePaths
            ))
    }

    private func syncGrok() {
        reregisterProviderPreservingSelection(id: "grok-api", provider:
            ProviderFactory.grokAPIProvider(
                config: providerFactoryConfig(),
                executionController: executionController,
                codebaseIndex: workspaceStore.codebaseIndex,
                workspacePaths: workspaceStore.activeWorkspacePaths
            ))
    }

    private func syncCodex() {
        reregisterProviderPreservingSelection(id: "codex-cli", provider:
            ProviderFactory.codexProvider(
                config: providerFactoryConfig(),
                executionController: executionController,
                codebaseIndex: workspaceStore.codebaseIndex,
                workspacePaths: workspaceStore.activeWorkspacePaths
            ))
    }

    private func syncClaude() {
        reregisterProviderPreservingSelection(id: "claude-cli", provider:
            ProviderFactory.claudeProvider(
                config: providerFactoryConfig(),
                executionController: executionController,
                codebaseIndex: workspaceStore.codebaseIndex,
                workspacePaths: workspaceStore.activeWorkspacePaths
            ))
        syncSwarm(); syncPlanProvider()
    }

    private func syncGemini() {
        reregisterProviderPreservingSelection(id: "gemini-cli", provider:
            ProviderFactory.geminiProvider(
                config: providerFactoryConfig(),
                executionController: executionController,
                codebaseIndex: workspaceStore.codebaseIndex,
                workspacePaths: workspaceStore.activeWorkspacePaths
            ))
    }

    private func reregisterProviderPreservingSelection(id: String, provider: (any LLMProvider)?) {
        let wasSel = providerRegistry.selectedProviderId
        providerRegistry.unregister(id: id)
        if let provider { providerRegistry.register(provider) }
        if wasSel == id, provider != nil { providerRegistry.selectedProviderId = id }
    }

    // MARK: - Provider Factory Config

    private func providerFactoryConfig() -> ProviderFactoryConfig {
        ProviderFactoryConfig(
            openaiApiKey: openaiApiKey, openaiModel: openaiModel,
            anthropicApiKey: anthropicApiKey, anthropicModel: anthropicModel,
            googleApiKey: googleApiKey, googleModel: googleModel,
            minimaxApiKey: minimaxApiKey, minimaxModel: minimaxModel,
            openrouterApiKey: openrouterApiKey, openrouterModel: openrouterModel,
            grokApiKey: grokApiKey, grokModel: grokModel,
            codexPath: codexPath, codexSandbox: codexSandbox,
            codexSessionFullAccess: codexSessionFullAccess,
            codexAskForApproval: codexAskForApproval,
            codexModelOverride: codexModelOverride,
            codexReasoningEffort: codexReasoningEffort,
            codexModelProvider: codexModelProvider,
            codexPreferResponsesWireAPI: codexPreferResponsesWireAPI,
            planModeBackend: planModeBackend,
            swarmOrchestrator: swarmOrchestrator, swarmWorkerBackend: swarmWorkerBackend,
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
            claudePath: claudePath, claudeModel: claudeModel,
            claudeAllowedTools: parseClaudeAllowedTools(),
            geminiCliPath: geminiCliPath, geminiModelOverride: geminiModelOverride,
            unifiedToolRuntimeEnabled: unifiedToolRuntimeEnabled,
            agentsHardBlockEnabled: agentsHardBlockEnabled,
            webSearchProvider: webSearchProvider,
            braveSearchApiKey: braveSearchApiKey,
            tavilyApiKey: tavilyApiKey,
            serperApiKey: serperApiKey
        )
    }

    // MARK: - Normalization

    private func normalizeStoredSelections() {
        if !openAIModels.contains(openaiModel), let first = openAIModels.first { openaiModel = first }
        if !anthropicModels.contains(anthropicModel), let first = anthropicModels.first { anthropicModel = first }
        if !googleModels.contains(googleModel), let first = googleModels.first { googleModel = first }
        if !minimaxModels.contains(minimaxModel), let first = minimaxModels.first { minimaxModel = first }
        if !grokModels.contains(grokModel), let first = grokModels.first { grokModel = first }
        if !["low", "medium", "high"].contains(reasoningEffort) { reasoningEffort = "medium" }
        if !["read-only", "workspace-write", "danger-full-access"].contains(codexSandbox) { codexSandbox = "workspace-write" }
        if !["never", "on-request", "untrusted"].contains(codexAskForApproval) { codexAskForApproval = "never" }
        if !["codex", "claude"].contains(planModeBackend) { planModeBackend = "codex" }
        let validClaudeSlugs = ClaudeModelsCache.loadModels().map(\.slug)
        if !validClaudeSlugs.contains(claudeModel) {
            switch claudeModel {
            case "sonnet": claudeModel = "claude-sonnet-4-6"
            case "opus": claudeModel = "claude-opus-4-6"
            case "haiku": claudeModel = "claude-haiku-4-5-20251001"
            default: claudeModel = "claude-sonnet-4-6"
            }
        }
        if !["system", "light", "dark"].contains(appearance) { appearance = "system" }
        chatBackgroundStyle = ChatBackgroundStyle.normalizedRawValue(chatBackgroundStyle)
        if !["openai-api", "codex-cli", "claude-cli"].contains(summarizeProvider) { summarizeProvider = "openai-api" }
    }

    // MARK: - Codex TOML

    private func loadCodexAdvanced() {
        let cfg = CodexConfigLoader.load()
        codexSandbox = cfg.sandboxMode ?? ""
        codexModelOverride = cfg.model ?? ""
        codexModelProvider = cfg.modelProvider ?? ""
        codexReasoningEffort = cfg.modelReasoningEffort ?? "low"
        codexReasoningSummary = cfg.modelReasoningSummary ?? "auto"
        codexVerbosity = cfg.modelVerbosity ?? "medium"
        let validPersonalities = ["none", "friendly", "pragmatic"]
        codexPersonality = validPersonalities.contains(cfg.personality ?? "none") ? (cfg.personality ?? "none") : "none"
        codexNetworkAccess = cfg.networkAccess ?? false
        codexAdditionalWriteRoots = cfg.additionalWriteRoots.joined(separator: ", ")
        codexDeveloperInstructions = cfg.developerInstructions ?? ""
        codexCheckUpdate = cfg.checkForUpdateOnStartup ?? true
        codexAgentsMd = CodexAgentsFile.loadGlobal()
        normalizeStoredSelections()
        reloadRulesFromDisk()
    }

    private func saveCodexToml() {
        var cfg = CodexConfigLoader.load()
        if !codexSandbox.isEmpty { cfg.sandboxMode = codexSandbox }
        if !codexModelOverride.isEmpty { cfg.model = codexModelOverride }
        if !codexModelProvider.isEmpty { cfg.modelProvider = codexModelProvider }
        if !codexReasoningEffort.isEmpty { cfg.modelReasoningEffort = codexReasoningEffort }
        cfg.modelReasoningSummary = codexReasoningSummary == "auto" ? nil : codexReasoningSummary
        cfg.modelVerbosity = codexVerbosity == "medium" ? nil : codexVerbosity
        cfg.personality = codexPersonality == "none" ? nil : codexPersonality
        cfg.networkAccess = codexNetworkAccess ? true : nil
        cfg.additionalWriteRoots = codexAdditionalWriteRoots.components(separatedBy: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        cfg.developerInstructions = codexDeveloperInstructions.isEmpty ? nil : codexDeveloperInstructions
        cfg.checkForUpdateOnStartup = codexCheckUpdate ? nil : false
        CodexConfigLoader.save(cfg)
    }

    // MARK: - Index Status

    private func refreshIndexStatus() async {
        let index = workspaceStore.codebaseIndex
        let info = await index.status()
        switch info.status {
        case .idle: indexStatusText = "Idle - no indexed workspace"
        case .indexing: indexStatusText = "Indexing..."
        case .ready:
            let duration = info.indexDurationMs > 0 ? " (\(info.indexDurationMs)ms)" : ""
            indexStatusText = "Ready\(duration)"
        case .error: indexStatusText = "Indexing error"
        }
        var stats: [String] = []
        if info.totalFiles > 0 { stats.append("\(info.totalFiles) files") }
        if info.totalSourceFiles > 0 { stats.append("\(info.totalSourceFiles) sources") }
        if info.totalSymbols > 0 { stats.append("\(info.totalSymbols) symbols") }
        indexStatsText = stats.joined(separator: " · ")
    }

    // MARK: - Helpers

    private func parseClaudeAllowedTools() -> [String] {
        ProviderFactory.normalizedToolList(from: claudeAllowedTools)
    }

    private var currentProjectRootPath: String? {
        if let active = workspaceStore.activeWorkspace, let root = active.folderPaths.first, !root.isEmpty { return root }
        return workspaceStore.workspaces.first(where: { !$0.folderPaths.isEmpty })?.folderPaths.first
    }

    // MARK: - Rules CRUD

    private func reloadRulesFromDisk() {
        globalRuleDocs = CoderRulesFile.loadGlobalRules()
        if selectedGlobalRuleName.isEmpty || !globalRuleDocs.contains(where: { $0.name == selectedGlobalRuleName }) {
            selectedGlobalRuleName = globalRuleDocs.first?.name ?? ""
        }
        globalRuleContentDraft = globalRuleDocs.first(where: { $0.name == selectedGlobalRuleName })?.content ?? ""
        if let root = currentProjectRootPath {
            projectRuleDocs = CoderRulesFile.loadProjectRules(workspacePath: root)
            if selectedProjectRuleName.isEmpty || !projectRuleDocs.contains(where: { $0.name == selectedProjectRuleName }) {
                selectedProjectRuleName = projectRuleDocs.first?.name ?? ""
            }
            projectRuleContentDraft = projectRuleDocs.first(where: { $0.name == selectedProjectRuleName })?.content ?? ""
        } else {
            projectRuleDocs = []; selectedProjectRuleName = ""; projectRuleContentDraft = ""
        }
    }

    private func createGlobalRule() {
        let base = newGlobalRuleName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !base.isEmpty else { return }
        CoderRulesFile.saveGlobalRule(name: base, content: "# \(base.replacingOccurrences(of: ".md", with: ""))\n")
        newGlobalRuleName = ""; reloadRulesFromDisk()
        if let created = globalRuleDocs.last?.name {
            selectedGlobalRuleName = created
            globalRuleContentDraft = globalRuleDocs.first(where: { $0.name == created })?.content ?? ""
        }
    }

    private func saveSelectedGlobalRule() {
        guard !selectedGlobalRuleName.isEmpty else { return }
        CoderRulesFile.saveGlobalRule(name: selectedGlobalRuleName, content: globalRuleContentDraft)
        reloadRulesFromDisk()
    }

    private func deleteSelectedGlobalRule() {
        guard !selectedGlobalRuleName.isEmpty else { return }
        CoderRulesFile.deleteGlobalRule(name: selectedGlobalRuleName); reloadRulesFromDisk()
    }

    private func createProjectRule() {
        guard let root = currentProjectRootPath else { return }
        let base = newProjectRuleName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !base.isEmpty else { return }
        CoderRulesFile.saveProjectRule(name: base, content: "# \(base.replacingOccurrences(of: ".md", with: ""))\n", workspacePath: root)
        newProjectRuleName = ""; reloadRulesFromDisk()
        if let created = projectRuleDocs.last?.name {
            selectedProjectRuleName = created
            projectRuleContentDraft = projectRuleDocs.first(where: { $0.name == created })?.content ?? ""
        }
    }

    private func saveSelectedProjectRule() {
        guard let root = currentProjectRootPath, !selectedProjectRuleName.isEmpty else { return }
        CoderRulesFile.saveProjectRule(name: selectedProjectRuleName, content: projectRuleContentDraft, workspacePath: root)
        reloadRulesFromDisk()
    }

    private func deleteSelectedProjectRule() {
        guard let root = currentProjectRootPath, !selectedProjectRuleName.isEmpty else { return }
        CoderRulesFile.deleteProjectRule(name: selectedProjectRuleName, workspacePath: root); reloadRulesFromDisk()
    }

    private func openFullDiskAccessPreferences() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
            NSWorkspace.shared.open(url)
        }
    }

    private func refreshUsageSnapshotsForSettings() async {
        let codexBin = CodexDetector.findCodexPath(customPath: codexPath.isEmpty ? nil : codexPath) ?? ""
        let claudeBin = ClaudeDetector.findClaudePath(customPath: claudePath.isEmpty ? nil : claudePath) ?? ""
        let geminiBin = GeminiDetector.findGeminiPath(customPath: geminiCliPath.isEmpty ? nil : geminiCliPath) ?? ""
        await providerUsageStore.fetchCodexUsage(codexPath: codexBin, workingDirectory: nil)
        await providerUsageStore.fetchClaudeUsage(
            claudePath: claudeBin,
            workingDirectory: nil,
            anthropicAdminApiKey: anthropicAdminApiKey
        )
        await providerUsageStore.fetchGeminiUsage(geminiPath: geminiBin, workingDirectory: nil)
    }
}
