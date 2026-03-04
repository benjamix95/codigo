import Foundation

extension UsageFooterView {
    var activeWorktreeSession: WorktreeSession? {
        worktreeSessionStore.session(for: selectedConversationId)
    }

    var isCurrentlyInWorktree: Bool {
        worktreeSessionStore.isInWorktree(
            conversationId: selectedConversationId,
            currentPath: effectiveContext.primaryPath
        )
    }

    var worktreeToggleTitle: String {
        isCurrentlyInWorktree ? "Passa a Local" : "Passa al worktree"
    }

    var worktreeToggleHelpText: String {
        if isWorktreeActionInFlight {
            return "Operazione worktree in corso..."
        }
        if isCurrentlyInWorktree {
            return "Torna al progetto locale e opzionalmente avvia auto-merge"
        }
        return "Crea o apri il worktree associato a questa conversazione"
    }

    var isWorktreeToggleDisabled: Bool {
        if selectedConversationId == nil { return true }
        guard let root = gitPanelStore.gitRoot else { return true }
        return root.isEmpty
    }

    var availableBranchNames: [String] {
        availableLocalBranches.map(\.name)
    }

    func clearWorktreeFeedback() {
        worktreeStatusMessage = nil
        worktreeErrorMessage = nil
    }

    func resolvedGitRoot(from path: String?) -> String? {
        if let cached = gitPanelStore.gitRoot, !cached.isEmpty {
            return cached
        }
        guard let path, !path.isEmpty else { return nil }
        return try? GitService().resolveGitRoot(from: path)
    }

    func defaultWorktreeBranchName(baseBranch: String) -> String {
        let base = sanitizeBranchComponent(baseBranch.isEmpty ? "task" : baseBranch)
        let suffix = String(UUID().uuidString.lowercased().prefix(6))
        return "solocode/\(base)-\(suffix)"
    }

    func suggestedWorktreePath(localRoot: String, worktreeBranch: String) -> String {
        let rootURL = URL(fileURLWithPath: localRoot).standardizedFileURL
        let parentURL = rootURL.deletingLastPathComponent()
        let repoName = rootURL.lastPathComponent
        let branchSlug = sanitizeBranchComponent(worktreeBranch)
        let dir = "\(repoName)-worktrees"
        return parentURL
            .appendingPathComponent(dir, isDirectory: true)
            .appendingPathComponent(branchSlug, isDirectory: true)
            .path(percentEncoded: false)
    }

    func sanitizeBranchComponent(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if trimmed.isEmpty { return "task" }
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789-_")
        let mapped = trimmed.map { char -> Character in
            let scalar = char.unicodeScalars.first!
            if allowed.contains(scalar) {
                return char
            }
            return "-"
        }
        var collapsed = String(mapped)
        while collapsed.contains("--") {
            collapsed = collapsed.replacingOccurrences(of: "--", with: "-")
        }
        return collapsed.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    }
}
