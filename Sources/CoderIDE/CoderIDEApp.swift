import AppKit
import CoderEngine
import SwiftUI

@main
struct CodigoApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var providerRegistry = ProviderRegistry()
    @StateObject private var chatStore = ChatStore()
    @StateObject private var workspaceStore = WorkspaceStore()
    @StateObject private var projectContextStore = ProjectContextStore()
    @StateObject private var openFilesStore = OpenFilesStore()
    @StateObject private var taskActivityStore = TaskActivityStore()
    @StateObject private var toolTraceStore = ToolTraceStore()
    @StateObject private var todoStore = TodoStore()
    @StateObject private var swarmProgressStore = SwarmProgressStore()
    @StateObject private var codexState = CodexStateStore()
    @StateObject private var executionController = ExecutionController()
    @StateObject private var providerUsageStore = ProviderUsageStore.shared
    @StateObject private var gitPanelStore = GitPanelStore()
    @StateObject private var planHistoryStore = PlanHistoryStore()
    @StateObject private var accountUsageDashboardStore = AccountUsageDashboardStore.shared
    @AppStorage("openai_api_key") private var apiKey = ""
    @AppStorage("openai_model") private var model = "gpt-4o-mini"
    @AppStorage("anthropic_api_key") private var anthropicApiKey = ""
    @AppStorage("anthropic_model") private var anthropicModel = "claude-sonnet-4-6"
    @AppStorage("google_api_key") private var googleApiKey = ""
    @AppStorage("google_model") private var googleModel = "gemini-2.5-pro"
    @AppStorage("codex_path") private var codexPath = ""
    @AppStorage("codex_sandbox") private var codexSandbox = ""
    @AppStorage("codex_ask_for_approval") private var codexAskForApproval = "never"
    @AppStorage("codex_model_override") private var codexModelOverride = ""
    @AppStorage("codex_reasoning_effort") private var codexReasoningEffort = "low"
    @AppStorage("codex_model_provider") private var codexModelProvider = ""
    @AppStorage("codex_prefer_responses_wire_api")
    private var codexPreferResponsesWireAPI = false
    @AppStorage("plan_mode_backend") private var planModeBackend = "codex"
    @AppStorage("claude_path") private var claudePath = ""
    @AppStorage("claude_model") private var claudeModel = "claude-sonnet-4-6"
    @AppStorage("claude_allowed_tools") private var claudeAllowedTools =
        "Read,Edit,Bash,Write,Search"
    @AppStorage("unified_tool_runtime_enabled") private var unifiedToolRuntimeEnabled = true
    @AppStorage("agents_hard_block_enabled") private var agentsHardBlockEnabled = true
    @AppStorage("swarm_orchestrator") private var swarmOrchestrator = "auto"
    @AppStorage("swarm_worker_backend") private var swarmWorkerBackend = "auto"
    @AppStorage("swarm_auto_post_code_pipeline") private var swarmAutoPostCodePipeline = true
    @AppStorage("swarm_max_post_code_retries") private var swarmMaxPostCodeRetries = 10
    @AppStorage("swarm_max_review_loops") private var swarmMaxReviewLoops = 2
    @AppStorage("swarm_enabled_roles") private var swarmEnabledRoles =
        "planner,coder,debugger,reviewer,testWriter"
    @AppStorage("global_yolo") private var globalYolo = false
    @AppStorage("code_review_partitions") private var codeReviewPartitions = 3
    @AppStorage("code_review_analysis_only") private var codeReviewAnalysisOnly = false
    @AppStorage("code_review_max_rounds") private var codeReviewMaxRounds = 3
    @AppStorage("code_review_analysis_backend") private var codeReviewAnalysisBackend = "codex-cli"
    @AppStorage("code_review_execution_backend") private var codeReviewExecutionBackend = "codex-cli"
    @AppStorage("appearance") private var appearance = "system"
    @AppStorage("ui_sans_font_family") private var uiSansFontFamily = FontPreferences.defaultSansFamily
    @AppStorage("ui_sans_font_size") private var uiSansFontSize = FontPreferences.defaultSansSize
    @AppStorage("ui_code_font_family") private var uiCodeFontFamily = FontPreferences.defaultCodeFamily
    @AppStorage("ui_code_font_size") private var uiCodeFontSize = FontPreferences.defaultCodeSize
    @AppStorage("minimax_api_key") private var minimaxApiKey = ""
    @AppStorage("minimax_model") private var minimaxModel = "MiniMax-M2.5"
    @AppStorage("openrouter_api_key") private var openrouterApiKey = ""
    @AppStorage("openrouter_model") private var openrouterModel = "anthropic/claude-sonnet-4-6"
    @AppStorage("gemini_cli_path") private var geminiCliPath = ""
    @AppStorage("gemini_model_override") private var geminiModelOverride = ""
    @AppStorage("grok_api_key") private var grokApiKey = ""
    @AppStorage("grok_model") private var grokModel = "grok-4-1-fast-reasoning"
    @AppStorage("web_search_provider") private var webSearchProvider = "duckduckgo"
    @AppStorage("brave_search_api_key") private var braveSearchApiKey = ""
    @AppStorage("tavily_api_key") private var tavilyApiKey = ""
    @AppStorage("serper_api_key") private var serperApiKey = ""

    private var colorScheme: ColorScheme? {
        switch appearance {
        case "light": return .light
        case "dark": return .dark
        default: return nil
        }
    }

    private var resolvedSansFont: Font {
        FontPreferences.resolveSansFont(
            size: FontPreferences.sanitizeSize(uiSansFontSize, kind: .sans),
            family: uiSansFontFamily
        )
    }

    var body: some Scene {
        WindowGroup {
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
                .onAppear {
                    FontPreferences.registerBundledFonts()
                    projectContextStore.ensureWorkspaceContexts(workspaceStore.workspaces)
                    chatStore.migrateLegacyContextsIfNeeded(
                        contextStore: projectContextStore, workspaceStore: workspaceStore)
                    chatStore.backfillPlanAttachmentsIfNeeded(historyStore: planHistoryStore)
                    registerProviders()
                    configureWindow()
                }
        }
        MenuBarExtra {
            UsageMenuBarView()
                .environmentObject(accountUsageDashboardStore)
        } label: {
            if let url = Bundle.module.url(forResource: "AppLogo", withExtension: "png"),
               let img = NSImage(contentsOf: url) {
                let resized = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { rect in
                    img.draw(in: rect)
                    return true
                }
                Image(nsImage: resized)
            } else {
                Image(systemName: "chart.bar.fill")
            }
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }
    }

    private func configureWindow() {
        let candidates = NSApplication.shared.windows.filter { $0.canBecomeMain }
        for window in candidates {
            window.minSize = NSSize(width: 860, height: 500)
            window.backgroundColor = DesignSystem.AppKit.windowBackground
            AppDelegate.applyMainWindowStyle(window)
        }
    }

    private func registerProviders() {
        if providerRegistry.provider(for: "openai-api") == nil {
            let effort = OpenAIAPIProvider.isReasoningModel(model) ? "medium" : nil
            providerRegistry.register(
                ProviderFactory.openAIAPIProvider(
                    config: providerFactoryConfig(), reasoningEffort: effort,
                    executionController: executionController,
                    codebaseIndex: workspaceStore.codebaseIndex,
                    workspacePaths: workspaceStore.activeWorkspacePaths))
        }
        if providerRegistry.provider(for: "anthropic-api") == nil {
            providerRegistry.register(
                ProviderFactory.anthropicAPIProvider(
                    config: providerFactoryConfig(),
                    executionController: executionController,
                    codebaseIndex: workspaceStore.codebaseIndex,
                    workspacePaths: workspaceStore.activeWorkspacePaths))
        }
        if providerRegistry.provider(for: "google-api") == nil {
            providerRegistry.register(
                ProviderFactory.googleAPIProvider(
                    config: providerFactoryConfig(),
                    executionController: executionController,
                    codebaseIndex: workspaceStore.codebaseIndex,
                    workspacePaths: workspaceStore.activeWorkspacePaths))
        }
        if providerRegistry.provider(for: "codex-cli") == nil {
            providerRegistry.register(
                ProviderFactory.codexProvider(
                    config: providerFactoryConfig(),
                    executionController: executionController,
                    codebaseIndex: workspaceStore.codebaseIndex,
                    workspacePaths: workspaceStore.activeWorkspacePaths))
        }
        if providerRegistry.provider(for: "claude-cli") == nil {
            providerRegistry.register(
                ProviderFactory.claudeProvider(
                    config: providerFactoryConfig(),
                    executionController: executionController,
                    codebaseIndex: workspaceStore.codebaseIndex,
                    workspacePaths: workspaceStore.activeWorkspacePaths
                ))
        }
        if providerRegistry.provider(for: "gemini-cli") == nil {
            providerRegistry.register(
                ProviderFactory.geminiProvider(
                    config: providerFactoryConfig(),
                    executionController: executionController,
                    codebaseIndex: workspaceStore.codebaseIndex,
                    workspacePaths: workspaceStore.activeWorkspacePaths
                ))
        }
        registerMiniMax()
        registerOpenRouter()
        registerGrok()
    }

    private func registerMiniMax() {
        providerRegistry.unregister(id: "minimax-api")
        providerRegistry.register(
            ProviderFactory.miniMaxAPIProvider(
                config: providerFactoryConfig(),
                executionController: executionController,
                codebaseIndex: workspaceStore.codebaseIndex,
                workspacePaths: workspaceStore.activeWorkspacePaths))
    }

    private func registerOpenRouter() {
        providerRegistry.unregister(id: "openrouter-api")
        providerRegistry.register(
            ProviderFactory.openRouterAPIProvider(
                config: providerFactoryConfig(),
                executionController: executionController,
                codebaseIndex: workspaceStore.codebaseIndex,
                workspacePaths: workspaceStore.activeWorkspacePaths))
    }

    private func registerGrok() {
        providerRegistry.unregister(id: "grok-api")
        providerRegistry.register(
            ProviderFactory.grokAPIProvider(
                config: providerFactoryConfig(),
                executionController: executionController,
                codebaseIndex: workspaceStore.codebaseIndex,
                workspacePaths: workspaceStore.activeWorkspacePaths))
    }

    private func providerFactoryConfig() -> ProviderFactoryConfig {
        let effectiveSandbox =
            codexSandbox.isEmpty
            ? (CodexConfigLoader.load().sandboxMode ?? "workspace-write") : codexSandbox
        let tools = ProviderFactory.normalizedToolList(from: claudeAllowedTools)
        return ProviderFactoryConfig(
            openaiApiKey: apiKey,
            openaiModel: model,
            anthropicApiKey: anthropicApiKey,
            anthropicModel: anthropicModel,
            googleApiKey: googleApiKey,
            googleModel: googleModel,
            minimaxApiKey: minimaxApiKey,
            minimaxModel: minimaxModel,
            openrouterApiKey: openrouterApiKey,
            openrouterModel: openrouterModel,
            grokApiKey: grokApiKey,
            grokModel: grokModel,
            codexPath: codexPath,
            codexSandbox: effectiveSandbox,
            codexSessionFullAccess: false,
            codexAskForApproval: codexAskForApproval,
            codexModelOverride: codexModelOverride,
            codexReasoningEffort: codexReasoningEffort,
            codexModelProvider: codexModelProvider,
            codexPreferResponsesWireAPI: codexPreferResponsesWireAPI,
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
            codeReviewExecutionBackend: codeReviewExecutionBackend,
            claudePath: claudePath,
            claudeModel: claudeModel,
            claudeAllowedTools: tools,
            geminiCliPath: geminiCliPath,
            geminiModelOverride: geminiModelOverride,
            unifiedToolRuntimeEnabled: unifiedToolRuntimeEnabled,
            agentsHardBlockEnabled: agentsHardBlockEnabled,
            webSearchProvider: webSearchProvider,
            braveSearchApiKey: braveSearchApiKey,
            tavilyApiKey: tavilyApiKey,
            serperApiKey: serperApiKey
        )
    }
}
