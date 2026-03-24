import Foundation

@MainActor
extension UsageFooterView {
    func switchConversationToWorktree(session: WorktreeSession) {
        guard let conversationId = selectedConversationId else { return }
        do {
            let switchPath = try validatedRepositorySwitchPath(
                session.worktreePath,
                missingMessage: "Il percorso worktree non esiste più: \(session.worktreePath)"
            )
            try WorktreeContextRouter.switchConversation(
                conversationId: conversationId,
                toProjectPath: switchPath,
                chatStore: chatStore,
                projectContextStore: projectContextStore,
                workspaceStore: workspaceStore
            )
            wt.worktreeStatusMessage = "Passato al worktree \(session.worktreeBranch)."
        } catch {
            wt.worktreeErrorMessage = error.localizedDescription
        }
    }

    func returnConversationToLocal(session: WorktreeSession) {
        guard let conversationId = selectedConversationId else { return }
        if !session.autoMergeOnReturn {
            do {
                let switchPath = try validatedRepositorySwitchPath(
                    session.localRootPath,
                    missingMessage: "Il repository locale non è più disponibile: \(session.localRootPath)"
                )
                try WorktreeContextRouter.switchConversation(
                    conversationId: conversationId,
                    toProjectPath: switchPath,
                    chatStore: chatStore,
                    projectContextStore: projectContextStore,
                    workspaceStore: workspaceStore
                )
                wt.worktreeStatusMessage = "Rientro su Local completato."
            } catch {
                wt.worktreeErrorMessage = error.localizedDescription
            }
            return
        }

        wt.isWorktreeActionInFlight = true
        wt.worktreeStatusMessage = "Auto-merge in corso..."
        wt.worktreeActionTask?.cancel()
        wt.worktreeActionTask = Task { @MainActor in
            defer {
                wt.isWorktreeActionInFlight = false
                wt.worktreeActionTask = nil
            }
            do {
                let report = try await performAutoMergePipeline(session: session)
                let switchPath = try validatedRepositorySwitchPath(
                    session.localRootPath,
                    missingMessage: "Il repository locale non è più disponibile: \(session.localRootPath)"
                )
                try WorktreeContextRouter.switchConversation(
                    conversationId: conversationId,
                    toProjectPath: switchPath,
                    chatStore: chatStore,
                    projectContextStore: projectContextStore,
                    workspaceStore: workspaceStore
                )
                if report.deletedWorktree && report.deletedBranch {
                    worktreeSessionStore.remove(conversationId: conversationId)
                } else {
                    var updated = session
                    updated.lastUpdatedAt = .now
                    worktreeSessionStore.upsert(updated)
                }
                wt.worktreeStatusMessage = "Merge completato su \(report.mergeTargetBranch)."
            } catch {
                wt.worktreeErrorMessage = error.localizedDescription
            }
        }
    }

    func performAutoMergePipeline(session: WorktreeSession) async throws -> GitAutoMergeReport {
        let gitService = GitService()
        let aiService = WorktreeMergeAIService()
        let preferredProviderId = providerRegistry.selectedProviderId
        var steps: [String] = []

        if try gitService.worktreeStatusIsDirty(gitRoot: session.worktreePath) {
            _ = try await aiService.enforceQualityGate(
                gitRoot: session.worktreePath,
                stage: "pre-commit",
                preferredProviderId: preferredProviderId,
                providerRegistry: providerRegistry,
                maxAttempts: 3
            )
            try gitService.autoCommitAllChanges(
                gitRoot: session.worktreePath,
                message: "chore(worktree): quality-gated auto-commit before merge"
            )
            steps.append("Auto-commit worktree eseguito.")
        } else {
            steps.append("Worktree già pulito: nessun auto-commit necessario.")
        }

        if try gitService.worktreeStatusIsDirty(gitRoot: session.localRootPath) {
            throw GitServiceError.commandFailed(
                "Il repository locale contiene modifiche non committate. Auto-merge annullato."
            )
        }
        steps.append("Preflight local root OK.")

        var mergeStarted = false
        do {
            let mergeStart = try gitService.startNoCommitMerge(
                sourceBranch: session.worktreeBranch,
                intoTarget: session.mergeTargetBranch,
                gitRoot: session.localRootPath
            )
            mergeStarted = true
            steps.append("Merge tecnico avviato su \(session.mergeTargetBranch).")

            if mergeStart.hadConflicts {
                let conflicted = try gitService.listConflictedFiles(gitRoot: session.localRootPath)
                let resolution = try await aiService.resolveConflictsAndFixTests(
                    gitRoot: session.localRootPath,
                    sourceBranch: session.worktreeBranch,
                    targetBranch: session.mergeTargetBranch,
                    conflictedFiles: conflicted,
                    preferredProviderId: preferredProviderId,
                    providerRegistry: providerRegistry,
                    maxFixRounds: 3
                )
                steps.append(resolution.notes)
            } else {
                _ = try await aiService.enforceQualityGate(
                    gitRoot: session.localRootPath,
                    stage: "post-merge",
                    preferredProviderId: preferredProviderId,
                    providerRegistry: providerRegistry,
                    maxAttempts: 3
                )
                steps.append("Quality gate post-merge superato.")
            }

            try gitService.finalizeMergeCommit(
                gitRoot: session.localRootPath,
                message: "merge: integrate \(session.worktreeBranch) into \(session.mergeTargetBranch)"
            )
            steps.append("Commit merge finalizzato.")
        } catch {
            if mergeStarted {
                try? gitService.abortMerge(gitRoot: session.localRootPath)
            }
            throw error
        }

        var deletedWorktree = false
        var deletedBranch = false
        if session.deleteBranchAfterMerge {
            try gitService.removeWorktree(
                gitRoot: session.localRootPath,
                worktreePath: session.worktreePath,
                force: true
            )
            deletedWorktree = true
            try gitService.deleteMergedBranch(
                name: session.worktreeBranch,
                gitRoot: session.localRootPath
            )
            deletedBranch = true
            steps.append("Worktree e branch eliminati post-merge.")
        }

        return GitAutoMergeReport(
            localRootPath: session.localRootPath,
            worktreePath: session.worktreePath,
            worktreeBranch: session.worktreeBranch,
            mergeTargetBranch: session.mergeTargetBranch,
            steps: steps,
            deletedWorktree: deletedWorktree,
            deletedBranch: deletedBranch
        )
    }

    private func validatedRepositorySwitchPath(
        _ path: String,
        missingMessage: String
    ) throws -> String {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            throw GitServiceError.commandFailed(missingMessage)
        }
        let resolvedRoot = try GitService().resolveGitRoot(from: path)
        let normalizedRoot = URL(fileURLWithPath: resolvedRoot)
            .standardizedFileURL
            .path(percentEncoded: false)
        let normalizedPath = URL(fileURLWithPath: path)
            .standardizedFileURL
            .path(percentEncoded: false)
        guard normalizedRoot == normalizedPath else {
            throw GitServiceError.commandFailed(
                "Il percorso selezionato non punta alla root del repository Git."
            )
        }
        return normalizedRoot
    }
}
