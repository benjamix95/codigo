import Foundation

@MainActor
extension UsageFooterView {
    func prepareWorktreeSheetState() {
        clearWorktreeFeedback()
        guard let localRoot = resolvedGitRoot(from: effectiveContext.primaryPath) else {
            worktreeErrorMessage = "Apri un repository Git valido prima di creare un worktree."
            return
        }
        pendingWorktreeLocalRoot = localRoot

        let gitService = GitService()
        do {
            let localBranches = try gitService.listLocalBranches(gitRoot: localRoot)
            availableLocalBranches = localBranches
            let currentBranch = try gitService.currentBranch(gitRoot: localRoot)
            worktreeBaseBranchDraft = currentBranch
            if localBranches.contains(where: { $0.name == currentBranch }) {
                worktreeMergeTargetDraft = currentBranch
            } else {
                worktreeMergeTargetDraft = localBranches.first?.name ?? currentBranch
            }
            worktreeBranchDraft = defaultWorktreeBranchName(baseBranch: currentBranch)
            worktreeAutoMergeOnReturn = true
            worktreeDeleteBranchAfterMerge = false
        } catch {
            availableLocalBranches = []
            worktreeErrorMessage = error.localizedDescription
        }
    }

    func handleWorktreeToggleTap() {
        clearWorktreeFeedback()
        guard !isWorktreeActionInFlight else { return }
        guard selectedConversationId != nil else {
            worktreeErrorMessage = "Seleziona una conversazione prima di usare i worktree."
            return
        }
        guard resolvedGitRoot(from: effectiveContext.primaryPath) != nil else {
            worktreeErrorMessage = "Nessun repository Git valido nel contesto corrente."
            return
        }

        if let session = activeWorktreeSession {
            if isCurrentlyInWorktree {
                returnConversationToLocal(session: session)
            } else {
                switchConversationToWorktree(session: session)
            }
            return
        }
        prepareWorktreeSheetState()
        showWorktreeSheet = true
    }

    func startWorktreeCreationFromSheet() {
        clearWorktreeFeedback()
        guard !isWorktreeActionInFlight else { return }
        guard let conversationId = selectedConversationId else {
            worktreeErrorMessage = "Nessuna conversazione selezionata."
            return
        }
        guard let localRoot = pendingWorktreeLocalRoot else {
            worktreeErrorMessage = "Root locale non disponibile."
            return
        }

        let branch = worktreeBranchDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        let mergeTarget = worktreeMergeTargetDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        let baseBranch = worktreeBaseBranchDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !branch.isEmpty, !mergeTarget.isEmpty, !baseBranch.isEmpty else {
            worktreeErrorMessage = "Compila branch worktree, base e target merge."
            return
        }
        let worktreePath = suggestedWorktreePath(localRoot: localRoot, worktreeBranch: branch)

        isWorktreeActionInFlight = true
        worktreeStatusMessage = "Creazione worktree in corso..."
        worktreeActionTask?.cancel()
        worktreeActionTask = Task { @MainActor in
            defer {
                isWorktreeActionInFlight = false
                worktreeActionTask = nil
            }
            do {
                try GitService().createWorktree(
                    request: GitWorktreeCreateRequest(
                        gitRoot: localRoot,
                        branchName: branch,
                        fromBranch: baseBranch,
                        worktreePath: worktreePath
                    )
                )
                let session = WorktreeSession(
                    conversationId: conversationId,
                    localRootPath: localRoot,
                    worktreePath: worktreePath,
                    worktreeBranch: branch,
                    baseBranch: baseBranch,
                    mergeTargetBranch: mergeTarget,
                    autoMergeOnReturn: worktreeAutoMergeOnReturn,
                    deleteBranchAfterMerge: worktreeDeleteBranchAfterMerge
                )
                worktreeSessionStore.upsert(session)
                try WorktreeContextRouter.switchConversation(
                    conversationId: conversationId,
                    toProjectPath: worktreePath,
                    chatStore: chatStore,
                    projectContextStore: projectContextStore,
                    workspaceStore: workspaceStore
                )
                showWorktreeSheet = false
                worktreeStatusMessage = "Worktree attivo su \(branch)."
            } catch {
                worktreeErrorMessage = error.localizedDescription
            }
        }
    }

    func switchConversationToWorktree(session: WorktreeSession) {
        guard let conversationId = selectedConversationId else { return }
        guard FileManager.default.fileExists(atPath: session.worktreePath) else {
            worktreeErrorMessage = "Il percorso worktree non esiste più: \(session.worktreePath)"
            return
        }
        do {
            try WorktreeContextRouter.switchConversation(
                conversationId: conversationId,
                toProjectPath: session.worktreePath,
                chatStore: chatStore,
                projectContextStore: projectContextStore,
                workspaceStore: workspaceStore
            )
            worktreeStatusMessage = "Passato al worktree \(session.worktreeBranch)."
        } catch {
            worktreeErrorMessage = error.localizedDescription
        }
    }

    func returnConversationToLocal(session: WorktreeSession) {
        guard selectedConversationId != nil else { return }
        if !session.autoMergeOnReturn {
            do {
                try WorktreeContextRouter.switchConversation(
                    conversationId: selectedConversationId,
                    toProjectPath: session.localRootPath,
                    chatStore: chatStore,
                    projectContextStore: projectContextStore,
                    workspaceStore: workspaceStore
                )
                worktreeStatusMessage = "Rientro su Local completato."
            } catch {
                worktreeErrorMessage = error.localizedDescription
            }
            return
        }

        isWorktreeActionInFlight = true
        worktreeStatusMessage = "Auto-merge in corso..."
        worktreeActionTask?.cancel()
        worktreeActionTask = Task { @MainActor in
            defer {
                isWorktreeActionInFlight = false
                worktreeActionTask = nil
            }
            do {
                let report = try await performAutoMergePipeline(session: session)
                try WorktreeContextRouter.switchConversation(
                    conversationId: selectedConversationId,
                    toProjectPath: session.localRootPath,
                    chatStore: chatStore,
                    projectContextStore: projectContextStore,
                    workspaceStore: workspaceStore
                )
                if report.deletedWorktree && report.deletedBranch {
                    worktreeSessionStore.remove(conversationId: selectedConversationId)
                } else {
                    var updated = session
                    updated.lastUpdatedAt = .now
                    worktreeSessionStore.upsert(updated)
                }
                worktreeStatusMessage = "Merge completato su \(report.mergeTargetBranch)."
            } catch {
                worktreeErrorMessage = error.localizedDescription
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
}
