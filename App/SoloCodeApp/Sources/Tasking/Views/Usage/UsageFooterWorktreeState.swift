import Foundation

// MARK: - Worktree Sheet State Container

struct UsageFooterWorktreeState {
    var showWorktreeSheet = false
    var availableLocalBranches: [GitBranch] = []
    var worktreeBranchDraft = ""
    var worktreeBaseBranchDraft = ""
    var worktreeMergeTargetDraft = ""
    var worktreeAutoMergeOnReturn = true
    var worktreeDeleteBranchAfterMerge = false
    var pendingWorktreeLocalRoot: String?
    var worktreeSheetLoadState: WorktreeSheetLoadState = .idle
    var worktreeStatusMessage: String?
    var worktreeErrorMessage: String?
    var isWorktreeActionInFlight = false
    var worktreeSheetTask: Task<Void, Never>?
    var worktreeActionTask: Task<Void, Never>?
}

// MARK: - Context Estimation State Container

struct UsageFooterContextState {
    var usageRefreshTask: Task<Void, Never>?
    var contextEstimateSnapshot: (tokens: Int, size: Int, pct: Double) = (0, 128_000, 0)
    var contextEstimateWorkItem: DispatchWorkItem?
    var contextEstimateGeneration: Int = 0
    var lastContextEstimateFireDate: Date = .distantPast

    static let estimateQueue = DispatchQueue(
        label: "com.solocode.context-estimate",
        qos: .utility
    )
}
