import AppKit
import CoderEngine
import SwiftUI

// MARK: - Settings View

struct SettingsView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var workspaceStore: WorkspaceStore
    @EnvironmentObject var providerRegistry: ProviderRegistry
    @EnvironmentObject var executionController: ExecutionController
    @EnvironmentObject var providerUsageStore: ProviderUsageStore
    @EnvironmentObject var appUpdateCenter: AppUpdateCenter
    @State var selectedSection: SettingsSection = .apiKeys

    // MARK: - Provider API Keys
    @AppStorage("openai_api_key") var openaiApiKey = ""
    @AppStorage("openai_model") var openaiModel = "gpt-4o-mini"
    @AppStorage("reasoning_effort") var reasoningEffort = "medium"
    @AppStorage("anthropic_api_key") var anthropicApiKey = ""
    @AppStorage("anthropic_admin_api_key") var anthropicAdminApiKey = ""
    @AppStorage("anthropic_model") var anthropicModel = "claude-sonnet-4-6"
    @AppStorage("google_api_key") var googleApiKey = ""
    @AppStorage("google_model") var googleModel = "gemini-2.5-pro"
    @AppStorage("minimax_api_key") var minimaxApiKey = ""
    @AppStorage("minimax_model") var minimaxModel = "MiniMax-M2.5"
    @AppStorage("openrouter_api_key") var openrouterApiKey = ""
    @AppStorage("openrouter_model") var openrouterModel = "anthropic/claude-sonnet-4-6"
    @AppStorage("grok_api_key") var grokApiKey = ""
    @AppStorage("grok_model") var grokModel = "grok-4-1-fast-reasoning"
    @AppStorage("web_search_provider") var webSearchProvider = "duckduckgo"
    @AppStorage("brave_search_api_key") var braveSearchApiKey = ""
    @AppStorage("tavily_api_key") var tavilyApiKey = ""
    @AppStorage("serper_api_key") var serperApiKey = ""

    // MARK: - CLI Tools
    @AppStorage("codex_path") var codexPath = ""
    @AppStorage("codex_sandbox") var codexSandbox = "workspace-write"
    @AppStorage("codex_ask_for_approval") var codexAskForApproval = "never"
    @AppStorage("codex_model_override") var codexModelOverride = ""
    @AppStorage("codex_reasoning_effort") var codexReasoningEffort = "low"
    @AppStorage("codex_fast_mode") var codexFastMode = true
    @AppStorage("codex_model_provider") var codexModelProvider = ""
    @AppStorage("codex_prefer_responses_wire_api") var codexPreferResponsesWireAPI = false
    @AppStorage("codex_session_full_access") var codexSessionFullAccess = false
    @AppStorage("codex_network_access") var codexNetworkAccess = false
    @AppStorage("codex_additional_write_roots") var codexAdditionalWriteRoots = ""
    @AppStorage("codex_check_update") var codexCheckUpdate = true
    @AppStorage("codex_developer_instructions") var codexDeveloperInstructions = ""
    @AppStorage("claude_path") var claudePath = ""
    @AppStorage("claude_model") var claudeModel = "claude-sonnet-4-6"
    @AppStorage("claude_allowed_tools") var claudeAllowedTools = "Read,Edit,Bash,Write,Search,Task"
    @AppStorage("gemini_cli_path") var geminiCliPath = ""
    @AppStorage("gemini_model_override") var geminiModelOverride = ""
    @AppStorage("unified_tool_runtime_enabled") var unifiedToolRuntimeEnabled = true
    @AppStorage("agents_hard_block_enabled") var agentsHardBlockEnabled = true
    @AppStorage("mcp_edit_enforcement_enabled") var mcpEditEnforcementEnabled = true

    // MARK: - Hidden runtime keys (no UI, consumed by ProviderFactoryConfig)
    @AppStorage("plan_mode_backend") var planModeBackend = "codex"
    @AppStorage("swarm_orchestrator") var swarmOrchestrator = "auto"
    @AppStorage("swarm_worker_backend") var swarmWorkerBackend = "auto"
    @AppStorage("swarm_enabled_roles") var swarmEnabledRoles = "explorer,coder,debugger,reviewer,testWriter"
    @AppStorage("code_review_partitions") var codeReviewPartitions = 3
    @AppStorage("code_review_analysis_only") var codeReviewAnalysisOnly = false
    @AppStorage("code_review_max_rounds") var codeReviewMaxRounds = 3
    @AppStorage("code_review_analysis_backend") var codeReviewAnalysisBackend = "auto"
    @AppStorage("code_review_execution_backend") var codeReviewExecutionBackend = "auto"
    @AppStorage("code_review_quick_commands_custom_json") var codeReviewQuickCommandsCustomJSON = ""
    @AppStorage("codex_reasoning_summary") var codexReasoningSummary = "auto"
    @AppStorage("codex_verbosity") var codexVerbosity = "medium"
    @AppStorage("codex_personality") var codexPersonality = "none"

    // MARK: - Behavior
    @AppStorage("global_yolo") var globalYolo = false
    @AppStorage("terminal_auto_follow_output") var terminalAutoFollowOutput = true
    @AppStorage("summarize_threshold") var summarizeThreshold = 0.8
    @AppStorage("summarize_keep_last") var summarizeKeepLast = 6
    @AppStorage("summarize_provider") var summarizeProvider = "openai-api"
    @AppStorage("full_auto_tools") var fullAutoTools = true
    @AppStorage(planHistoryMaxEntriesPreferenceKey) var planHistoryMaxEntries = 200
    @AppStorage(planHistoryMaxMarkdownLengthPreferenceKey) var planHistoryMaxMarkdownLength = 65_536
    @AppStorage("app_update_check_enabled") var appUpdateCheckEnabled = true
    @AppStorage("app_update_manifest_url") var appUpdateManifestURL = AppUpdateCenter.defaultManifestURL

    // MARK: - Appearance
    @AppStorage("appearance") var appearance = "system"
    @AppStorage("chat_background_style") var chatBackgroundStyle = ChatBackgroundStyle.defaultRawValue
    @AppStorage("chat_panel_position") var chatPanelPosition = "left"
    @AppStorage("ui_sans_font_family") var uiSansFontFamily = FontPreferences.defaultSansFamily
    @AppStorage("ui_sans_font_size") var uiSansFontSize = FontPreferences.defaultSansSize
    @AppStorage("ui_code_font_family") var uiCodeFontFamily = FontPreferences.defaultCodeFamily
    @AppStorage("ui_code_font_size") var uiCodeFontSize = FontPreferences.defaultCodeSize

    // MARK: - Codebase Index
    @AppStorage("codebase_index_enabled") var codebaseIndexEnabled = true
    @AppStorage("codebase_index_excluded_paths") var codebaseIndexExcludedPaths = ""
    @AppStorage("codebase_index_respect_gitignore") var codebaseIndexRespectGitignore = true
    @AppStorage("codebase_index_excluded_file_patterns") var codebaseIndexExcludedFilePatterns = ""

    // MARK: - State Objects
    @StateObject var codexState = CodexStateStore()
    @StateObject var codexMCPHealth = CodexMCPHealthStore.shared
    @StateObject var geminiState = GeminiStateStore()
    @StateObject var cliAccountsStore = CLIAccountsStore.shared
    @StateObject var cliUsageLedger = CLIAccountUsageLedgerStore.shared
    @StateObject var accountLoginCoordinator = CLIAccountLoginCoordinator()

    // MARK: - UI State
    @State var showOpenRouterLogin = false
    @State var codexAgentsMd = ""
    @State var customAgentsDraft = ""
    @State var savedAgentsSnapshot = ""
    @State var savedPersonalitySnapshot = "none"
    @State var isSavingCustom = false
    @State var customSaveMessage = ""
    @State var claudeMdContent = ""
    @State var globalRuleDocs: [CoderRuleDocument] = []
    @State var projectRuleDocs: [CoderRuleDocument] = []
    @State var selectedGlobalRuleName: String = ""
    @State var selectedProjectRuleName: String = ""
    @State var newGlobalRuleName: String = ""
    @State var newProjectRuleName: String = ""
    @State var globalRuleContentDraft: String = ""
    @State var projectRuleContentDraft: String = ""
    @State var loginSheetAccount: CLIAccount?
    @State var showDeleteConfirmation: UUID?
    @State var pendingLoginAccountIds: Set<UUID> = []
    @State var indexStatusText: String = "Loading..."
    @State var indexStatsText: String = ""
    @State var statusRefreshTask: Task<Void, Never>?

    var availableSansFontFamilies: [String] {
        FontPreferences.availableSansFamilies()
    }

    var availableMonoFontFamilies: [String] {
        FontPreferences.availableMonoFamilies()
    }

    // MARK: - Body

    var body: some View {
        applyBehaviorSyncs(applyCLISyncs(applyProviderSyncs(settingsContent)))
    }

    var settingsContent: some View {
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
            prepareCustomDraftIfNeeded()
            codexMCPHealth.refresh()
            syncProviders()
            reloadRulesFromDisk()
            appUpdateCenter.setUpdateCheckEnabled(appUpdateCheckEnabled)
            appUpdateCenter.setManifestURL(appUpdateManifestURL)
        }
    }

    // MARK: - onChange Handlers

    func applyProviderSyncs<V: View>(_ content: V) -> some View {
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

    func applyCLISyncs<V: View>(_ content: V) -> some View {
        content
            .onChange(of: codexPath) { _, _ in codexState.refresh(); syncCodex() }
            .onChange(of: codexSandbox) { _, _ in syncCodex(); saveCodexToml() }
            .onChange(of: codexAskForApproval) { _, _ in syncCodex() }
            .onChange(of: codexModelOverride) { _, _ in syncCodex(); saveCodexToml() }
            .onChange(of: codexFastMode) { _, _ in syncCodex(); saveCodexToml() }
            .onChange(of: codexModelProvider) { _, _ in syncCodex(); saveCodexToml() }
            .onChange(of: codexPreferResponsesWireAPI) { _, _ in syncCodex() }
            .onChange(of: codexSessionFullAccess) { _, _ in syncCodex() }
            .onChange(of: codexNetworkAccess) { _, _ in saveCodexToml() }
            .onChange(of: codexAdditionalWriteRoots) { _, _ in saveCodexToml() }
            .onChange(of: codexCheckUpdate) { _, _ in saveCodexToml() }
            .onChange(of: codexDeveloperInstructions) { _, _ in saveCodexToml() }
            .onChange(of: claudePath) { _, _ in syncClaude() }
            .onChange(of: claudeModel) { _, _ in syncClaude() }
            .onChange(of: claudeAllowedTools) { _, _ in syncClaude() }
            .onChange(of: geminiCliPath) { _, _ in syncGemini() }
    }

    func applyBehaviorSyncs<V: View>(_ content: V) -> some View {
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
}
