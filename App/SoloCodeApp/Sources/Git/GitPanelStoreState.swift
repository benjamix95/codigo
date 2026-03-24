import CoderEngine
import Foundation

// MARK: - GitRepoState

/// Core repository state: branch, files, log, refresh status.
struct GitRepoState {
    var gitRoot: String?
    var currentBranch: String = "-"
    var branches: [GitBranch] = []
    var status: GitStatusSummary?
    var changedFiles: [GitChangedFile] = []
    var commitLog: [GitLogEntry] = []
    var isRefreshing: Bool = false
    var isBusy: Bool = false
    var error: String?
    var successMessage: String?
}

// MARK: - GitCommitFormState

/// Commit form input state.
struct GitCommitFormState {
    var commitMessage: String = ""
    var includeUnstaged: Bool = false
    var nextStep: GitCommitNextStep = .commit
}

// MARK: - GitBranchFormState

/// Branch creation and search form state.
struct GitBranchFormState {
    var showCreateBranch: Bool = false
    var newBranchName: String = ""
    var branchSearch: String = ""
}

// MARK: - GitRemoteState

/// Remote-related state: stash, remote branches, ahead/behind.
struct GitRemoteState {
    var stashEntries: [GitStashEntry] = []
    var remoteBranches: [GitBranch] = []
    var aheadCount: Int = 0
    var behindCount: Int = 0
    var showDeleteBranchConfirm: Bool = false
    var branchToDelete: String?
    var stashMessage: String = ""
}
