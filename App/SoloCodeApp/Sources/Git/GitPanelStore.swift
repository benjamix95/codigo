import SwiftUI
import CoderEngine

@MainActor
final class GitPanelStore: ObservableObject {
    // MARK: - Grouped State (reduces @Published explosion)

    @Published var isOpen = false
    @Published var repo = GitRepoState()
    @Published var commitForm = GitCommitFormState()
    @Published var branchForm = GitBranchFormState()
    @Published var remote = GitRemoteState()

    // MARK: - Backward-compatible accessors – Repo

    var gitRoot: String? {
        get { repo.gitRoot }
        set { repo.gitRoot = newValue }
    }
    var currentBranch: String {
        get { repo.currentBranch }
        set { repo.currentBranch = newValue }
    }
    var branches: [GitBranch] {
        get { repo.branches }
        set { repo.branches = newValue }
    }
    var status: GitStatusSummary? {
        get { repo.status }
        set { repo.status = newValue }
    }
    var changedFiles: [GitChangedFile] {
        get { repo.changedFiles }
        set { repo.changedFiles = newValue }
    }
    var commitLog: [GitLogEntry] {
        get { repo.commitLog }
        set { repo.commitLog = newValue }
    }
    var isRefreshing: Bool {
        get { repo.isRefreshing }
        set { repo.isRefreshing = newValue }
    }
    var isBusy: Bool {
        get { repo.isBusy }
        set { repo.isBusy = newValue }
    }
    var error: String? {
        get { repo.error }
        set { repo.error = newValue }
    }
    var successMessage: String? {
        get { repo.successMessage }
        set { repo.successMessage = newValue }
    }

    // MARK: - Backward-compatible accessors – Commit Form

    var commitMessage: String {
        get { commitForm.commitMessage }
        set { commitForm.commitMessage = newValue }
    }
    var includeUnstaged: Bool {
        get { commitForm.includeUnstaged }
        set { commitForm.includeUnstaged = newValue }
    }
    var nextStep: GitCommitNextStep {
        get { commitForm.nextStep }
        set { commitForm.nextStep = newValue }
    }

    // MARK: - Backward-compatible accessors – Branch Form

    var showCreateBranch: Bool {
        get { branchForm.showCreateBranch }
        set { branchForm.showCreateBranch = newValue }
    }
    var newBranchName: String {
        get { branchForm.newBranchName }
        set { branchForm.newBranchName = newValue }
    }
    var branchSearch: String {
        get { branchForm.branchSearch }
        set { branchForm.branchSearch = newValue }
    }

    // MARK: - Backward-compatible accessors – Remote

    var stashEntries: [GitStashEntry] {
        get { remote.stashEntries }
        set { remote.stashEntries = newValue }
    }
    var remoteBranches: [GitBranch] {
        get { remote.remoteBranches }
        set { remote.remoteBranches = newValue }
    }
    var aheadCount: Int {
        get { remote.aheadCount }
        set { remote.aheadCount = newValue }
    }
    var behindCount: Int {
        get { remote.behindCount }
        set { remote.behindCount = newValue }
    }
    var showDeleteBranchConfirm: Bool {
        get { remote.showDeleteBranchConfirm }
        set { remote.showDeleteBranchConfirm = newValue }
    }
    var branchToDelete: String? {
        get { remote.branchToDelete }
        set { remote.branchToDelete = newValue }
    }
    var stashMessage: String {
        get { remote.stashMessage }
        set { remote.stashMessage = newValue }
    }

    let gitService = GitService()
    let commitMessageGenerator = GitCommitMessageGenerator()
    let refreshQueue = DispatchQueue(label: "com.solocode.git-panel.refresh", qos: .utility)
    var pendingRefreshWorkItem: DispatchWorkItem?
    var postCommitBugHunterObserver: ((GitCommitResult, String) -> Void)?

    // Monotonic counter used to discard stale refresh results.
    var refreshGeneration: Int = 0

    // MARK: - Derived State
    var stagedFiles: [GitChangedFile] { changedFiles.filter(\.isStaged) }
    var unstagedFiles: [GitChangedFile] { changedFiles.filter { !$0.isStaged } }
    var totalAdded: Int { changedFiles.reduce(0) { $0 + $1.added } }
    var totalRemoved: Int { changedFiles.reduce(0) { $0 + $1.removed } }
    var canPush: Bool { status?.hasRemote == true }
    var canCreatePR: Bool { canPush && currentBranch != "main" && currentBranch != "master" }
    var filteredBranches: [GitBranch] {
        let query = branchSearch.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if query.isEmpty { return branches }
        return branches.filter { $0.name.lowercased().contains(query) }
    }
}
