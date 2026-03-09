import AppKit
import CoderEngine
import SwiftUI

@main
struct CodigoApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject var providerRegistry = ProviderRegistry()
    @StateObject var chatStore = ChatStore()
    @StateObject var workspaceStore = WorkspaceStore()
    @StateObject var projectContextStore = ProjectContextStore()
    @StateObject var openFilesStore = OpenFilesStore()
    @StateObject var taskActivityStore = TaskActivityStore()
    @StateObject var toolTraceStore = ToolTraceStore()
    @StateObject var todoStore = TodoStore()
    @StateObject var swarmProgressStore = SwarmProgressStore()
    @StateObject var codexState = CodexStateStore()
    @StateObject var executionController = ExecutionController()
    @StateObject var providerUsageStore = ProviderUsageStore.shared
    @StateObject var gitPanelStore = GitPanelStore()
    @StateObject var planHistoryStore = PlanHistoryStore()
    @StateObject var accountUsageDashboardStore = AccountUsageDashboardStore.shared
    @StateObject var appUpdateCenter = AppUpdateCenter()
    @StateObject var pipelineIntegrationService = PipelineIntegrationService()
    @State var didStartCodeReviewCommandLoop = false
    @State var didStartBugHunterCommandLoop = false

    @AppStorage("openai_api_key") var apiKey = ""
    @AppStorage("openai_model") var model = "gpt-4o-mini"
    @AppStorage("anthropic_api_key") var anthropicApiKey = ""
    @AppStorage("anthropic_model") var anthropicModel = "claude-sonnet-4-6"
    @AppStorage("google_api_key") var googleApiKey = ""
    @AppStorage("google_model") var googleModel = "gemini-2.5-pro"
    @AppStorage("codex_path") var codexPath = ""
    @AppStorage("codex_sandbox") var codexSandbox = ""
    @AppStorage("codex_session_full_access") var codexSessionFullAccess = false
    @AppStorage("codex_ask_for_approval") var codexAskForApproval = "never"
    @AppStorage("codex_model_override") var codexModelOverride = ""
    @AppStorage("codex_reasoning_effort") var codexReasoningEffort = "low"
    @AppStorage("codex_model_provider") var codexModelProvider = ""
    @AppStorage("codex_prefer_responses_wire_api")
    var codexPreferResponsesWireAPI = false
    @AppStorage("plan_mode_backend") var planModeBackend = "codex"
    @AppStorage("claude_path") var claudePath = ""
    @AppStorage("claude_model") var claudeModel = "claude-sonnet-4-6"
    @AppStorage("claude_allowed_tools") var claudeAllowedTools =
        "Read,Edit,Bash,Write,Search,Task"
    @AppStorage("unified_tool_runtime_enabled") var unifiedToolRuntimeEnabled = true
    @AppStorage("agents_hard_block_enabled") var agentsHardBlockEnabled = true
    @AppStorage("mcp_edit_enforcement_enabled") var mcpEditEnforcementEnabled = true
    @AppStorage("swarm_orchestrator") var swarmOrchestrator = "auto"
    @AppStorage("swarm_worker_backend") var swarmWorkerBackend = "auto"
    @AppStorage("swarm_enabled_roles") var swarmEnabledRoles =
        "explorer,coder,debugger,reviewer,testWriter"
    @AppStorage("global_yolo") var globalYolo = false
    @AppStorage("code_review_partitions") var codeReviewPartitions = 3
    @AppStorage("code_review_analysis_only") var codeReviewAnalysisOnly = false
    @AppStorage("code_review_max_rounds") var codeReviewMaxRounds = 3
    @AppStorage("code_review_analysis_backend") var codeReviewAnalysisBackend = "auto"
    @AppStorage("code_review_execution_backend") var codeReviewExecutionBackend = "auto"
    @AppStorage("appearance") var appearance = "system"
    @AppStorage("ui_sans_font_family") var uiSansFontFamily = FontPreferences.defaultSansFamily
    @AppStorage("ui_sans_font_size") var uiSansFontSize = FontPreferences.defaultSansSize
    @AppStorage("ui_code_font_family") var uiCodeFontFamily = FontPreferences.defaultCodeFamily
    @AppStorage("ui_code_font_size") var uiCodeFontSize = FontPreferences.defaultCodeSize
    @AppStorage("minimax_api_key") var minimaxApiKey = ""
    @AppStorage("minimax_model") var minimaxModel = "MiniMax-M2.5"
    @AppStorage("openrouter_api_key") var openrouterApiKey = ""
    @AppStorage("openrouter_model") var openrouterModel = "anthropic/claude-sonnet-4-6"
    @AppStorage("gemini_cli_path") var geminiCliPath = ""
    @AppStorage("gemini_model_override") var geminiModelOverride = ""
    @AppStorage("grok_api_key") var grokApiKey = ""
    @AppStorage("grok_model") var grokModel = "grok-4-1-fast-reasoning"
    @AppStorage("web_search_provider") var webSearchProvider = "duckduckgo"
    @AppStorage("brave_search_api_key") var braveSearchApiKey = ""
    @AppStorage("tavily_api_key") var tavilyApiKey = ""
    @AppStorage("serper_api_key") var serperApiKey = ""

    var body: some Scene {
        WindowGroup("") {
            ContentView()
                .preferredColorScheme(colorScheme)
                .environment(\.font, resolvedSansFont)
                .environmentObject(providerRegistry)
                .environmentObject(chatStore)
                .environmentObject(workspaceStore)
                .environmentObject(projectContextStore)
                .environmentObject(openFilesStore)
                .environmentObject(taskActivityStore)
                .environmentObject(toolTraceStore)
                .environmentObject(todoStore)
                .environmentObject(swarmProgressStore)
                .environmentObject(codexState)
                .environmentObject(executionController)
                .environmentObject(providerUsageStore)
                .environmentObject(gitPanelStore)
                .environmentObject(planHistoryStore)
                .environmentObject(accountUsageDashboardStore)
                .environmentObject(appUpdateCenter)
                .environmentObject(pipelineIntegrationService)
                .onAppear {
                    configureWindow()
                    bootstrapPersistenceIfNeeded()
                    Task { @MainActor in
                        FontPreferences.registerBundledFonts()
                        projectContextStore.ensureWorkspaceContexts(workspaceStore.workspaces)
                        workspaceStore.syncActiveWorkspace(with: projectContextStore.activeContext)
                        chatStore.migrateLegacyContextsIfNeeded(
                            contextStore: projectContextStore, workspaceStore: workspaceStore)
                        chatStore.backfillPlanAttachmentsIfNeeded(historyStore: planHistoryStore)
                        CLIAccountsStore.shared.bootstrapAccountsIfNeeded()
                        CLIAccountRouter.shared.bootstrapActiveSelectionsIfNeeded()
                        CodexMCPHealthStore.shared.refresh()
                        await appUpdateCenter.checkForUpdates()
                        registerProviders()
                        pipelineIntegrationService.configure(
                            chatStore: chatStore,
                            taskActivityStore: taskActivityStore,
                            swarmProgressStore: swarmProgressStore,
                            todoStore: todoStore,
                            executionController: executionController
                        )
                        gitPanelStore.postCommitBugHunterObserver = { commit, gitRoot in
                            Task { @MainActor in
                                self.enqueueBugHunterPostCommit(
                                    commit: commit,
                                    gitRoot: gitRoot,
                                    triggerKind: .appCommit
                                )
                            }
                        }
                        startCodeReviewCommandLoopIfNeeded()
                        startBugHunterCommandLoopIfNeeded()
                    }
                }
        }
        .commands {
            appFileCommands
        }
        MenuBarExtra {
            UsageMenuBarView()
                .environmentObject(accountUsageDashboardStore)
        } label: {
            if let img = Self.cachedMenuBarImage {
                Image(nsImage: img)
            } else {
                Image(systemName: "chart.bar.fill")
            }
        }
    }
}
