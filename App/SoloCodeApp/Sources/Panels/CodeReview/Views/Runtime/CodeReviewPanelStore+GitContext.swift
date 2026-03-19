import CoderEngine
import Foundation

extension CodeReviewPanelStore {
    func scheduleGitContextStatus(_ status: ReviewPanelGitContextStatus) {
        scheduleDeferredMutation { store in
            store.isLoadingGit = status.isLoading
            guard store.gitContextStatus != status else { return }
            store.gitContextStatus = status
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
            store.isLoadingGit = false
            store.gitContextStatus = .loaded
        }
    }

    func scheduleClearedGitContext(status: ReviewPanelGitContextStatus) {
        scheduleDeferredMutation { store in
            store.gitBranches = []
            store.gitRemoteBranches = []
            store.gitCommitLog = []
            store.currentGitBranch = ""
            store.isLoadingGit = false
            store.gitContextStatus = status
        }
    }

    func refreshGitContext() async {
        guard !isGitContextRefreshInFlight else { return }
        isGitContextRefreshInFlight = true
        scheduleGitContextStatus(.loading)
        let outcome = fetchGitContext(limit: 50)
        isGitContextRefreshInFlight = false
        applyGitContextOutcome(outcome)
    }

    func loadMoreCommits(limit: Int = 100) async {
        scheduleGitContextStatus(.loading)
        applyGitContextOutcome(fetchGitContext(limit: limit))
    }

    private func fetchGitContext(limit: Int) -> ReviewPanelGitContextOutcome {
        guard let workspacePath = workspaceStore.activeWorkspacePaths.first?.path,
              !workspacePath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return .failure("Workspace attivo mancante")
        }

        let loadedState = ReviewCoreBridge.loadedState()
        guard ReviewCoreBridge.isEnabled else {
            return .failure(runtimeDisabledMessage(loadedState: loadedState))
        }
        guard loadedState.loaded else {
            return .failure(runtimeUnavailableMessage(loadedState: loadedState))
        }

        guard let response: ReviewPanelGitContextResponse = ReviewCoreBridge.call(
            functionName: "review_core_panel_git_context",
            request: ReviewPanelGitContextRequest(
                workspacePath: workspacePath,
                limit: limit
            )
        ) else {
            return .failure("Chiamata Rust review_core_panel_git_context fallita")
        }

        if let error = response.error {
            if isNotGitRepositoryError(error) {
                return .notRepository("Il workspace attivo non è un repository Git. \(error.message)")
            }
            return .failure(error.message)
        }

        return .success(response)
    }

    private func applyGitContextOutcome(_ outcome: ReviewPanelGitContextOutcome) {
        switch outcome {
        case .success(let response):
            scheduleGitContextSnapshot(
                branches: response.branches.map(\.appModel),
                remotes: response.remotes.map(\.appModel),
                commits: response.commits.map(\.appModel),
                currentBranch: response.currentBranch
            )
        case .notRepository(let message):
            scheduleClearedGitContext(status: .notRepository(message: message))
        case .failure(let message):
            scheduleClearedGitContext(status: .failed(message: message))
        }
    }

    private func runtimeDisabledMessage(loadedState: ReviewCoreLoadedState) -> String {
        let env = ProcessInfo.processInfo.environment
        let isForcedOff = env["SOLOCODE_REVIEW_CORE_FORCE_SWIFT"] == "1"
            || env["SOLOCODE_REVIEW_CORE_DISABLE_RUST"] == "1"
        guard isForcedOff else {
            return runtimeUnavailableMessage(loadedState: loadedState)
        }

        var message = "Runtime Rust review core disabilitato dalla configurazione del processo."
        if let path = loadedState.libraryPath, !path.isEmpty {
            message += " Libreria rilevata: \(path)"
        }
        return message
    }

    private func runtimeUnavailableMessage(loadedState: ReviewCoreLoadedState) -> String {
        var parts = ["Runtime Rust review core non disponibile."]
        if let reason = loadedState.failureReason, !reason.isEmpty {
            parts.append("Motivo: \(reason)")
        }
        if let path = loadedState.libraryPath, !path.isEmpty {
            parts.append("Path: \(path)")
        }
        return parts.joined(separator: " ")
    }

    private func isNotGitRepositoryError(_ error: ReviewPanelReduceError) -> Bool {
        guard error.code == "git_root_failed" else { return false }
        let message = error.message.lowercased()
        return message.contains("not a git repository")
            || message.contains("must be run in a work tree")
            || message.contains("non è un repository git")
    }
}

private enum ReviewPanelGitContextOutcome {
    case success(ReviewPanelGitContextResponse)
    case notRepository(String)
    case failure(String)
}

private struct ReviewPanelGitContextRequest: Encodable {
    let schemaVersion: Int = 1
    let workspacePath: String
    let limit: Int
}

private struct ReviewPanelGitContextResponse: Decodable {
    let schemaVersion: Int
    let error: ReviewPanelReduceError?
    let branches: [ReviewPanelGitBranch]
    let remotes: [ReviewPanelGitBranch]
    let commits: [ReviewPanelGitCommit]
    let currentBranch: String
}

private struct ReviewPanelGitBranch: Decodable {
    let name: String
    let isCurrent: Bool
    let isRemoteTracking: Bool

    var appModel: GitBranch {
        GitBranch(name: name, isCurrent: isCurrent, isRemoteTracking: isRemoteTracking)
    }
}

private struct ReviewPanelGitCommit: Decodable {
    let sha: String
    let shortSha: String
    let subject: String
    let authorName: String
    let relativeDate: String

    var appModel: GitLogEntry {
        GitLogEntry(
            sha: sha,
            shortSha: shortSha,
            subject: subject,
            authorName: authorName,
            relativeDate: relativeDate
        )
    }
}
