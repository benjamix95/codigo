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
    let providerFactoryConfigBuilder: () -> ProviderFactoryConfig

    // MARK: - Coordinator

    lazy var coordinator = ReviewPanelCoordinator()

    // MARK: - Grouped State (reduces @Published explosion)

    @Published var navigation = ReviewNavigationState()
    @Published var runtime = ReviewRuntimeState()
    @Published var transcript = ReviewPanelTranscriptState()
    @Published var git = ReviewGitState()
    @Published var scope = ReviewScopeState()
    @Published var history = ReviewHistoryState()

    // MARK: - Backward-compatible accessors – Navigation

    var selectedTab: CodeReviewTab {
        get { navigation.selectedTab }
        set { navigation.selectedTab = newValue }
    }
    var selectedFindingId: String? {
        get { navigation.selectedFindingId }
        set { navigation.selectedFindingId = newValue }
    }
    var selectedHistoricalFindingId: String? {
        get { navigation.selectedHistoricalFindingId }
        set { navigation.selectedHistoricalFindingId = newValue }
    }
    var sessionBrowserExpanded: Bool {
        get { navigation.sessionBrowserExpanded }
        set { navigation.sessionBrowserExpanded = newValue }
    }

    // MARK: - Backward-compatible accessors – Runtime

    var isRunning: Bool {
        get { runtime.isRunning }
        set { runtime.isRunning = newValue }
    }
    var runStartedAt: Date? {
        get { runtime.runStartedAt }
        set { runtime.runStartedAt = newValue }
    }
    var frozenTimerText: String? {
        get { runtime.frozenTimerText }
        set { runtime.frozenTimerText = newValue }
    }
    var lastError: String? {
        get { runtime.lastError }
        set { runtime.lastError = newValue }
    }

    // MARK: - Transcript (Rust reducer mirror only; no chat UI)

    var chatMessages: [ReviewPanelMessage] {
        get { transcript.messages }
        set { transcript.messages = newValue }
    }
    var isChatProcessing: Bool {
        get { transcript.isProcessing }
        set { transcript.isProcessing = newValue }
    }
    var chatStartedAt: Date? {
        get { transcript.startedAt }
        set { transcript.startedAt = newValue }
    }

    /// Maps activity message ID → response message ID for split bubbles.
    var responseMessageIds: [UUID: UUID] = [:]
    var finishedReviewRunActivityIds: Set<UUID> = []
    var isGitContextRefreshInFlight = false
    var isHistoryRefreshInFlight = false

    /// Buffer per coalescing `textDelta` prima del reducer Rust (meno round-trip FFI).
    var reviewPanelStreamDeltaCoalesceBuffers: [UUID: String] = [:]
    var reviewPanelStreamDeltaCoalesceTasks: [UUID: Task<Void, Never>] = [:]

    // MARK: - Backward-compatible accessors – Git

    var gitBranches: [GitBranch] {
        get { git.gitBranches }
        set { git.gitBranches = newValue }
    }
    var gitRemoteBranches: [GitBranch] {
        get { git.gitRemoteBranches }
        set { git.gitRemoteBranches = newValue }
    }
    var gitCommitLog: [GitLogEntry] {
        get { git.gitCommitLog }
        set { git.gitCommitLog = newValue }
    }
    var currentGitBranch: String {
        get { git.currentGitBranch }
        set { git.currentGitBranch = newValue }
    }
    var isLoadingGit: Bool {
        get { git.isLoadingGit }
        set { git.isLoadingGit = newValue }
    }

    // MARK: - Backward-compatible accessors – Scope

    var selectedBranch: GitBranch? {
        get { scope.selectedBranch }
        set { scope.selectedBranch = newValue }
    }
    var selectedCommits: Set<String> {
        get { scope.selectedCommits }
        set { scope.selectedCommits = newValue }
    }
    var scopeTarget: ReviewScopeTarget {
        get { scope.scopeTarget }
        set { scope.scopeTarget = newValue }
    }
    var againstCommitRef: String {
        get { scope.againstCommitRef }
        set { scope.againstCommitRef = newValue }
    }
    var selectedModes: Set<CodeReviewPanelMode> {
        get { scope.selectedModes }
        set { scope.selectedModes = newValue }
    }
    var selectedProviderOverrideId: String? {
        get { scope.selectedProviderOverrideId }
        set { scope.selectedProviderOverrideId = newValue }
    }

    // MARK: - Settings

    @Published var settings: ReviewPanelSettings

    // MARK: - Backward-compatible accessors – History

    var panelSessionId: String? {
        get { history.panelSessionId }
        set { history.panelSessionId = newValue }
    }
    var historyRecords: [HistoricalFindingRecord] {
        get { history.historyRecords }
        set { history.historyRecords = newValue }
    }
    var isHistoryLoading: Bool {
        get { history.isHistoryLoading }
        set { history.isHistoryLoading = newValue }
    }
    var historyLoadError: String? {
        get { history.historyLoadError }
        set { history.historyLoadError = newValue }
    }
    var historyStatusFilter: ReviewFindingHistoryStatusFilter {
        get { history.historyStatusFilter }
        set { history.historyStatusFilter = newValue }
    }
    var historyDomainFilter: ReviewFindingHistoryDomainFilter {
        get { history.historyDomainFilter }
        set { history.historyDomainFilter = newValue }
    }
    var historySeverityFilter: ReviewFindingHistorySeverityFilter {
        get { history.historySeverityFilter }
        set { history.historySeverityFilter = newValue }
    }

    // MARK: - Session Persistence

    private var taskActivityStoreCancellable: AnyCancellable?

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
        providerFactoryConfigBuilder: @escaping () -> ProviderFactoryConfig
    ) {
        self.taskActivityStore = taskActivityStore
        self.providerRegistry = providerRegistry
        self.executionController = executionController
        self.workspaceStore = workspaceStore
        self.openFilesStore = openFilesStore
        self.todoStore = todoStore
        self.conversationId = conversationId
        self.providerFactoryConfigBuilder = providerFactoryConfigBuilder
        self.settings = ReviewPanelSettingsPersistence.load()

        if let snapshot = taskActivityStore.codeReviewSnapshot(sessionId: nil, conversationId: conversationId),
           !snapshot.findings.isEmpty || snapshot.isActive {
            self.selectedTab = .findings
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

    /// Finding aperti con patch già preparata e pronta per Apply (diff non vuoto + verify).
    var openFindingIdsReadyForPatchApply: [String] {
        guard let snapshot = currentSnapshot else { return [] }
        return snapshot.findings
            .filter { $0.status == .open }
            .map(\.id)
            .filter { findingId in
                snapshot.patches.first { $0.findingId == findingId }?.isReadyForUserApply == true
            }
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
