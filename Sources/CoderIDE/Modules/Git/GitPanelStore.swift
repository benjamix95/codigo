import SwiftUI
import CoderEngine

@MainActor
final class GitPanelStore: ObservableObject {
    // MARK: - Published State
    @Published var isOpen = false

    @Published private(set) var gitRoot: String?
    @Published private(set) var currentBranch = "-"
    @Published private(set) var branches: [GitBranch] = []
    @Published private(set) var status: GitStatusSummary?
    @Published private(set) var changedFiles: [GitChangedFile] = []
    @Published private(set) var commitLog: [GitLogEntry] = []
    @Published private(set) var isRefreshing = false
    @Published private(set) var isBusy = false
    @Published var error: String?
    @Published var successMessage: String?

    // Commit form state
    @Published var commitMessage = ""
    @Published var includeUnstaged = true
    @Published var nextStep: GitCommitNextStep = .commit

    // Branch creation
    @Published var showCreateBranch = false
    @Published var newBranchName = ""
    @Published var branchSearch = ""

    // Extended state
    @Published private(set) var stashEntries: [GitStashEntry] = []
    @Published private(set) var remoteBranches: [GitBranch] = []
    @Published private(set) var aheadCount: Int = 0
    @Published private(set) var behindCount: Int = 0
    @Published var showDeleteBranchConfirm = false
    @Published var branchToDelete: String?
    @Published var stashMessage = ""

    let gitService = GitService()
    private let commitMessageGenerator = GitCommitMessageGenerator()
    private let refreshQueue = DispatchQueue(label: "com.codigo.git-panel.refresh", qos: .utility)
    private var pendingRefreshWorkItem: DispatchWorkItem?

    // Monotonic counter used to discard stale refresh results.
    private var refreshGeneration: Int = 0

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
