import Foundation
import CoderEngine

@MainActor
extension GitPanelStore {
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
