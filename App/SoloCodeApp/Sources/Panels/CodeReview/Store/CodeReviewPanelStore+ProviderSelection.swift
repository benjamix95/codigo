import CoderEngine
import Foundation

struct ReviewPanelProviderOption: Identifiable, Equatable {
    let id: String
    let displayName: String
    let modelName: String
    let iconName: String
    let isAuthenticated: Bool
}

extension CodeReviewPanelStore {
    func scheduleGitLoadingState(_ isLoading: Bool) {
        scheduleDeferredMutation { store in
            guard store.isLoadingGit != isLoading else { return }
            store.isLoadingGit = isLoading
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
        }
    }

    func scheduleCommitLogSnapshot(_ commits: [GitLogEntry]) {
        scheduleDeferredMutation { store in
            store.gitCommitLog = commits
        }
    }

    func refreshGitContext() async {
        guard let workspacePath = workspaceStore.activeWorkspacePaths.first?.path else { return }
        guard !isGitContextRefreshInFlight else { return }
        isGitContextRefreshInFlight = true
        scheduleGitLoadingState(true)
        defer {
            isGitContextRefreshInFlight = false
            scheduleGitLoadingState(false)
        }

        guard let response: ReviewPanelGitContextResponse = ReviewCoreBridge.call(
            functionName: "review_core_panel_git_context",
            request: ReviewPanelGitContextRequest(
                workspacePath: workspacePath,
                limit: 50
            )
        ), response.error == nil else {
            return
        }

        scheduleGitContextSnapshot(
            branches: response.branches.map(\.appModel),
            remotes: response.remotes.map(\.appModel),
            commits: response.commits.map(\.appModel),
            currentBranch: response.currentBranch
        )
    }

    func loadMoreCommits(limit: Int = 100) async {
        guard let workspacePath = workspaceStore.activeWorkspacePaths.first?.path else { return }
        guard let response: ReviewPanelGitContextResponse = ReviewCoreBridge.call(
            functionName: "review_core_panel_git_context",
            request: ReviewPanelGitContextRequest(
                workspacePath: workspacePath,
                limit: limit
            )
        ), response.error == nil else {
            return
        }
        scheduleCommitLogSnapshot(response.commits.map(\.appModel))
    }

    func selectBranch(_ branch: GitBranch) {
        selectedBranch = branch
        scopeTarget = .branch(branch.name)
        selectedCommits.removeAll()
    }

    func clearBranchSelection() {
        selectedBranch = nil
        scopeTarget = .uncommitted
    }

    func toggleCommitSelection(_ sha: String) {
        if selectedCommits.contains(sha) {
            selectedCommits.remove(sha)
        } else {
            selectedCommits.insert(sha)
        }
        updateScopeFromCommitSelection()
    }

    func selectCommitRange(from: Int, to: Int) {
        let range = min(from, to)...max(from, to)
        for index in range where index < gitCommitLog.count {
            selectedCommits.insert(gitCommitLog[index].sha)
        }
        updateScopeFromCommitSelection()
    }

    func clearCommitSelection() {
        selectedCommits.removeAll()
        scopeTarget = .uncommitted
    }

    func isCommitSelected(_ sha: String) -> Bool {
        selectedCommits.contains(sha)
    }

    var usesAutomaticProviderSelection: Bool {
        selectedProviderOverrideId == nil
    }

    var effectivePanelProviderId: String? {
        selectedProviderOverrideId
            ?? providerRegistry.selectedProviderId
            ?? providerRegistry.providers.first(where: {
                ProviderSupport.isAgentCompatibleProvider(id: $0.id)
            })?.id
    }

    var effectivePanelProvider: (any LLMProvider)? {
        guard let effectivePanelProviderId else { return providerRegistry.selectedProvider }
        return providerRegistry.provider(for: effectivePanelProviderId)
            ?? providerRegistry.selectedProvider
    }

    var effectivePanelProviderLabel: String {
        effectivePanelProviderOption?.modelName ?? "No provider"
    }

    var effectivePanelProviderName: String {
        effectivePanelProviderOption?.displayName ?? "Auto"
    }

    var effectivePanelProviderIconName: String {
        effectivePanelProviderOption?.iconName ?? "bolt.circle"
    }

    var effectivePanelProviderOption: ReviewPanelProviderOption? {
        guard let effectivePanelProviderId else { return nil }
        return providerOption(for: effectivePanelProviderId)
    }

    var panelRunBackendId: String? {
        effectivePanelProviderId
    }

    var panelProviderOptions: [ReviewPanelProviderOption] {
        providerRegistry.providers
            .filter { ProviderSupport.isAgentCompatibleProvider(id: $0.id) }
            .map { provider in
                ReviewPanelProviderOption(
                    id: provider.id,
                    displayName: provider.displayName,
                    modelName: providerModelName(for: provider.id),
                    iconName: providerIconName(for: provider.id),
                    isAuthenticated: provider.isAuthenticated()
                )
            }
            .sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
    }

    func setPanelProviderOverride(_ providerId: String?) {
        guard let providerId, !providerId.isEmpty else {
            selectedProviderOverrideId = nil
            return
        }
        guard panelProviderOptions.contains(where: { $0.id == providerId }) else { return }
        selectedProviderOverrideId = providerId
    }

    private func providerOption(for id: String) -> ReviewPanelProviderOption? {
        panelProviderOptions.first(where: { $0.id == id })
    }

    private func providerModelName(for id: String) -> String {
        let config = providerFactoryConfigBuilder()
        switch id {
        case "openai-api": return config.openaiModel
        case "anthropic-api": return config.anthropicModel
        case "google-api": return config.googleModel
        case "openrouter-api": return config.openrouterModel
        case "minimax-api": return config.minimaxModel
        case "grok-api": return config.grokModel
        case "codex-cli": return config.codexModelOverride.nilIfEmpty ?? "codex"
        case "claude-cli": return config.claudeModel
        case "gemini-cli": return config.geminiModelOverride.nilIfEmpty ?? "gemini"
        default: return id
        }
    }

    private func providerIconName(for id: String) -> String {
        switch id {
        case "codex-cli": return "sparkles.rectangle.stack"
        case "claude-cli": return "message.badge.waveform"
        case "gemini-cli": return "diamond"
        case "openai-api": return "sparkles"
        case "anthropic-api": return "text.quote"
        case "google-api": return "globe"
        case "openrouter-api": return "point.3.connected.trianglepath.dotted"
        case "minimax-api": return "m.circle"
        case "grok-api": return "bolt"
        default: return "bolt.circle"
        }
    }

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

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
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
