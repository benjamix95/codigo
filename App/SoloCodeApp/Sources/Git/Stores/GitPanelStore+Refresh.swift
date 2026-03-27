import Foundation
import CoderEngine

private struct GitPanelBaseRefreshSnapshot {
    let gitRoot: String?
    let currentBranch: String
    let branches: [GitBranch]
    let status: GitStatusSummary?
    let aheadCount: Int
    let behindCount: Int
    let errorMessage: String?
}

private struct GitPanelDetailRefreshSnapshot {
    let changedFiles: [GitChangedFile]
    let commitLog: [GitLogEntry]
    let remoteBranches: [GitBranch]
    let stashEntries: [GitStashEntry]
    let errorMessage: String?
}

private func loadGitPanelBaseRefreshSnapshot(
    gitService: GitService,
    workingDirectory: String?
) -> GitPanelBaseRefreshSnapshot {
    do {
        let root = try gitService.resolveGitRoot(from: workingDirectory)
        let branch = try gitService.currentBranch(gitRoot: root)
        let branches = (try? gitService.listLocalBranches(gitRoot: root)) ?? []
        let status = try? gitService.status(gitRoot: root)
        let aheadBehind = (try? gitService.aheadBehindCount(gitRoot: root)) ?? (ahead: 0, behind: 0)
        return GitPanelBaseRefreshSnapshot(
            gitRoot: root,
            currentBranch: branch,
            branches: branches,
            status: status,
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
        return GitPanelBaseRefreshSnapshot(
            gitRoot: nil,
            currentBranch: "-",
            branches: [],
            status: nil,
            aheadCount: 0,
            behindCount: 0,
            errorMessage: errorMessage
        )
    }
}

private func loadGitPanelDetailRefreshSnapshot(
    gitService: GitService,
    workingDirectory: String?,
    includePanelDetails: Bool
) -> GitPanelDetailRefreshSnapshot {
    do {
        let root = try gitService.resolveGitRoot(from: workingDirectory)
        let changedFiles = (try? gitService.changedFiles(gitRoot: root)) ?? []
        let commitLog = includePanelDetails ? ((try? gitService.commitHistory(gitRoot: root, limit: 30)) ?? []) : []
        let remoteBranches = includePanelDetails ? ((try? gitService.listRemoteBranches(gitRoot: root)) ?? []) : []
        let stashEntries = includePanelDetails ? ((try? gitService.stashList(gitRoot: root)) ?? []) : []
        return GitPanelDetailRefreshSnapshot(
            changedFiles: changedFiles,
            commitLog: commitLog,
            remoteBranches: remoteBranches,
            stashEntries: stashEntries,
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
        return GitPanelDetailRefreshSnapshot(
            changedFiles: [],
            commitLog: [],
            remoteBranches: [],
            stashEntries: [],
            errorMessage: errorMessage
        )
    }
}

@MainActor
extension GitPanelStore {
    // MARK: - Refresh
    func refresh(workingDirectory: String?, force: Bool = false) {
        let includePanelDetails = isOpen
        let requestKey = normalizedRefreshRequestKey(for: workingDirectory)
        if !force, shouldSkipRefresh(
            requestKey: requestKey,
            includePanelDetails: includePanelDetails
        ) {
            return
        }

        pendingRefreshWorkItem?.cancel()
        pendingDetailRefreshWorkItem?.cancel()
        refreshGeneration += 1
        let generation = refreshGeneration
        lastRefreshRequestKey = requestKey
        lastRefreshIncludedPanelDetails = includePanelDetails
        lastRefreshScheduledAt = Date()
        DispatchQueue.main.async { [weak self] in
            self?.isRefreshing = true
            self?.error = nil
        }

        let requestedDirectory = workingDirectory
        let service = gitService
        let baseWorkItem = DispatchWorkItem { [weak self] in
            let snapshot = loadGitPanelBaseRefreshSnapshot(
                gitService: service,
                workingDirectory: requestedDirectory
            )
            DispatchQueue.main.async { [weak self] in
                guard let self, generation == self.refreshGeneration else { return }
                self.apply(baseSnapshot: snapshot)
            }
        }
        pendingRefreshWorkItem = baseWorkItem
        refreshQueue.asyncAfter(deadline: .now() + 0.08, execute: baseWorkItem)

        guard includePanelDetails || force else {
            isRefreshing = false
            return
        }

        let detailWorkItem = DispatchWorkItem { [weak self] in
            let snapshot = loadGitPanelDetailRefreshSnapshot(
                gitService: service,
                workingDirectory: requestedDirectory,
                includePanelDetails: includePanelDetails
            )
            DispatchQueue.main.async { [weak self] in
                guard let self, generation == self.refreshGeneration else { return }
                self.apply(detailSnapshot: snapshot)
            }
        }
        pendingDetailRefreshWorkItem = detailWorkItem
        let detailDelay: TimeInterval = 0.18
        refreshQueue.asyncAfter(deadline: .now() + detailDelay, execute: detailWorkItem)
    }

    private func apply(baseSnapshot: GitPanelBaseRefreshSnapshot) {
        let previousRoot = gitRoot
        gitRoot = baseSnapshot.gitRoot
        currentBranch = baseSnapshot.currentBranch
        branches = baseSnapshot.branches
        status = baseSnapshot.status
        aheadCount = baseSnapshot.aheadCount
        behindCount = baseSnapshot.behindCount
        error = baseSnapshot.errorMessage

        if baseSnapshot.gitRoot == nil || previousRoot != baseSnapshot.gitRoot {
            changedFiles = []
            commitLog = []
            remoteBranches = []
            stashEntries = []
        }
    }

    private func apply(detailSnapshot: GitPanelDetailRefreshSnapshot) {
        changedFiles = detailSnapshot.changedFiles
        commitLog = detailSnapshot.commitLog
        remoteBranches = detailSnapshot.remoteBranches
        stashEntries = detailSnapshot.stashEntries
        if let errorMessage = detailSnapshot.errorMessage {
            error = errorMessage
        }
        isRefreshing = false
    }

    private func normalizedRefreshRequestKey(for workingDirectory: String?) -> String {
        guard let workingDirectory, !workingDirectory.isEmpty else { return "__none__" }
        return URL(fileURLWithPath: workingDirectory).standardizedFileURL.path
    }

    private func shouldSkipRefresh(
        requestKey: String,
        includePanelDetails: Bool
    ) -> Bool {
        guard lastRefreshRequestKey == requestKey else { return false }
        guard lastRefreshIncludedPanelDetails == includePanelDetails else { return false }
        return Date().timeIntervalSince(lastRefreshScheduledAt) < 0.4
    }
}
