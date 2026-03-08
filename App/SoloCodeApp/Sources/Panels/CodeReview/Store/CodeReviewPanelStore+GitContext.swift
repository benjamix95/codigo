import CoderEngine
import Foundation

// MARK: - Git Context Loading

extension CodeReviewPanelStore {

    /// Load branches, commits, and current branch from git.
    func refreshGitContext() async {
        guard !isLoadingGit else { return }
        isLoadingGit = true
        defer { isLoadingGit = false }

        let git = GitService()
        guard let rootPath = workspaceStore.activeWorkspacePaths.first?.path else {
            return
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

            await MainActor.run {
                self.gitBranches = branches
                self.gitRemoteBranches = remotes
                self.gitCommitLog = commits
                self.currentGitBranch = current
            }
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
            await MainActor.run {
                self.gitCommitLog = commits
            }
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
