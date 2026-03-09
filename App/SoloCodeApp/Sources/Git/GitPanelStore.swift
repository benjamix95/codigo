import SwiftUI
import CoderEngine

@MainActor
final class GitPanelStore: ObservableObject {
    // MARK: - Published State
    @Published var isOpen = false

    @Published var gitRoot: String?
    @Published var currentBranch = "-"
    @Published var branches: [GitBranch] = []
    @Published var status: GitStatusSummary?
    @Published var changedFiles: [GitChangedFile] = []
    @Published var commitLog: [GitLogEntry] = []
    @Published var isRefreshing = false
    @Published var isBusy = false
    @Published var error: String?
    @Published var successMessage: String?

    // Commit form state
    @Published var commitMessage = ""
    @Published var includeUnstaged = false
    @Published var nextStep: GitCommitNextStep = .commit

    // Branch creation
    @Published var showCreateBranch = false
    @Published var newBranchName = ""
    @Published var branchSearch = ""

    // Extended state
    @Published var stashEntries: [GitStashEntry] = []
    @Published var remoteBranches: [GitBranch] = []
    @Published var aheadCount: Int = 0
    @Published var behindCount: Int = 0
    @Published var showDeleteBranchConfirm = false
    @Published var branchToDelete: String?
    @Published var stashMessage = ""

    let gitService = GitService()
    let commitMessageGenerator = GitCommitMessageGenerator()
    let refreshQueue = DispatchQueue(label: "com.codigo.git-panel.refresh", qos: .utility)
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
