import Foundation

extension UsageFooterView {
    var activeWorktreeSession: WorktreeSession? {
        worktreeSessionStore.session(for: selectedConversationId)
    }

    var isCurrentlyInWorktree: Bool {
        worktreeSessionStore.isInWorktree(
            conversationId: selectedConversationId,
            currentPath: effectiveContext.primaryPath
        )
    }

    var worktreeToggleTitle: String {
        isCurrentlyInWorktree ? "Passa a Local" : "Passa al worktree"
    }

    var worktreeToggleHelpText: String {
        if wt.isWorktreeActionInFlight {
            return "Operazione worktree in corso..."
        }
        if isCurrentlyInWorktree {
            return "Torna al progetto locale e opzionalmente avvia auto-merge"
        }
        return "Crea o apri il worktree associato a questa conversazione"
    }

    var isWorktreeToggleDisabled: Bool {
        if selectedConversationId == nil { return true }
        guard let root = gitPanelStore.gitRoot else { return true }
        return root.isEmpty
    }

    var availableBranchNames: [String] {
        wt.availableLocalBranches.map(\.name)
    }

    var worktreeSheetIsLoading: Bool {
        if case .loading = wt.worktreeSheetLoadState {
            return true
        }
        return false
    }

    var isWorktreeSheetReady: Bool {
        if case .ready = wt.worktreeSheetLoadState {
            return true
        }
        return false
    }

    var isWorktreeSheetSubmissionDisabled: Bool {
        wt.isWorktreeActionInFlight
            || worktreeSheetIsLoading
            || !isWorktreeSheetReady
            || wt.worktreeBranchDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || wt.worktreeBaseBranchDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || wt.worktreeMergeTargetDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var worktreeFlowCoordinator: WorktreeFlowCoordinator {
        WorktreeFlowCoordinator()
    }

    func clearWorktreeFeedback() {
        wt.worktreeStatusMessage = nil
        wt.worktreeErrorMessage = nil
    }

    func resetWorktreeSheetDrafts() {
        wt.availableLocalBranches = []
        wt.pendingWorktreeLocalRoot = nil
        wt.worktreeBranchDraft = ""
        wt.worktreeBaseBranchDraft = ""
        wt.worktreeMergeTargetDraft = ""
        wt.worktreeAutoMergeOnReturn = true
        wt.worktreeDeleteBranchAfterMerge = false
        wt.worktreeSheetLoadState = .idle
    }

    func applyWorktreeSheetBootstrap(_ bootstrap: WorktreeSheetBootstrap) {
        wt.pendingWorktreeLocalRoot = bootstrap.localRootPath
        wt.availableLocalBranches = bootstrap.localBranches
        wt.worktreeBaseBranchDraft = bootstrap.suggestedBaseBranch
        wt.worktreeMergeTargetDraft = bootstrap.suggestedMergeTargetBranch
        wt.worktreeBranchDraft = bootstrap.suggestedWorktreeBranch
        wt.worktreeAutoMergeOnReturn = true
        wt.worktreeDeleteBranchAfterMerge = false
        wt.worktreeSheetLoadState = .ready
    }

    func cancelWorktreeSheetPreparation(resetSheetState: Bool) {
        wt.worktreeSheetTask?.cancel()
        wt.worktreeSheetTask = nil
        if resetSheetState {
            resetWorktreeSheetDrafts()
        } else if worktreeSheetIsLoading {
            wt.worktreeSheetLoadState = .idle
        }
    }

    func resolvedGitRoot(from path: String?) -> String? {
        if let cached = gitPanelStore.gitRoot, !cached.isEmpty {
            return cached
        }
        guard let path, !path.isEmpty else { return nil }
        return try? GitService().resolveGitRoot(from: path)
    }

    func defaultWorktreeBranchName(baseBranch: String) -> String {
        makeDefaultWorktreeBranchName(baseBranch: baseBranch)
    }

    func suggestedWorktreePath(localRoot: String, worktreeBranch: String) -> String {
        let rootURL = URL(fileURLWithPath: localRoot).standardizedFileURL
        let parentURL = rootURL.deletingLastPathComponent()
        let repoName = rootURL.lastPathComponent
        let branchSlug = sanitizeBranchComponent(worktreeBranch)
        let dir = "\(repoName)-worktrees"
        return parentURL
            .appendingPathComponent(dir, isDirectory: true)
            .appendingPathComponent(branchSlug, isDirectory: true)
            .path(percentEncoded: false)
    }

    func sanitizeBranchComponent(_ raw: String) -> String {
        sanitizeWorktreeBranchComponent(raw)
    }
}
