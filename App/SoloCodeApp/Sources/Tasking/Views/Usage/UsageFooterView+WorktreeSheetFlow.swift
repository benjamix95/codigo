import Foundation

@MainActor
extension UsageFooterView {
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

        showWorktreeSheet = true
        beginWorktreeSheetPreparation()
    }

    func beginWorktreeSheetPreparation() {
        clearWorktreeFeedback()
        cancelWorktreeSheetPreparation(resetSheetState: true)

        guard let localRoot = resolvedGitRoot(from: effectiveContext.primaryPath) else {
            worktreeErrorMessage = "Apri un repository Git valido prima di creare un worktree."
            showWorktreeSheet = false
            return
        }

        pendingWorktreeLocalRoot = localRoot
        worktreeSheetLoadState = .loading
        worktreeStatusMessage = "Caricamento branch locali..."

        worktreeSheetTask = Task { @MainActor in
            defer {
                worktreeStatusMessage = nil
                worktreeSheetTask = nil
            }

            do {
                let bootstrap = try await worktreeFlowCoordinator.loadSheetBootstrap(
                    localRootPath: localRoot
                )
                guard !Task.isCancelled else { return }
                applyWorktreeSheetBootstrap(bootstrap)
            } catch {
                guard !Task.isCancelled else { return }
                availableLocalBranches = []
                worktreeSheetLoadState = .failed(error.localizedDescription)
                worktreeErrorMessage = error.localizedDescription
            }
        }
    }

    func startWorktreeCreationFromSheet() {
        clearWorktreeFeedback()
        guard !isWorktreeActionInFlight else { return }

        let branch = worktreeBranchDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        let mergeTarget = worktreeMergeTargetDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        let baseBranch = worktreeBaseBranchDraft.trimmingCharacters(in: .whitespacesAndNewlines)

        let localRoot = pendingWorktreeLocalRoot
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
                autoMergeOnReturn: worktreeAutoMergeOnReturn,
                deleteBranchAfterMerge: worktreeDeleteBranchAfterMerge
            )
        } catch {
            worktreeErrorMessage = error.localizedDescription
            return
        }

        isWorktreeActionInFlight = true
        worktreeStatusMessage = "Creazione worktree in corso..."
        worktreeActionTask?.cancel()
        worktreeActionTask = Task { @MainActor in
            defer {
                isWorktreeActionInFlight = false
                worktreeActionTask = nil
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
                showWorktreeSheet = false
                cancelWorktreeSheetPreparation(resetSheetState: true)
                worktreeStatusMessage = "Worktree attivo su \(outcome.session.worktreeBranch)."
            } catch {
                guard !Task.isCancelled else { return }
                worktreeErrorMessage = error.localizedDescription
            }
        }
    }
}
