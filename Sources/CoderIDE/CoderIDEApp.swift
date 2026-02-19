import SwiftUI
import AppKit
import CoderEngine

@main
struct CodigoApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var providerRegistry = ProviderRegistry()
    @StateObject private var chatStore = ChatStore()
    @StateObject private var workspaceStore = WorkspaceStore()
    @StateObject private var openFilesStore = OpenFilesStore()
    @StateObject private var taskActivityStore = TaskActivityStore()
    @StateObject private var todoStore = TodoStore()
    @StateObject private var swarmProgressStore = SwarmProgressStore()
    @StateObject private var codexState = CodexStateStore()
    @State private var showSettings = false
    @AppStorage("openai_api_key") private var apiKey = ""
    @AppStorage("openai_model") private var model = "gpt-4o-mini"
    @AppStorage("codex_path") private var codexPath = ""
    @AppStorage("codex_sandbox") private var codexSandbox = ""
    @AppStorage("codex_model_override") private var codexModelOverride = ""
    @AppStorage("codex_reasoning_effort") private var codexReasoningEffort = "xhigh"
    @AppStorage("swarm_orchestrator") private var swarmOrchestrator = "openai"
    @AppStorage("swarm_auto_post_code_pipeline") private var swarmAutoPostCodePipeline = true
    @AppStorage("swarm_max_post_code_retries") private var swarmMaxPostCodeRetries = 10
    @AppStorage("code_review_yolo") private var codeReviewYolo = false
    @AppStorage("code_review_partitions") private var codeReviewPartitions = 3
    @AppStorage("code_review_analysis_only") private var codeReviewAnalysisOnly = false
    @AppStorage("appearance") private var appearance = "system"

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
                .environmentObject(openFilesStore)
                .environmentObject(taskActivityStore)
                .environmentObject(todoStore)
                .environmentObject(swarmProgressStore)
                .environmentObject(codexState)
                .onAppear {
                    registerProviders()
                    configureWindow()
                }
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            showSettings = true
                        } label: {
                            Image(systemName: "gearshape")
                        }
                    }
                }
                .sheet(isPresented: $showSettings) {
                    SettingsView()
                        .environmentObject(providerRegistry)
                }
        }
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandGroup(after: .appSettings) {
                Button("Impostazioni Codigo...") {
                    showSettings = true
                }
                .keyboardShortcut(",", modifiers: .command)
            }
        }
    }

    private func configureWindow() {
        guard let window = NSApplication.shared.windows.first else { return }
        window.minSize = NSSize(width: 1000, height: 600)
    }

    private func registerProviders() {
        if providerRegistry.provider(for: "openai-api") == nil {
            providerRegistry.register(OpenAIAPIProvider(apiKey: apiKey, model: model))
        }
        if providerRegistry.provider(for: "codex-cli") == nil {
            let effective = codexSandbox.isEmpty ? CodexConfigLoader.load().sandboxMode ?? "workspace-write" : codexSandbox
            let sandbox: CodexSandboxMode = CodexSandboxMode(rawValue: effective) ?? .workspaceWrite
            providerRegistry.register(CodexCLIProvider(
                codexPath: codexPath.isEmpty ? nil : codexPath,
                sandboxMode: sandbox,
                modelOverride: codexModelOverride.isEmpty ? nil : codexModelOverride,
                modelReasoningEffort: codexReasoningEffort.isEmpty ? nil : codexReasoningEffort
            ))
        }
        if providerRegistry.provider(for: "claude-cli") == nil {
            providerRegistry.register(ClaudeCLIProvider())
        }
        registerPlanProvider()
        registerSwarmProvider()
        registerMultiSwarmReviewProvider()
    }

    private func registerPlanProvider() {
        let codex = providerRegistry.provider(for: "codex-cli") as? CodexCLIProvider
        let claude = providerRegistry.provider(for: "claude-cli") as? ClaudeCLIProvider
        guard codex != nil || claude != nil else { return }
        let planProvider = PlanModeProvider(codexProvider: codex, claudeProvider: claude)
        providerRegistry.unregister(id: "plan-mode")
        providerRegistry.register(planProvider)
    }

    private func registerMultiSwarmReviewProvider() {
        guard let codex = providerRegistry.provider(for: "codex-cli") as? CodexCLIProvider else { return }
        let effective = codexSandbox.isEmpty ? CodexConfigLoader.load().sandboxMode ?? "workspace-write" : codexSandbox
        let sandbox: CodexSandboxMode = CodexSandboxMode(rawValue: effective) ?? .workspaceWrite
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

    private func registerSwarmProvider() {
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
}
