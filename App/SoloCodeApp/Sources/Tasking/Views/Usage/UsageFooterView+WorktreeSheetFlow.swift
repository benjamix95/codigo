import Foundation

@MainActor
extension UsageFooterView {
    func handleWorktreeToggleTap() {
        clearWorktreeFeedback()
        guard !wt.isWorktreeActionInFlight else { return }
        guard selectedConversationId != nil else {
            wt.worktreeErrorMessage = "Seleziona una conversazione prima di usare i worktree."
            return
        }
        guard resolvedGitRoot(from: effectiveContext.primaryPath) != nil else {
            wt.worktreeErrorMessage = "Nessun repository Git valido nel contesto corrente."
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

        wt.showWorktreeSheet = true
        beginWorktreeSheetPreparation()
    }

    func beginWorktreeSheetPreparation() {
        clearWorktreeFeedback()
        cancelWorktreeSheetPreparation(resetSheetState: true)

        guard let localRoot = resolvedGitRoot(from: effectiveContext.primaryPath) else {
            wt.worktreeErrorMessage = "Apri un repository Git valido prima di creare un worktree."
            wt.showWorktreeSheet = false
            return
        }

        wt.pendingWorktreeLocalRoot = localRoot
        wt.worktreeSheetLoadState = .loading
        wt.worktreeStatusMessage = "Caricamento branch locali..."

        wt.worktreeSheetTask = Task { @MainActor in
            defer {
                wt.worktreeStatusMessage = nil
                wt.worktreeSheetTask = nil
            }

            do {
                let bootstrap = try await worktreeFlowCoordinator.loadSheetBootstrap(
                    localRootPath: localRoot
                )
                guard !Task.isCancelled else { return }
                applyWorktreeSheetBootstrap(bootstrap)
            } catch {
                guard !Task.isCancelled else { return }
                wt.availableLocalBranches = []
                wt.worktreeSheetLoadState = .failed(error.localizedDescription)
                wt.worktreeErrorMessage = error.localizedDescription
            }
        }
    }

    func startWorktreeCreationFromSheet() {
        clearWorktreeFeedback()
        guard !wt.isWorktreeActionInFlight else { return }

        let branch = wt.worktreeBranchDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        let mergeTarget = wt.worktreeMergeTargetDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        let baseBranch = wt.worktreeBaseBranchDraft.trimmingCharacters(in: .whitespacesAndNewlines)

        let localRoot = wt.pendingWorktreeLocalRoot
        let worktreePath = suggestedWorktreePath(
            localRoot: localRoot ?? "",
            worktreeBranch: branch
        )

        let input: WorktreeCreateFlowInput
        do {
            input = try worktreeFlowCoordinator.validateCreateInput(
                conversationId: selectedConversationId,
                localRootPath: localRoot,
                worktreeBranch: branch,
                baseBranch: baseBranch,
                mergeTargetBranch: mergeTarget,
                worktreePath: worktreePath,
                autoMergeOnReturn: wt.worktreeAutoMergeOnReturn,
                deleteBranchAfterMerge: wt.worktreeDeleteBranchAfterMerge
            )
        } catch {
            wt.worktreeErrorMessage = error.localizedDescription
            return
        }

        wt.isWorktreeActionInFlight = true
        wt.worktreeStatusMessage = "Creazione worktree in corso..."
        wt.worktreeActionTask?.cancel()
        wt.worktreeActionTask = Task { @MainActor in
            defer {
                wt.isWorktreeActionInFlight = false
                wt.worktreeActionTask = nil
            }

            do {
                let outcome = try await worktreeFlowCoordinator.createAndSwitch(
                    input: input,
                    chatStore: chatStore,
                    projectContextStore: projectContextStore,
                    workspaceStore: workspaceStore
                ) { session in
                    worktreeSessionStore.upsert(session)
                }
                guard !Task.isCancelled else { return }
                wt.showWorktreeSheet = false
                cancelWorktreeSheetPreparation(resetSheetState: true)
                wt.worktreeStatusMessage = "Worktree attivo su \(outcome.session.worktreeBranch)."
            } catch {
                guard !Task.isCancelled else { return }
                wt.worktreeErrorMessage = error.localizedDescription
            }
        }
    }
}
