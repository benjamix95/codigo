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
    @Environment(\.conversationBootstrapIfNeeded) var conversationBootstrapIfNeeded

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

    // MARK: - Messages Snapshot (breaks chatStore dependency in body)

    /// Cached conversation snapshot for the messages list. Updated only
    /// when messages actually change (count, content, streaming state),
    /// not on every `chatStore.objectWillChange`. This breaks the direct
    /// dependency chain that caused ~24 idle re-renders at startup.
    @State var messagesConversationSnapshot: Conversation?

    /// Pre-computed trace events per assistant message. Updated alongside
    /// the conversation snapshot to avoid accessing toolTraceStore in the
    /// body evaluation path (which would register SwiftUI dependencies).
    @State var snapshotTraceEvents: [UUID: [ToolTraceEvent]] = [:]

    /// Whether a task is currently active for the snapshot conversation.
    /// Cached to avoid reading chatStore/pipelineIntegrationService in body.
    @State var snapshotIsLoading: Bool = false
    /// Ultimo istante in cui la chat era sicuramente in stato busy.
    /// Serve a proteggere lo snapshot da svuotamenti transienti subito dopo fine stream.
    @State var snapshotLastBusyAt: Date?

    /// Include fase plan "building" per chrome (task bar / swarm) senza leggere `planState` nel body di rootLayout.
    @State var snapshotChromeLoading: Bool = false

    /// Copia throttle di step/cards swarm per evitare letture dirette da store nel `rootLayout`.
    @State var snapshotRootLayoutSwarmSteps: [SwarmStep] = []
    @State var snapshotRootLayoutSwarmCards: [SwarmLiveCardState] = []

    /// Timestamp of last trace events refresh. Used to throttle trace
    /// snapshot updates to max 4/sec during streaming.
    @State var lastTraceRefreshTime: CFAbsoluteTime = 0

    /// Snapshot of the active streaming assistant turn state. These values
    /// are refreshed in a throttled way so the chat body does not need to
    /// query TaskActivityStore directly during every render pass.
    @State var snapshotActiveAssistantMessageId: UUID?
    @State var snapshotStreamingStatusText: String = ""
    @State var snapshotStreamingDetailText: String?
    @State var snapshotInlineActivities: [TaskActivity] = []
    @State var snapshotSupervisorActivities: [TaskActivity] = []
    @State var snapshotLiveSubagentCards: [SwarmLiveCardState] = []
    @State var messagesSnapshotRefreshTask: Task<Void, Never>?
    @State var liveActivitySnapshotRefreshTask: Task<Void, Never>?
    @State var composerRetainedTodoItems: [TodoItem] = []
    @State var composerTodoLastNonEmptySnapshotAt: CFAbsoluteTime = 0
    @State var composerTodoGraceTask: Task<Void, Never>?
    @State var composerTodoRetentionConversationId: UUID?
    /// Per-conversation: evita che `hide_reset` sulla conv B azzeri l’expand scelto dall’utente sulla conv A.
    @State var composerTodoOverlayExpandedByConversation: [UUID: Bool] = [:]
    @State var composerTodoLastAutoExpandedSignatureByConversation: [UUID: String] = [:]
    /// Firma todo per cui l’utente ha chiuso manualmente l’overlay (tap header); stesso formato di `composerTodoAutoExpandSignature`.
    @State var composerTodoOverlayUserDismissedSignatureByConversation: [UUID: String] = [:]

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

    internal var composerTodoOverlayExpanded: Bool {
        get {
            guard let cid = conversationId else { return false }
            return composerTodoOverlayExpandedByConversation[cid] ?? false
        }
        nonmutating set {
            guard let cid = conversationId else { return }
            var copy = composerTodoOverlayExpandedByConversation
            if newValue {
                copy[cid] = true
            } else {
                copy.removeValue(forKey: cid)
            }
            composerTodoOverlayExpandedByConversation = copy
        }
    }

    internal var composerTodoLastAutoExpandedSignature: String {
        get {
            guard let cid = conversationId else { return "" }
            return composerTodoLastAutoExpandedSignatureByConversation[cid] ?? ""
        }
        nonmutating set {
            guard let cid = conversationId else { return }
            var copy = composerTodoLastAutoExpandedSignatureByConversation
            if newValue.isEmpty {
                copy.removeValue(forKey: cid)
            } else {
                copy[cid] = newValue
            }
            composerTodoLastAutoExpandedSignatureByConversation = copy
        }
    }

    internal var composerTodoOverlayExpandedBinding: Binding<Bool> {
        Binding(
            get: { composerTodoOverlayExpanded },
            set: { composerTodoOverlayExpanded = $0 }
        )
    }

    internal func setComposerTodoOverlayUserDismissedForSelection(signature: String) {
        guard let cid = conversationId else { return }
        var copy = composerTodoOverlayUserDismissedSignatureByConversation
        copy[cid] = signature
        composerTodoOverlayUserDismissedSignatureByConversation = copy
    }

    internal func clearComposerTodoOverlayUserDismissedForSelection() {
        guard let cid = conversationId else { return }
        var copy = composerTodoOverlayUserDismissedSignatureByConversation
        copy.removeValue(forKey: cid)
        composerTodoOverlayUserDismissedSignatureByConversation = copy
    }

    var isLoadingForCurrentConversation: Bool {
        chatStore.isTaskActive(for: conversationId)
            || pipelineIntegrationService.isRunning(for: conversationId)
            || (planFlowPhase == .building && activeBuildPlanConversationId == conversationId)
    }
}
