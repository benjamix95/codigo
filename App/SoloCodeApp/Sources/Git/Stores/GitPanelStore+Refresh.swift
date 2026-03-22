import Foundation
import CoderEngine

private struct GitPanelRefreshSnapshot {
    let gitRoot: String?
    let currentBranch: String
    let branches: [GitBranch]
    let status: GitStatusSummary?
    let changedFiles: [GitChangedFile]
    let commitLog: [GitLogEntry]
    let remoteBranches: [GitBranch]
    let stashEntries: [GitStashEntry]
    let aheadCount: Int
    let behindCount: Int
    let errorMessage: String?
}

private func loadGitPanelRefreshSnapshot(
    gitService: GitService,
    workingDirectory: String?
) -> GitPanelRefreshSnapshot {
    do {
        let root = try gitService.resolveGitRoot(from: workingDirectory)
        let branch = try gitService.currentBranch(gitRoot: root)
        let branches = try gitService.listLocalBranches(gitRoot: root)
        let status = try gitService.status(gitRoot: root)
        let changedFiles = try gitService.changedFiles(gitRoot: root)
        let commitLog = (try? gitService.commitHistory(gitRoot: root, limit: 30)) ?? []
        let remoteBranches = (try? gitService.listRemoteBranches(gitRoot: root)) ?? []
        let stashEntries = (try? gitService.stashList(gitRoot: root)) ?? []
        let aheadBehind = (try? gitService.aheadBehindCount(gitRoot: root)) ?? (ahead: 0, behind: 0)
        return GitPanelRefreshSnapshot(
            gitRoot: root,
            currentBranch: branch,
            branches: branches,
            status: status,
            changedFiles: changedFiles,
            commitLog: commitLog,
            remoteBranches: remoteBranches,
            stashEntries: stashEntries,
            aheadCount: aheadBehind.ahead,
            behindCount: aheadBehind.behind,
            errorMessage: nil
        )
    } catch {
        let errorMessage: String?
        if let gitError = error as? GitServiceError {
            switch gitError {
            case .notGitRepository:
                errorMessage = nil
            default:
                errorMessage = error.localizedDescription
            }
        } else {
            errorMessage = error.localizedDescription
        }
        return GitPanelRefreshSnapshot(
            gitRoot: nil,
            currentBranch: "-",
            branches: [],
            status: nil,
            changedFiles: [],
            commitLog: [],
            remoteBranches: [],
            stashEntries: [],
            aheadCount: 0,
            behindCount: 0,
            errorMessage: errorMessage
        )
    }
}

@MainActor
extension GitPanelStore {
    // MARK: - Refresh
    func refresh(workingDirectory: String?) {
        pendingRefreshWorkItem?.cancel()
        refreshGeneration += 1
        let generation = refreshGeneration
        DispatchQueue.main.async { [weak self] in
            self?.isRefreshing = true
            self?.error = nil
        }

        let requestedDirectory = workingDirectory
        let service = gitService
        let workItem = DispatchWorkItem { [weak self] in
            let snapshot = loadGitPanelRefreshSnapshot(
                gitService: service,
                workingDirectory: requestedDirectory
            )
            DispatchQueue.main.async { [weak self] in
                guard let self, generation == self.refreshGeneration else { return }
                self.apply(snapshot: snapshot)
            }
        }
        pendingRefreshWorkItem = workItem
        refreshQueue.asyncAfter(deadline: .now() + 0.2, execute: workItem)
    }

    private func apply(snapshot: GitPanelRefreshSnapshot) {
        gitRoot = snapshot.gitRoot
        currentBranch = snapshot.currentBranch
        branches = snapshot.branches
        status = snapshot.status
        changedFiles = snapshot.changedFiles
        commitLog = snapshot.commitLog
        remoteBranches = snapshot.remoteBranches
        stashEntries = snapshot.stashEntries
        aheadCount = snapshot.aheadCount
        behindCount = snapshot.behindCount
        error = snapshot.errorMessage
        isRefreshing = false
    }
}
