import CoderEngine
import Combine
import Foundation
import SwiftUI

/// Central store for the independent Code Review Panel.
/// All panel state is owned here; views observe this store directly.
@MainActor
final class CodeReviewPanelStore: ObservableObject {

    // MARK: - Dependencies

    let taskActivityStore: TaskActivityStore
    let providerRegistry: ProviderRegistry
    let executionController: ExecutionController?
    let workspaceStore: WorkspaceStore
    let openFilesStore: OpenFilesStore
    let todoStore: TodoStore?
    let conversationId: UUID?
    let chatSessionStore: ReviewPanelChatSessionStore
    let providerFactoryConfigBuilder: () -> ProviderFactoryConfig

    // MARK: - Coordinator

    lazy var coordinator = ReviewPanelCoordinator()

    // MARK: - Tab & Navigation

    @Published var selectedTab: CodeReviewTab = .findings
    @Published var selectedFindingId: String?
    @Published var selectedHistoricalFindingId: String?
    @Published var sessionBrowserExpanded: Bool = false

    // MARK: - Execution State

    @Published var isRunning: Bool = false
    @Published var runStartedAt: Date?
    @Published var frozenTimerText: String?
    @Published var lastError: String?

    // MARK: - Chat State

    @Published var chatMessages: [ReviewPanelMessage] = []
    @Published var isChatProcessing: Bool = false
    @Published var chatStartedAt: Date?
    @Published var chatThreads: [ReviewPanelChatThreadState] = []
    @Published var activeChatThreadId: String?

    /// Maps activity message ID → response message ID for split bubbles.
    var responseMessageIds: [UUID: UUID] = [:]
    var finishedReviewRunActivityIds: Set<UUID> = []
    var isGitContextRefreshInFlight = false
    var isHistoryRefreshInFlight = false

    // MARK: - Git Context

    @Published var gitBranches: [GitBranch] = []
    @Published var gitRemoteBranches: [GitBranch] = []
    @Published var gitCommitLog: [GitLogEntry] = []
    @Published var currentGitBranch: String = ""
    @Published var isLoadingGit: Bool = false

    // MARK: - Scope & Selection

    @Published var selectedBranch: GitBranch?
    @Published var selectedCommits: Set<String> = []
    @Published var scopeTarget: ReviewScopeTarget = .uncommitted
    @Published var againstCommitRef: String = ""
    @Published var selectedModes: Set<CodeReviewPanelMode> = [.standard, .bugFinder, .securityAudit]
    @Published var selectedProviderOverrideId: String?

    // MARK: - Settings

    @Published var settings: ReviewPanelSettings

    // MARK: - Session Tracking

    @Published var panelSessionId: String?
    @Published var historyRecords: [HistoricalFindingRecord] = []
    @Published var isHistoryLoading: Bool = false
    @Published var historyLoadError: String?
    @Published var historyStatusFilter: ReviewFindingHistoryStatusFilter = .resumeQueue
    @Published var historyDomainFilter: ReviewFindingHistoryDomainFilter = .all
    @Published var historySeverityFilter: ReviewFindingHistorySeverityFilter = .all

    // MARK: - Session Persistence

    private var chatStateCancellable: AnyCancellable?
    private var taskActivityStoreCancellable: AnyCancellable?
    var pendingChatConversationApplyTask: Task<Void, Never>?

    // MARK: - Accent Color

    let accent = DesignSystem.Colors.reviewColor

    // MARK: - Init

