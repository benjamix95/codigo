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
    @StateObject private var todoStore = TodoStore()
    @StateObject private var swarmProgressStore = SwarmProgressStore()
    @StateObject private var codexState = CodexStateStore()
    @StateObject private var executionController = ExecutionController()
    @StateObject private var providerUsageStore = ProviderUsageStore.shared
    @StateObject private var flowDiagnosticsStore = FlowDiagnosticsStore()
    @StateObject private var changedFilesStore = ChangedFilesStore()
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
    @AppStorage("codex_reasoning_effort") private var codexReasoningEffort = "xhigh"
    @AppStorage("plan_mode_backend") private var planModeBackend = "codex"
    @AppStorage("claude_path") private var claudePath = ""
    @AppStorage("claude_model") private var claudeModel = "sonnet"
    @AppStorage("claude_allowed_tools") private var claudeAllowedTools =
        "Read,Edit,Bash,Write,Search"
    @AppStorage("swarm_orchestrator") private var swarmOrchestrator = "openai"
    @AppStorage("swarm_worker_backend") private var swarmWorkerBackend = "codex"
    @AppStorage("swarm_auto_post_code_pipeline") private var swarmAutoPostCodePipeline = true
    @AppStorage("swarm_max_post_code_retries") private var swarmMaxPostCodeRetries = 10
    @AppStorage("swarm_max_review_loops") private var swarmMaxReviewLoops = 2
    @AppStorage("swarm_enabled_roles") private var swarmEnabledRoles =
        "planner,coder,debugger,reviewer,testWriter"
    @AppStorage("global_yolo") private var globalYolo = false
    @AppStorage("code_review_partitions") private var codeReviewPartitions = 3
    @AppStorage("code_review_analysis_only") private var codeReviewAnalysisOnly = false
    @AppStorage("code_review_max_rounds") private var codeReviewMaxRounds = 3
    @AppStorage("code_review_analysis_backend") private var codeReviewAnalysisBackend = "codex"
    @AppStorage("code_review_execution_backend") private var codeReviewExecutionBackend = "codex"
    @AppStorage("appearance") private var appearance = "system"
    @AppStorage("minimax_api_key") private var minimaxApiKey = ""
    @AppStorage("minimax_model") private var minimaxModel = "MiniMax-M2.5"
    @AppStorage("openrouter_api_key") private var openrouterApiKey = ""
    @AppStorage("openrouter_model") private var openrouterModel = "anthropic/claude-sonnet-4-6"
    @AppStorage("gemini_cli_path") private var geminiCliPath = ""
    @AppStorage("gemini_model_override") private var geminiModelOverride = ""

    private var colorScheme: ColorScheme? {
        switch appearance {
        case "light": return .light
        case "dark": return .dark
        default: return nil
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .preferredColorScheme(colorScheme)
                .environmentObject(providerRegistry)
                .environmentObject(chatStore)
                .environmentObject(workspaceStore)
                .environmentObject(projectContextStore)
                .environmentObject(openFilesStore)
                .environmentObject(taskActivityStore)
                .environmentObject(todoStore)
                .environmentObject(swarmProgressStore)
                .environmentObject(codexState)
                .environmentObject(executionController)
                .environmentObject(providerUsageStore)
                .environmentObject(flowDiagnosticsStore)
                .environmentObject(changedFilesStore)
                .environmentObject(accountUsageDashboardStore)
                .onAppear {
                    projectContextStore.ensureWorkspaceContexts(workspaceStore.workspaces)
                    chatStore.migrateLegacyContextsIfNeeded(
                        contextStore: projectContextStore, workspaceStore: workspaceStore)
                    registerProviders()
                    configureWindow()
                }
        }
        MenuBarExtra("Codigo • Usage", systemImage: "chart.bar.fill") {
            UsageMenuBarView()
                .environmentObject(accountUsageDashboardStore)
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }
    }

    private func configureWindow() {
        let candidates = NSApplication.shared.windows.filter { $0.canBecomeMain }
        for window in candidates {
            window.minSize = NSSize(width: 1000, height: 600)
            window.backgroundColor = DesignSystem.AppKit.windowBackground
            AppDelegate.applyMainWindowStyle(window)
        }
    }

    private func registerProviders() {
        if providerRegistry.provider(for: "openai-api") == nil {
            let effort = OpenAIAPIProvider.isReasoningModel(model) ? "medium" : nil
            providerRegistry.register(
                ProviderFactory.openAIAPIProvider(
                    config: providerFactoryConfig(), reasoningEffort: effort))
        }
        if providerRegistry.provider(for: "anthropic-api") == nil {
            providerRegistry.register(
                ProviderFactory.anthropicAPIProvider(config: providerFactoryConfig()))
        }
        if providerRegistry.provider(for: "google-api") == nil {
            providerRegistry.register(
                ProviderFactory.googleAPIProvider(config: providerFactoryConfig()))
        }
        if providerRegistry.provider(for: "codex-cli") == nil {
            providerRegistry.register(
                ProviderFactory.codexProvider(
                    config: providerFactoryConfig(), executionController: executionController))
        }
        if providerRegistry.provider(for: "claude-cli") == nil {
            providerRegistry.register(
                ProviderFactory.claudeProvider(
                    config: providerFactoryConfig(), executionController: executionController))
        }
        if providerRegistry.provider(for: "gemini-cli") == nil {
            providerRegistry.register(
                ProviderFactory.geminiProvider(
                    config: providerFactoryConfig(), executionController: executionController))
        }
        registerMiniMax()
        registerOpenRouter()
        registerPlanProvider()
        registerSwarmProvider()
        registerMultiSwarmReviewProvider()
    }

    private func registerMiniMax() {
        providerRegistry.unregister(id: "minimax-api")
        providerRegistry.register(
            ProviderFactory.miniMaxAPIProvider(config: providerFactoryConfig()))
    }

    private func registerOpenRouter() {
        providerRegistry.unregister(id: "openrouter-api")
        providerRegistry.register(
            ProviderFactory.openRouterAPIProvider(config: providerFactoryConfig()))
    }

    private func registerPlanProvider() {
        let codex = providerRegistry.provider(for: "codex-cli") as? CodexCLIProvider
        let claude = providerRegistry.provider(for: "claude-cli") as? ClaudeCLIProvider
        guard codex != nil || claude != nil else { return }
        providerRegistry.unregister(id: "plan-mode")
        providerRegistry.register(
            ProviderFactory.planProvider(
                config: providerFactoryConfig(), codex: codex, claude: claude,
                executionController: executionController))
    }

    private func registerMultiSwarmReviewProvider() {
        guard let codex = providerRegistry.provider(for: "codex-cli") as? CodexCLIProvider else {
            return
        }
        let claude = providerRegistry.provider(for: "claude-cli") as? ClaudeCLIProvider
        let provider = ProviderFactory.codeReviewProvider(
            config: providerFactoryConfig(), codex: codex, claude: claude)
        providerRegistry.unregister(id: "multi-swarm-review")
        providerRegistry.register(provider)
    }

    private func registerSwarmProvider() {
        providerRegistry.unregister(id: "agent-swarm")
        if let swarm = ProviderFactory.swarmProvider(
            config: providerFactoryConfig(),
            executionController: executionController)
        {
            providerRegistry.register(swarm)
        }
    }

    private func providerFactoryConfig() -> ProviderFactoryConfig {
        let effectiveSandbox =
            codexSandbox.isEmpty
            ? (CodexConfigLoader.load().sandboxMode ?? "workspace-write") : codexSandbox
        let tools = claudeAllowedTools.components(separatedBy: ",").map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines)
        }.filter { !$0.isEmpty }
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
            codexPath: codexPath,
            codexSandbox: effectiveSandbox,
            codexSessionFullAccess: false,
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
            codeReviewExecutionBackend: codeReviewExecutionBackend,
            claudePath: claudePath,
            claudeModel: claudeModel,
            claudeAllowedTools: tools,
            geminiCliPath: geminiCliPath,
            geminiModelOverride: geminiModelOverride
        )
    }
}
