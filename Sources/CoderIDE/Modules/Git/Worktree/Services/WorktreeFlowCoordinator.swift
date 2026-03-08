import Foundation

struct WorktreeFlowCoordinator {
    private let gitService: GitService
    private let router: any WorktreeConversationRouting

    init(
        gitService: GitService,
        router: any WorktreeConversationRouting
    ) {
        self.gitService = gitService
        self.router = router
    }

    func loadSheetBootstrap(
        localRootPath: String
    ) async throws -> WorktreeSheetBootstrap {
        let trimmedRoot = localRootPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedRoot.isEmpty else {
            throw WorktreeFlowError.preloadFailed("Root locale non disponibile.")
        }

        do {
            return try await Task.detached(priority: .userInitiated) {
                let localBranches = try gitService.listLocalBranches(gitRoot: trimmedRoot)
                let currentBranch = try gitService.currentBranch(gitRoot: trimmedRoot)
                let mergeTarget = localBranches.contains(where: { $0.name == currentBranch })
                    ? currentBranch
                    : (localBranches.first?.name ?? currentBranch)
                return WorktreeSheetBootstrap(
                    localRootPath: trimmedRoot,
                    localBranches: localBranches,
                    currentBranch: currentBranch,
                    suggestedBaseBranch: currentBranch,
                    suggestedMergeTargetBranch: mergeTarget,
                    suggestedWorktreeBranch: makeDefaultWorktreeBranchName(baseBranch: currentBranch)
                )
            }.value
        } catch {
            throw WorktreeFlowError.preloadFailed(error.localizedDescription)
        }
    }

    func validateCreateInput(
        conversationId: UUID?,
        localRootPath: String?,
        worktreeBranch: String,
        baseBranch: String,
        mergeTargetBranch: String,
        worktreePath: String,
        autoMergeOnReturn: Bool,
        deleteBranchAfterMerge: Bool
    ) throws -> WorktreeCreateFlowInput {
        guard let conversationId else {
            throw WorktreeFlowError.validationFailed("Nessuna conversazione selezionata.")
        }
        guard let localRootPath else {
            throw WorktreeFlowError.validationFailed("Root locale non disponibile.")
        }

        do {
            return WorktreeCreateFlowInput(
                conversationId: conversationId,
                localRootPath: try gitService.resolveGitRoot(from: localRootPath),
                worktreePath: normalizedPath(worktreePath),
                worktreeBranch: try validatedGitRef(worktreeBranch, label: "branch worktree"),
                baseBranch: try validatedGitRef(baseBranch, label: "branch base"),
                mergeTargetBranch: try validatedGitRef(mergeTargetBranch, label: "branch target merge"),
                autoMergeOnReturn: autoMergeOnReturn,
                deleteBranchAfterMerge: deleteBranchAfterMerge
            )
        } catch {
            throw WorktreeFlowError.validationFailed(error.localizedDescription)
        }
    }

    @MainActor
    func createAndSwitch(
        input: WorktreeCreateFlowInput,
        chatStore: ChatStore,
        projectContextStore: ProjectContextStore,
        workspaceStore: WorkspaceStore,
        persistSession: (WorktreeSession) -> Void
    ) async throws -> WorktreeCreationOutcome {
        do {
            try await Task.detached(priority: .userInitiated) {
                try gitService.ensureBranchExists(name: input.mergeTargetBranch, gitRoot: input.localRootPath)
                try gitService.createWorktree(
                    request: GitWorktreeCreateRequest(
                        gitRoot: input.localRootPath,
                        branchName: input.worktreeBranch,
                        fromBranch: input.baseBranch,
                        worktreePath: input.worktreePath
                    )
                )
            }.value
        } catch let error as WorktreeFlowError {
            throw error
        } catch {
            throw WorktreeFlowError.validationFailed(error.localizedDescription)
        }

        let session = WorktreeSession(
            conversationId: input.conversationId,
            localRootPath: input.localRootPath,
            worktreePath: input.worktreePath,
            worktreeBranch: input.worktreeBranch,
            baseBranch: input.baseBranch,
            mergeTargetBranch: input.mergeTargetBranch,
            autoMergeOnReturn: input.autoMergeOnReturn,
            deleteBranchAfterMerge: input.deleteBranchAfterMerge
        )

        do {
            try router.switchConversation(
                conversationId: input.conversationId,
                toProjectPath: input.worktreePath,
                chatStore: chatStore,
                projectContextStore: projectContextStore,
                workspaceStore: workspaceStore
            )
            persistSession(session)
            return WorktreeCreationOutcome(
                session: session,
                rollbackPerformed: false,
                didSwitchContext: true
            )
        } catch {
            let rollbackPerformed = await rollbackFailedCreation(input: input)
            throw WorktreeFlowError.switchFailedAfterCreate(
                reason: "Impossibile passare al worktree creato: \(error.localizedDescription)",
                rollbackPerformed: rollbackPerformed
            )
        }
    }

    private func rollbackFailedCreation(input: WorktreeCreateFlowInput) async -> Bool {
        do {
            return try await Task.detached(priority: .utility) {
            var rollbackErrors: [Error] = []

            do {
                try gitService.removeWorktree(
                    gitRoot: input.localRootPath,
                    worktreePath: input.worktreePath,
                    force: true
                )
            } catch {
                rollbackErrors.append(error)
            }

            do {
                if try gitService.branchExists(name: input.worktreeBranch, gitRoot: input.localRootPath) {
                    try gitService.deleteBranch(
                        name: input.worktreeBranch,
                        gitRoot: input.localRootPath,
                        force: true
                    )
                }
            } catch {
                rollbackErrors.append(error)
            }

            if !rollbackErrors.isEmpty {
                throw rollbackErrors[0]
            }
            return true
            }.value
        } catch {
            return false
        }
    }

    private func normalizedPath(_ path: String) -> String {
        URL(fileURLWithPath: path)
            .standardizedFileURL
            .path(percentEncoded: false)
    }
}

@MainActor
extension WorktreeFlowCoordinator {
    init(gitService: GitService = GitService()) {
        self.init(
            gitService: gitService,
            router: DefaultWorktreeConversationRouter()
        )
    }
}