    init(
        taskActivityStore: TaskActivityStore,
        providerRegistry: ProviderRegistry,
        executionController: ExecutionController?,
        workspaceStore: WorkspaceStore,
        openFilesStore: OpenFilesStore,
        todoStore: TodoStore? = nil,
        conversationId: UUID?,
        chatSessionStore: ReviewPanelChatSessionStore? = nil,
        providerFactoryConfigBuilder: @escaping () -> ProviderFactoryConfig
    ) {
        self.taskActivityStore = taskActivityStore
        self.providerRegistry = providerRegistry
        self.executionController = executionController
        self.workspaceStore = workspaceStore
        self.openFilesStore = openFilesStore
        self.todoStore = todoStore
        self.conversationId = conversationId
        let resolvedChatSessionStore = chatSessionStore ?? ReviewPanelChatSessionStore.shared
        self.chatSessionStore = resolvedChatSessionStore
        self.providerFactoryConfigBuilder = providerFactoryConfigBuilder
        self.settings = ReviewPanelSettingsPersistence.load()

        let initialConversation = resolvedChatSessionStore.conversation(
            for: Self.chatSessionKey(conversationId: conversationId)
        )
        // Apply initial state synchronously (safe during init, no view update in progress).
        chatThreads = initialConversation.threads
        activeChatThreadId = initialConversation.activeThreadId
        let activeState = initialConversation.activeThreadId.flatMap { activeId in
            initialConversation.threads.first(where: { $0.id == activeId })?.sessionState
        } ?? .empty
        chatMessages = activeState.messages
        isChatProcessing = activeState.isProcessing
        chatStartedAt = activeState.startedAt
        if let snapshot = taskActivityStore.codeReviewSnapshot(sessionId: nil, conversationId: conversationId),
           !snapshot.findings.isEmpty || snapshot.isActive {
            self.selectedTab = .findings
        } else if !chatMessages.isEmpty {
            self.selectedTab = .chat
        }
        if let activeChatThreadId,
           !applyPanelIntent("set_active_chat_thread", value: activeChatThreadId),
           !ReviewCoreBridge.isEnabled {
            self.activeChatThreadId = activeChatThreadId
        }

        let sessionKey = Self.chatSessionKey(conversationId: conversationId)
        self.chatStateCancellable = resolvedChatSessionStore.$conversationsByKey
            .map { $0[sessionKey] ?? .empty }
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] conversation in
                guard let self else { return }
                self.handleIncomingChatConversation(conversation)
            }
        self.taskActivityStoreCancellable = taskActivityStore.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.scheduleDeferredMutation { store in
                    store.objectWillChange.send()
                }
            }
    }

    func scheduleDeferredMutation(
        _ mutation: @escaping @MainActor (CodeReviewPanelStore) -> Void
    ) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            mutation(self)
        }
    }

    func schedulePanelSessionBinding(_ sessionId: String?) {
        scheduleDeferredMutation { store in
            guard store.panelSessionId != sessionId else { return }
            if !store.applyPanelIntent("bind_panel_session", value: sessionId) {
                store.panelSessionId = sessionId
            }
        }
    }

    // MARK: - Computed Properties

    var selectedSessionId: String? {
        panelSessionId
            ?? taskActivityStore.selectedCodeReviewSessionId(for: conversationId)
            ?? taskActivityStore.codeReviewSnapshots(for: conversationId).first?.sessionId
    }

    var currentSnapshot: CodeReviewSessionSnapshot? {
        guard let sid = selectedSessionId else { return nil }
        return taskActivityStore.codeReviewSnapshot(
            sessionId: sid,
            conversationId: conversationId
        )
    }

    var currentFindings: [CodeReviewFinding] {
        currentSnapshot?.findings ?? []
    }

    var currentCandidates: [ReviewCandidate] {
        currentSnapshot?.candidates ?? []
    }

    var currentPatches: [ReviewPatchArtifact] {
        currentSnapshot?.patches ?? []
    }

    var currentOutcome: ReviewSessionOutcome {
        currentSnapshot?.outcome ?? .empty
    }

    var currentVerifiedFindingsEnvelope: VerifiedFindingsSessionEnvelope? {
        guard let sessionId = selectedSessionId else { return nil }
        return taskActivityStore.verifiedFindingsEnvelope(
            sessionId: sessionId,
            conversationId: conversationId
        )
    }

    var currentVerifiedFindingsProjection: VerifiedFindingsProjectionSnapshot {
        if let envelope = currentVerifiedFindingsEnvelope {
            return envelope.projectionSnapshot
        }
        return taskActivityStore.verifiedFindingsProjection(for: conversationId)
    }

    var currentEvents: [CodeReviewSessionEvent] {
        currentSnapshot?.events ?? []
    }

    var availableSnapshots: [CodeReviewSessionSnapshot] {
        taskActivityStore.codeReviewSnapshots(for: conversationId)
    }

    // MARK: - Tab Selection

    func selectTab(_ tab: CodeReviewTab) {
        withAnimation(.snappy(duration: 0.15)) {
            if !applyPanelIntent("select_tab", value: tab.rawValue),
               !ReviewCoreBridge.isEnabled {
                selectedTab = tab
            }
        }
    }

    // MARK: - Session Selection

    func setSelectedSession(_ sessionId: String?) {
        if !applyPanelIntent("set_selected_session", value: sessionId),
           !ReviewCoreBridge.isEnabled {
            panelSessionId = sessionId
            selectedFindingId = nil
            selectedHistoricalFindingId = nil
        }
        taskActivityStore.setSelectedCodeReviewSessionId(sessionId, for: conversationId)
    }

    func deleteSession(_ sessionId: String) async {
        await ReviewSessionRegistry.shared.unregister(sessionId: sessionId)
        MCPSharedState.deleteCodeReviewSession(sessionId: sessionId)
        taskActivityStore.deleteCodeReviewSession(
            sessionId: sessionId,
            conversationId: conversationId
        )

        if panelSessionId == sessionId {
            setSelectedSession(availableSnapshots.first?.sessionId)
        } else {
            clearSelectedFinding()
            clearSelectedHistoricalFinding()
        }
    }

    func focusFinding(_ findingId: String) {
        guard currentVisibleFindings.contains(where: { $0.id == findingId }) else { return }
        if !applyPanelIntent("focus_finding", value: findingId),
           !ReviewCoreBridge.isEnabled {
            selectedHistoricalFindingId = nil
            selectedFindingId = findingId
        }
        selectTab(.findings)
    }

    func clearSelectedFinding() {
        if !applyPanelIntent("clear_selected_finding"),
           !ReviewCoreBridge.isEnabled {
            selectedFindingId = nil
        }
    }

    func clearSelectedHistoricalFinding() {
        if !applyPanelIntent("clear_selected_historical_finding"),
           !ReviewCoreBridge.isEnabled {
            selectedHistoricalFindingId = nil
        }
    }

    // MARK: - Workspace Context

    func buildWorkspaceContext() -> WorkspaceContext {
        WorkspaceContext(
            workspacePaths: workspaceStore.activeWorkspacePaths,
            excludedPaths: workspaceStore.activeExcludedPaths,
            openFiles: openFilesStore.openFilesForContext(),
            activeFilePath: openFilesStore.openFilePath,
            activeRootPath: workspaceStore.activeWorkspacePaths.first?.path
        )
    }

    // MARK: - Metrics

    func computeMetrics() -> CodeReviewMetrics {
        let allActivities = taskActivityStore.activities
        let sessionId = selectedSessionId

        let reviewActivities = scopedReviewActivitiesForSession(
            allActivities, sessionId: sessionId
        )

        let cards = taskActivityStore
            .swarmCardStates(for: conversationId)
            .filter {
                isCodeReviewSwarmCard($0)
                    && reviewCardBelongsToSession($0, sessionId: sessionId)
            }

        let active = cards.filter { $0.status == .running }.count

        let workerActivities = sortedReviewWorkerPlanActivitiesForDisplay(
            selectReviewWorkerActivities(from: reviewActivities)
        )

        let hasArtifacts = hasCodeReviewArtifactsCheck(
            cards: cards,
            workerActivities: workerActivities,
            activities: reviewActivities
        )

        guard shouldDisplayCodeReviewMetrics(
            isRunning: isRunning,
            hasReviewArtifacts: hasArtifacts
        ) else {
            return CodeReviewMetrics(
                cards: [], activeCount: 0, workers: [], roundInfo: nil
            )
        }

        let workers: [ReviewWorkerRow] = workerActivities.compactMap { a in
            guard let wid = a.payload["worker_id"],
                  let desc = a.payload["description"],
                  let sev = a.payload["severity"],
                  let fcRaw = a.payload["fileCount"] else { return nil }
            let rawFiles = (a.payload["files_raw"] ?? "")
                .components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            return ReviewWorkerRow(
                id: wid,
                description: desc,
                severity: FindingSeverity(rawValue: sev.lowercased()) ?? .warning,
                fileCount: Int(fcRaw) ?? 0,
                files: rawFiles,
                filesSummary: a.payload["files"] ?? ""
            )
        }

        let round: (String, String)? = hasArtifacts
            ? reviewActivities.reversed().compactMap { a -> (String, String)? in
                guard a.type == "review-fix-round",
                      let r = a.payload["round"],
                      let m = a.payload["maxRounds"] else { return nil }
                return (r, m)
            }.first
            : nil

        return CodeReviewMetrics(
            cards: cards,
            activeCount: active,
            workers: workers,
            roundInfo: round
        )
    }

}
