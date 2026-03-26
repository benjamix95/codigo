import CoderEngine
import Foundation

// MARK: - ReviewNavigationState

/// Tab selection and finding navigation state.
struct ReviewNavigationState {
    var selectedTab: CodeReviewTab = .findings
    var selectedFindingId: String?
    var selectedHistoricalFindingId: String?
    /// Full-panel workspace per finding verificato (bug/security).
    var immersiveFindingWorkspaceId: String?
    var sessionBrowserExpanded: Bool = false
}

// MARK: - ReviewRuntimeState

/// Execution lifecycle state for the review run.
struct ReviewRuntimeState {
    var isRunning: Bool = false
    var runStartedAt: Date?
    var frozenTimerText: String?
    var lastError: String?
    /// Durante `apply_patch`: build, test mirati, regression, suite completa Xcode.
    var applyingPatchFindingId: String?
    /// Inizio fase apply (per timer nel footer immersivo).
    var applyPatchPhaseStartedAt: Date?
}

// MARK: - ReviewPanelTranscriptState

/// In-memory transcript mirror for the Rust panel runtime reducer (stream / activity).
/// Not shown in UI; review chat was removed from the panel.
struct ReviewPanelTranscriptState {
    var messages: [ReviewPanelMessage] = []
    var isProcessing: Bool = false
    var startedAt: Date?
}

// MARK: - ReviewGitState

/// Git context loaded for scope selection.
struct ReviewGitState {
    var gitBranches: [GitBranch] = []
    var gitRemoteBranches: [GitBranch] = []
    var gitCommitLog: [GitLogEntry] = []
    var currentGitBranch: String = ""
    var isLoadingGit: Bool = false
}

// MARK: - ReviewScopeState

/// User-selected review scope and mode options.
struct ReviewScopeState {
    var selectedBranch: GitBranch?
    var selectedCommits: Set<String> = []
    var scopeTarget: ReviewScopeTarget = .uncommitted
    var againstCommitRef: String = ""
    var selectedModes: Set<CodeReviewPanelMode> = [.standard, .bugFinder, .securityAudit]
    var selectedProviderOverrideId: String?
}

// MARK: - ReviewHistoryState

/// Historical findings session tracking and filters.
struct ReviewHistoryState {
    var panelSessionId: String?
    var historyRecords: [HistoricalFindingRecord] = []
    var isHistoryLoading: Bool = false
    var historyLoadError: String?
    var historyStatusFilter: ReviewFindingHistoryStatusFilter = .resumeQueue
    var historyDomainFilter: ReviewFindingHistoryDomainFilter = .all
    var historySeverityFilter: ReviewFindingHistorySeverityFilter = .all
}
