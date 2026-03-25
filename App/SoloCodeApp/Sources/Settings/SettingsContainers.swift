import SwiftUI
import CoderEngine

// MARK: - Provider API Keys & Models

struct SettingsProviderKeys: DynamicProperty {
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
}

// MARK: - CLI Tool Configuration

struct SettingsCLIConfig: DynamicProperty {
    @AppStorage("codex_path") var codexPath = ""
    @AppStorage("codex_sandbox") var codexSandbox = "workspace-write"
    @AppStorage("codex_ask_for_approval") var codexAskForApproval = "never"
    @AppStorage("codex_model_override") var codexModelOverride = ""
    @AppStorage("codex_reasoning_effort") var codexReasoningEffort = "low"
    @AppStorage("codex_fast_mode") var codexFastMode = true
    @AppStorage("codex_model_provider") var codexModelProvider = ""
    @AppStorage("codex_prefer_responses_wire_api") var codexPreferResponsesWireAPI = false
    @AppStorage("codex_session_full_access") var codexSessionFullAccess = false
    @AppStorage(CodexCustomModelProfileSync.settingsKey) var codexCustomGPT54Enabled = false
    @AppStorage("codex_network_access") var codexNetworkAccess = false
    @AppStorage("codex_additional_write_roots") var codexAdditionalWriteRoots = ""
    @AppStorage("codex_check_update") var codexCheckUpdate = true
    @AppStorage("codex_developer_instructions") var codexDeveloperInstructions = ""
    @AppStorage("kilo_path") var kiloPath = ""
    @AppStorage("kilo_model") var kiloModel = ""
    @AppStorage("claude_path") var claudePath = ""
    @AppStorage("claude_model") var claudeModel = "claude-sonnet-4-6"
    @AppStorage("claude_allowed_tools") var claudeAllowedTools = "Read,Edit,Bash,Write,Search,Task"
    @AppStorage("gemini_cli_path") var geminiCliPath = ""
    @AppStorage("gemini_model_override") var geminiModelOverride = ""
    @AppStorage("unified_tool_runtime_enabled") var unifiedToolRuntimeEnabled = true
    @AppStorage("agents_hard_block_enabled") var agentsHardBlockEnabled = true
    @AppStorage("mcp_edit_enforcement_enabled") var mcpEditEnforcementEnabled = true
}

// MARK: - Runtime Configuration (no UI, consumed by ProviderFactoryConfig)

struct SettingsRuntimeConfig: DynamicProperty {
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
}

// MARK: - Behavior

struct SettingsBehaviorConfig: DynamicProperty {
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
}

// MARK: - Appearance

struct SettingsAppearanceConfig: DynamicProperty {
    @AppStorage("appearance") var appearance = "system"
    @AppStorage("chat_background_style") var chatBackgroundStyle = ChatBackgroundStyle.defaultRawValue
    @AppStorage("chat_panel_position") var chatPanelPosition = "left"
    @AppStorage("ui_sans_font_family") var uiSansFontFamily = FontPreferences.defaultSansFamily
    @AppStorage("ui_sans_font_size") var uiSansFontSize = FontPreferences.defaultSansSize
    @AppStorage("ui_code_font_family") var uiCodeFontFamily = FontPreferences.defaultCodeFamily
    @AppStorage("ui_code_font_size") var uiCodeFontSize = FontPreferences.defaultCodeSize
}

// MARK: - Codebase Index

struct SettingsIndexConfig: DynamicProperty {
    @AppStorage("codebase_index_enabled") var codebaseIndexEnabled = true
    @AppStorage("codebase_index_excluded_paths") var codebaseIndexExcludedPaths = ""
    @AppStorage("codebase_index_respect_gitignore") var codebaseIndexRespectGitignore = true
    @AppStorage("codebase_index_excluded_file_patterns") var codebaseIndexExcludedFilePatterns = ""
    @AppStorage("vector_search_enabled") var vectorSearchEnabled = false
    @AppStorage("trigram_index_enabled") var trigramIndexEnabled = false
}
