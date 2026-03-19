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
            return try mergePullRequestResult(artifact: artifact)
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
            return try mergePullRequestResult(artifact: resolved)
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

        return try resolveConflictsResult(artifact: artifact)
    }

    func mergePullRequestResult(
        artifact: ReviewPatchArtifact
    ) throws -> ReviewPatchArtifact {
        let response: ReviewPatchMergeResultBridgeResponse? = ReviewCoreBridge.call(
            functionName: "review_core_patch_build_merge_result",
            request: ReviewPatchMergeResultBridgeRequest(
                schemaVersion: 1,
                patchId: artifact.id,
                prURL: artifact.prURL,
                success: true,
                errorMessage: nil
            )
        )
        guard let response else {
            throw ReviewPatchWorkflowError.pullRequestUnavailable(
                "Rust patch merge result runtime required but unavailable"
            )
        }
        if response.isError {
            throw ReviewPatchWorkflowError.pullRequestUnavailable(
                response.message ?? "Unable to derive patch merge result"
            )
        }
        guard let statusRaw = response.status,
              let status = ReviewPatchStatus(rawValue: statusRaw),
              let mergeStatusRaw = response.mergeStatus,
              let mergeStatus = ReviewPatchMergeStatus(rawValue: mergeStatusRaw) else {
            throw ReviewPatchWorkflowError.pullRequestUnavailable(
                "Rust patch merge result response was incomplete"
            )
        }
        var merged = artifact
        merged.status = status
        merged.mergeStatus = mergeStatus
        merged.prURL = response.prURL ?? artifact.prURL
        merged.conflicts = response.conflicts ?? []
        merged.updatedAt = Date()
        return merged
    }

    func resolveConflictsResult(
        artifact: ReviewPatchArtifact
    ) throws -> ReviewPatchArtifact {
        let response: ReviewPatchResolveConflictsResultBridgeResponse? = ReviewCoreBridge.call(
            functionName: "review_core_patch_build_resolve_conflicts_result",
            request: ReviewPatchResolveConflictsResultBridgeRequest(
                schemaVersion: 1,
                patchId: artifact.id
            )
        )
        guard let response else {
            throw ReviewPatchWorkflowError.pullRequestUnavailable(
                "Rust patch resolve conflicts result runtime required but unavailable"
            )
        }
        if response.isError {
            throw ReviewPatchWorkflowError.pullRequestUnavailable(
                response.message ?? "Unable to derive patch resolve conflicts result"
            )
        }
        guard let statusRaw = response.status,
              let status = ReviewPatchStatus(rawValue: statusRaw),
              let mergeStatusRaw = response.mergeStatus,
              let mergeStatus = ReviewPatchMergeStatus(rawValue: mergeStatusRaw) else {
            throw ReviewPatchWorkflowError.pullRequestUnavailable(
                "Rust patch resolve conflicts result response was incomplete"
            )
        }
        var updated = artifact
        updated.conflicts = response.conflicts ?? []
        updated.status = status
        updated.mergeStatus = mergeStatus
        updated.updatedAt = Date()
        return updated
    }
}

private struct ReviewPatchMergeResultBridgeRequest: Encodable {
    let schemaVersion: Int
    let patchId: String
    let prURL: String?
    let success: Bool
    let errorMessage: String?
}

private struct ReviewPatchMergeResultBridgeResponse: Decodable {
    let isError: Bool
    let message: String?
    let status: String?
    let mergeStatus: String?
    let prURL: String?
    let conflicts: [String]?
}

private struct ReviewPatchResolveConflictsResultBridgeRequest: Encodable {
    let schemaVersion: Int
    let patchId: String
}

private struct ReviewPatchResolveConflictsResultBridgeResponse: Decodable {
    let isError: Bool
    let message: String?
    let status: String?
    let mergeStatus: String?
    let conflicts: [String]?
}
