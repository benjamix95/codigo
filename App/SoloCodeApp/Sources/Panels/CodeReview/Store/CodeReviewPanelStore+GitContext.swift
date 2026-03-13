import CoderEngine
import Foundation

@MainActor
struct ReviewPanelLaunchRequest: Equatable {
    let conversationId: UUID?
    let scope: ReviewScopeTarget
    let modes: Set<CodeReviewPanelMode>
    let promptOverride: String
    let invocationLabel: String
}

@MainActor
final class ReviewPanelLaunchRequestStore {
    static let shared = ReviewPanelLaunchRequestStore()

    private var pendingByConversationKey: [String: ReviewPanelLaunchRequest] = [:]

    private init() {}

    func enqueue(_ request: ReviewPanelLaunchRequest) {
        pendingByConversationKey[conversationKey(for: request.conversationId)] = request
    }

    func consume(conversationId: UUID?) -> ReviewPanelLaunchRequest? {
        pendingByConversationKey.removeValue(forKey: conversationKey(for: conversationId))
    }

    private func conversationKey(for conversationId: UUID?) -> String {
        conversationId?.uuidString.lowercased() ?? "workspace-review-panel"
    }
}

// MARK: - Git Context Loading

extension CodeReviewPanelStore {
    var historyAutomaticRefreshKey: String {
        let workspaceKey = historyWorkspaceId ?? "no-workspace"
        let sessionKey = selectedSessionId ?? "no-session"
        return [workspaceKey, sessionKey].joined(separator: "|")
    }

    func scheduleGitLoadingState(_ isLoading: Bool) {
        scheduleDeferredMutation { store in
            guard store.isLoadingGit != isLoading else { return }
            store.isLoadingGit = isLoading
        }
    }

    func scheduleGitContextSnapshot(
        branches: [GitBranch],
        remotes: [GitBranch],
        commits: [GitLogEntry],
        currentBranch: String
    ) {
        scheduleDeferredMutation { store in
            store.gitBranches = branches
            store.gitRemoteBranches = remotes
            store.gitCommitLog = commits
            store.currentGitBranch = currentBranch
        }
    }

    func scheduleCommitLogSnapshot(_ commits: [GitLogEntry]) {
        scheduleDeferredMutation { store in
            store.gitCommitLog = commits
        }
    }

    func scheduleHistoryLoadingState(
        _ isLoading: Bool,
        refreshKey: String
    ) {
        scheduleDeferredMutation { store in
            guard store.historyAutomaticRefreshKey == refreshKey else { return }
            guard store.isHistoryLoading != isLoading else { return }
            store.isHistoryLoading = isLoading
        }
    }

    func scheduleHistoricalFindingsSnapshot(
        _ records: [HistoricalFindingRecord],
        error: String?,
        refreshKey: String
    ) {
        scheduleDeferredMutation { store in
            guard store.historyAutomaticRefreshKey == refreshKey else { return }
            store.historyRecords = records
            store.historyLoadError = error
        }
    }

    /// Load branches, commits, and current branch from git.
    func refreshGitContext() async {
        let git = GitService()
        guard let rootPath = workspaceStore.activeWorkspacePaths.first?.path else {
            return
        }
        guard !isGitContextRefreshInFlight else { return }
        isGitContextRefreshInFlight = true
        scheduleGitLoadingState(true)
        defer {
            isGitContextRefreshInFlight = false
            scheduleGitLoadingState(false)
        }

        do {
            let gitRoot = try git.resolveGitRoot(from: rootPath)

            async let branchesResult = Task.detached {
                try git.listLocalBranches(gitRoot: gitRoot)
            }.value

            async let remotesResult = Task.detached {
                try git.listRemoteBranches(gitRoot: gitRoot)
            }.value

            async let commitsResult = Task.detached {
                try git.commitHistory(gitRoot: gitRoot, limit: 50)
            }.value

            async let currentResult = Task.detached {
                try git.currentBranch(gitRoot: gitRoot)
            }.value

            let branches = (try? await branchesResult) ?? []
            let remotes = (try? await remotesResult) ?? []
            let commits = (try? await commitsResult) ?? []
            let current = (try? await currentResult) ?? ""

            scheduleGitContextSnapshot(
                branches: branches,
                remotes: remotes,
                commits: commits,
                currentBranch: current
            )
        } catch {
            // Silently fail - git context is optional
        }
    }

    /// Load more commits beyond the initial limit.
    func loadMoreCommits(limit: Int = 100) async {
        let git = GitService()
        guard let rootPath = workspaceStore.activeWorkspacePaths.first?.path else {
            return
        }
        do {
            let gitRoot = try git.resolveGitRoot(from: rootPath)
            let commits = try git.commitHistory(gitRoot: gitRoot, limit: limit)
            scheduleCommitLogSnapshot(commits)
        } catch {
            // Silently fail
        }
    }

    /// Select a branch for review.
    func selectBranch(_ branch: GitBranch) {
        selectedBranch = branch
        scopeTarget = .branch(branch.name)
        selectedCommits.removeAll()
    }

    /// Clear branch selection and go back to default scope.
    func clearBranchSelection() {
        selectedBranch = nil
        scopeTarget = .uncommitted
    }

    /// Toggle commit selection for multi-commit review.
    func toggleCommitSelection(_ sha: String) {
        if selectedCommits.contains(sha) {
            selectedCommits.remove(sha)
        } else {
            selectedCommits.insert(sha)
        }
        updateScopeFromCommitSelection()
    }

    /// Select all commits in a range.
    func selectCommitRange(from: Int, to: Int) {
        let range = min(from, to)...max(from, to)
        for i in range where i < gitCommitLog.count {
            selectedCommits.insert(gitCommitLog[i].sha)
        }
        updateScopeFromCommitSelection()
    }

    /// Clear commit selection.
    func clearCommitSelection() {
        selectedCommits.removeAll()
        scopeTarget = .uncommitted
    }

    /// Check if a commit SHA is selected.
    func isCommitSelected(_ sha: String) -> Bool {
        selectedCommits.contains(sha)
    }

    // MARK: - Private

    private func updateScopeFromCommitSelection() {
        if selectedCommits.isEmpty {
            scopeTarget = .uncommitted
        } else {
            let orderedShas = gitCommitLog
                .filter { selectedCommits.contains($0.sha) }
                .map(\.sha)
            scopeTarget = .commits(orderedShas)
        }
        selectedBranch = nil
    }
}
