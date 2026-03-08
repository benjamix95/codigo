import CoderEngine
import Foundation

extension ReviewPatchWorkflowService {
    func mergePullRequest(
        artifact: ReviewPatchArtifact,
        preferredProviderId: String?,
        providerRegistry: ProviderRegistry,
        workspaceRoot: String,
        safeOnly: Bool
    ) async throws -> ReviewPatchArtifact {
        guard let prURL = artifact.prURL else {
            throw ReviewPatchWorkflowError.pullRequestUnavailable("PR non presente sull'artefatto patch.")
        }
        let gitRoot = try gitService.resolveGitRoot(from: workspaceRoot)

        do {
            try gitService.mergePullRequest(gitRoot: gitRoot, prURL: prURL, auto: safeOnly)
            var merged = artifact
            merged.status = .merged
            merged.mergeStatus = .merged
            merged.updatedAt = Date()
            return merged
        } catch {
            guard safeOnly else {
                throw ReviewPatchWorkflowError.pullRequestUnavailable(error.localizedDescription)
            }
            let resolved = try await resolveConflicts(
                artifact: artifact,
                preferredProviderId: preferredProviderId,
                providerRegistry: providerRegistry
            )
            try gitService.mergePullRequest(gitRoot: gitRoot, prURL: prURL, auto: false)
            var merged = resolved
            merged.status = .merged
            merged.mergeStatus = .merged
            merged.updatedAt = Date()
            return merged
        }
    }

    func resolveConflicts(
        artifact: ReviewPatchArtifact,
        preferredProviderId: String?,
        providerRegistry: ProviderRegistry
    ) async throws -> ReviewPatchArtifact {
        guard let worktreePath = artifact.worktreePath,
              let branchName = artifact.branchName,
              let baseBranch = artifact.baseBranchName else {
            throw ReviewPatchWorkflowError.pullRequestUnavailable("Worktree o branch mancanti per la risoluzione conflitti.")
        }

        let start = try gitService.startNoCommitMerge(
            sourceBranch: baseBranch,
            intoTarget: branchName,
            gitRoot: worktreePath
        )
        if start.hadConflicts {
            let conflictedFiles = try gitService.listConflictedFiles(gitRoot: worktreePath)
            _ = try await mergeAIService.resolveConflictsAndFixTests(
                gitRoot: worktreePath,
                sourceBranch: baseBranch,
                targetBranch: branchName,
                conflictedFiles: conflictedFiles,
                preferredProviderId: preferredProviderId,
                providerRegistry: providerRegistry,
                maxFixRounds: 2
            )
        }

        try gitService.finalizeMergeCommit(
            gitRoot: worktreePath,
            message: "chore(review): sync \(branchName) with \(baseBranch)"
        )
        try gitService.push(gitRoot: worktreePath, branch: branchName)

        var updated = artifact
        updated.conflicts = []
        updated.status = .verified
        updated.mergeStatus = .pending
        updated.updatedAt = Date()
        return updated
    }
}
