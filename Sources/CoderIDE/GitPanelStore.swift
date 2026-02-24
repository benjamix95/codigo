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

    // New state
    @Published private(set) var stashEntries: [GitStashEntry] = []
    @Published private(set) var remoteBranches: [GitBranch] = []
    @Published private(set) var aheadCount: Int = 0
    @Published private(set) var behindCount: Int = 0
    @Published var showDeleteBranchConfirm = false
    @Published var branchToDelete: String?
    @Published var stashMessage = ""

    let gitService = GitService()
    private let commitMessageGenerator = GitCommitMessageGenerator()

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

    // MARK: - Refresh
    func refresh(workingDirectory: String?) {
        isRefreshing = true
        defer { isRefreshing = false }
        error = nil
        do {
            let root = try gitService.resolveGitRoot(from: workingDirectory)
            gitRoot = root
            currentBranch = try gitService.currentBranch(gitRoot: root)
            branches = try gitService.listLocalBranches(gitRoot: root)
            status = try gitService.status(gitRoot: root)
            changedFiles = try gitService.changedFiles(gitRoot: root)
            commitLog = (try? gitService.commitHistory(gitRoot: root, limit: 30)) ?? []
            remoteBranches = (try? gitService.listRemoteBranches(gitRoot: root)) ?? []
            stashEntries = (try? gitService.stashList(gitRoot: root)) ?? []
            if let ab = try? gitService.aheadBehindCount(gitRoot: root) {
                aheadCount = ab.ahead
                behindCount = ab.behind
            } else {
                aheadCount = 0
                behindCount = 0
            }
        } catch {
            gitRoot = nil
            currentBranch = "-"
            branches = []
            status = nil
            changedFiles = []
            commitLog = []
            remoteBranches = []
            stashEntries = []
            aheadCount = 0
            behindCount = 0
            if let e = error as? GitServiceError {
                switch e {
                case .notGitRepository:
                    self.error = nil
                default:
                    self.error = error.localizedDescription
                }
            } else {
                self.error = error.localizedDescription
            }
        }
    }

    // MARK: - File Undo
    func undo(path: String) {
        guard let gitRoot else { return }
        do {
            try gitService.restoreFile(gitRoot: gitRoot, path: path)
            refresh(workingDirectory: gitRoot)
        } catch {
            self.error = error.localizedDescription
        }
    }

    func undoAll() {
        guard let gitRoot else { return }
        do {
            try gitService.restoreAll(gitRoot: gitRoot)
            refresh(workingDirectory: gitRoot)
        } catch {
            self.error = error.localizedDescription
        }
    }

    // MARK: - Branch Operations
    func switchBranch(_ name: String) {
        guard let gitRoot else { return }
        isBusy = true
        error = nil
        successMessage = nil
        Task {
            do {
                try gitService.checkoutBranch(name: name, gitRoot: gitRoot)
                await MainActor.run {
                    successMessage = "Branch: \(name)"
                    refresh(workingDirectory: gitRoot)
                    isBusy = false
                }
            } catch {
                await MainActor.run {
                    self.error = error.localizedDescription
                    isBusy = false
                }
            }
        }
    }

    func createAndCheckoutBranch() {
        guard let gitRoot else { return }
        let name = newBranchName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        isBusy = true
        error = nil
        successMessage = nil
        Task {
            do {
                try gitService.createAndCheckoutBranch(name: name, gitRoot: gitRoot)
                await MainActor.run {
                    successMessage = "Branch created: \(name)"
                    showCreateBranch = false
                    newBranchName = ""
                    refresh(workingDirectory: gitRoot)
                    isBusy = false
                }
            } catch {
                await MainActor.run {
                    self.error = error.localizedDescription
                    isBusy = false
                }
            }
        }
    }

    // MARK: - Commit/Push/PR
    func runCommitFlow(providerRegistry: ProviderRegistry) {
        guard let gitRoot else { return }
        isBusy = true
        error = nil
        successMessage = nil

        Task {
            do {
                var message = commitMessage.trimmingCharacters(in: .whitespacesAndNewlines)
                if message.isEmpty {
                    let diff = try gitService.diffForCommitMessage(
                        gitRoot: gitRoot, includeUnstaged: includeUnstaged)
                    if let provider = bestCommitMessageProvider(providerRegistry: providerRegistry) {
                        let aiContext = WorkspaceContext(
                            workspacePath: URL(fileURLWithPath: gitRoot))
                        message = try await commitMessageGenerator.generateCommitMessage(
                            diff: diff, provider: provider, context: aiContext)
                    } else {
                        message = commitMessageGenerator.fallbackMessage(
                            from: try gitService.status(gitRoot: gitRoot)
                        )
                    }
                }

                let commit = try gitService.commit(
                    gitRoot: gitRoot, message: message, includeUnstaged: includeUnstaged)

                if nextStep == .commitAndPush || nextStep == .commitAndCreatePR {
                    try gitService.push(gitRoot: gitRoot, branch: currentBranch)
                }
                var success = "Commit \(commit.shortSha): \(commit.subject)"
                if nextStep == .commitAndCreatePR {
                    let pr = try gitService.createPullRequest(
                        gitRoot: gitRoot,
                        base: nil,
                        title: commit.subject,
                        body: nil
                    )
                    success += " • PR: \(pr.url)"
                }
                await MainActor.run {
                    successMessage = success
                    commitMessage = ""
                    refresh(workingDirectory: gitRoot)
                    isBusy = false
                }
            } catch {
                await MainActor.run {
                    self.error = error.localizedDescription
                    isBusy = false
                }
            }
        }
    }

    func pushOnly() {
        guard let gitRoot else { return }
        isBusy = true
        error = nil
        successMessage = nil
        Task {
            do {
                try gitService.push(gitRoot: gitRoot, branch: currentBranch)
                await MainActor.run {
                    successMessage = "Push completed on \(currentBranch)"
                    refresh(workingDirectory: gitRoot)
                    isBusy = false
                }
            } catch {
                await MainActor.run {
                    self.error = error.localizedDescription
                    isBusy = false
                }
            }
        }
    }

    func createPROnly() {
        guard let gitRoot else { return }
        isBusy = true
        error = nil
        successMessage = nil
        Task {
            do {
                let result = try gitService.createPullRequest(
                    gitRoot: gitRoot,
                    base: nil,
                    title: "chore: update \(currentBranch)",
                    body: nil
                )
                await MainActor.run {
                    successMessage = "PR created: \(result.url)"
                    isBusy = false
                }
            } catch {
                await MainActor.run {
                    self.error = error.localizedDescription
                    isBusy = false
                }
            }
        }
    }

    // MARK: - Pull & Fetch
    func pull() {
        guard let gitRoot else { return }
        isBusy = true; error = nil; successMessage = nil
        Task {
            do {
                _ = try gitService.pull(gitRoot: gitRoot)
                await MainActor.run {
                    successMessage = "Pull completed"
                    refresh(workingDirectory: gitRoot)
                    isBusy = false
                }
            } catch {
                await MainActor.run { self.error = error.localizedDescription; isBusy = false }
            }
        }
    }

    func fetch() {
        guard let gitRoot else { return }
        isBusy = true; error = nil; successMessage = nil
        Task {
            do {
                _ = try gitService.fetch(gitRoot: gitRoot)
                await MainActor.run {
                    successMessage = "Fetch completed"
                    refresh(workingDirectory: gitRoot)
                    isBusy = false
                }
            } catch {
                await MainActor.run { self.error = error.localizedDescription; isBusy = false }
            }
        }
    }

    // MARK: - Stash
    func stash(message: String?) {
        guard let gitRoot else { return }
        isBusy = true; error = nil; successMessage = nil
        Task {
            do {
                try gitService.stash(gitRoot: gitRoot, message: message)
                await MainActor.run {
                    successMessage = "Changes stashed"
                    stashMessage = ""
                    refresh(workingDirectory: gitRoot)
                    isBusy = false
                }
            } catch {
                await MainActor.run { self.error = error.localizedDescription; isBusy = false }
            }
        }
    }

    func stashPop() {
        guard let gitRoot else { return }
        isBusy = true; error = nil; successMessage = nil
        Task {
            do {
                try gitService.stashPop(gitRoot: gitRoot)
                await MainActor.run {
                    successMessage = "Stash popped"
                    refresh(workingDirectory: gitRoot)
                    isBusy = false
                }
            } catch {
                await MainActor.run { self.error = error.localizedDescription; isBusy = false }
            }
        }
    }

    func stashDrop(index: Int) {
        guard let gitRoot else { return }
        isBusy = true; error = nil; successMessage = nil
        Task {
            do {
                try gitService.stashDrop(gitRoot: gitRoot, index: index)
                await MainActor.run {
                    successMessage = "Stash dropped"
                    refresh(workingDirectory: gitRoot)
                    isBusy = false
                }
            } catch {
                await MainActor.run { self.error = error.localizedDescription; isBusy = false }
            }
        }
    }

    // MARK: - Branch Delete/Rename
    func deleteBranch(name: String, force: Bool) {
        guard let gitRoot else { return }
        isBusy = true; error = nil; successMessage = nil
        Task {
            do {
                try gitService.deleteBranch(name: name, gitRoot: gitRoot, force: force)
                await MainActor.run {
                    successMessage = "Branch deleted: \(name)"
                    showDeleteBranchConfirm = false
                    branchToDelete = nil
                    refresh(workingDirectory: gitRoot)
                    isBusy = false
                }
            } catch {
                await MainActor.run { self.error = error.localizedDescription; isBusy = false }
            }
        }
    }

    func renameBranch(oldName: String, newName: String) {
        guard let gitRoot else { return }
        isBusy = true; error = nil; successMessage = nil
        Task {
            do {
                try gitService.renameBranch(oldName: oldName, newName: newName, gitRoot: gitRoot)
                await MainActor.run {
                    successMessage = "Branch renamed: \(oldName) → \(newName)"
                    refresh(workingDirectory: gitRoot)
                    isBusy = false
                }
            } catch {
                await MainActor.run { self.error = error.localizedDescription; isBusy = false }
            }
        }
    }

    func checkoutRemoteBranch(name: String) {
        guard let gitRoot else { return }
        isBusy = true; error = nil; successMessage = nil
        Task {
            do {
                try gitService.checkoutRemoteBranch(name: name, gitRoot: gitRoot)
                await MainActor.run {
                    successMessage = "Checked out: \(name)"
                    refresh(workingDirectory: gitRoot)
                    isBusy = false
                }
            } catch {
                await MainActor.run { self.error = error.localizedDescription; isBusy = false }
            }
        }
    }

    // MARK: - Stage/Unstage
    func stageFile(path: String) {
        guard let gitRoot else { return }
        do {
            try gitService.stageFile(path: path, gitRoot: gitRoot)
            refresh(workingDirectory: gitRoot)
        } catch {
            self.error = error.localizedDescription
        }
    }

    func unstageFile(path: String) {
        guard let gitRoot else { return }
        do {
            try gitService.unstageFile(path: path, gitRoot: gitRoot)
            refresh(workingDirectory: gitRoot)
        } catch {
            self.error = error.localizedDescription
        }
    }

    func stageAll() {
        guard let gitRoot else { return }
        do {
            try gitService.stageAll(gitRoot: gitRoot)
            refresh(workingDirectory: gitRoot)
        } catch {
            self.error = error.localizedDescription
        }
    }

    func unstageAll() {
        guard let gitRoot else { return }
        do {
            try gitService.unstageAll(gitRoot: gitRoot)
            refresh(workingDirectory: gitRoot)
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func bestCommitMessageProvider(providerRegistry: ProviderRegistry) -> (any LLMProvider)? {
        if let selected = providerRegistry.selectedProvider, selected.isAuthenticated() {
            return selected
        }
        if let codex = providerRegistry.provider(for: "codex-cli"), codex.isAuthenticated() {
            return codex
        }
        if let claude = providerRegistry.provider(for: "claude-cli"), claude.isAuthenticated() {
            return claude
        }
        return nil
    }
}
