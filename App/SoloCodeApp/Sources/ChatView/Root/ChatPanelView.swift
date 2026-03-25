import AppKit
import CoderEngine
import SwiftUI

struct ChatPanelView: View {

    // MARK: - Environment Objects

    @EnvironmentObject var providerRegistry: ProviderRegistry
    @EnvironmentObject var chatStore: ChatStore
    @EnvironmentObject var workspaceStore: WorkspaceStore
    @EnvironmentObject var projectContextStore: ProjectContextStore
    @EnvironmentObject var openFilesStore: OpenFilesStore
    @EnvironmentObject var editorNavigationDispatchStore: EditorNavigationDispatchStore
    @EnvironmentObject var taskActivityStore: TaskActivityStore
    @EnvironmentObject var toolTraceStore: ToolTraceStore
    @EnvironmentObject var todoStore: TodoStore
    @EnvironmentObject var swarmProgressStore: SwarmProgressStore
    @EnvironmentObject var executionController: ExecutionController
    @EnvironmentObject var providerUsageStore: ProviderUsageStore
    @EnvironmentObject var gitPanelStore: GitPanelStore
    @EnvironmentObject var planHistoryStore: PlanHistoryStore
    @EnvironmentObject var browserTabManager: BrowserTabManager
    @EnvironmentObject var pipelineIntegrationService: PipelineIntegrationService

    // MARK: - Injected (order matches call site)

    @Binding var selectedConversationId: UUID?
    let effectiveContext: EffectiveContext
    let windowChromeLeadingInset: CGFloat
    @Binding var coderMode: CoderMode
    @Binding var showPlanPanel: Bool
    @Binding var showDebugPanel: Bool
    @Binding var showSwarmPanel: Bool
    @Binding var showCodeReviewPanel: Bool
    @Binding var showBrowserPanel: Bool
    @ObservedObject var debugStore: DebugStore

    // MARK: - Settings (DynamicProperty groups — replace 54 @AppStorage)

    var providerSettings = ChatPanelProviderSettings()
    var swarmReviewSettings = ChatPanelSwarmReviewSettings()
    var uiSettings = ChatPanelUISettings()

    // MARK: - State Containers (replace ~35 loose @State)

    @State var streaming = ChatStreamingState()
    @State var scrollState = ChatScrollState()
    @State var toolRuntime = ChatToolRuntimeState()
    @State var conversationRuntime = ChatConversationRuntimeState()

    // MARK: - Existing State Containers

    @State var composerState = ChatPanelComposerViewState()
    @State var panelState = ChatPanelThreadViewState()
    @State var planState = ChatPanelPlanViewState()
    @State var interactionState = ChatPanelInteractionViewState()

    // MARK: - Remaining @State (not grouped)

    @State var codexModels: [CodexModel] = []
    @State var geminiModels: [GeminiModel] = []
    @State var showSwarmHelp = false
    @State var pendingCodeReviewSessionConfigOverride: SessionConfig?

    // MARK: - State Objects

    @StateObject var voiceInputController = VoiceInputController()
    @StateObject var flowCoordinator = ConversationFlowCoordinator()
    @StateObject var networkMonitor = NetworkMonitor.shared

    // MARK: - Constants

    let sequentialStreamingLayoutEnabled = false
    let separateCodexThinkingMessagesEnabled = false
    let codexLinearChatEnabled = true
    let streamThrottleInterval: TimeInterval = 0.020
    let planStreamThrottleInterval: TimeInterval = 0.066
    let taskActivityFlushInterval: TimeInterval = 0.1
    let taskBacklogDiagnosticThreshold = 40
    let checkpointGitStore = ConversationCheckpointGitStore()
    let cliAccountsStore = CLIAccountsStore.shared
    let cliAccountRouter = CLIAccountRouter.shared

    // MARK: - Computed

    var conversationId: UUID? { selectedConversationId }

    var isLoadingForCurrentConversation: Bool {
        chatStore.isTaskActive(for: conversationId)
            || pipelineIntegrationService.isRunning(for: conversationId)
            || (planFlowPhase == .building && activeBuildPlanConversationId == conversationId)
    }
}
