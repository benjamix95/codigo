import CoderEngine
import Foundation

extension ReviewPatchWorkflowService {
    func mergePullRequestExecutionContext(
        artifact: ReviewPatchArtifact,
        safeOnly: Bool
    ) throws -> ReviewPatchMergeExecutionContext {
        let response: ReviewPatchMergeExecutionContextResponse? = ReviewCoreBridge.call(
            functionName: "review_core_patch_build_merge_execution_context",
            request: ReviewPatchMergeExecutionContextRequest(
                schemaVersion: 1,
                prURL: artifact.prURL,
                safeOnly: safeOnly
            )
        )
        guard let response else {
            throw ReviewPatchWorkflowError.pullRequestUnavailable(
                "Rust patch merge execution context runtime required but unavailable"
            )
        }
        if response.isError {
            throw ReviewPatchWorkflowError.pullRequestUnavailable(
                response.message ?? "Unable to derive patch merge execution context"
            )
        }
        guard let prURL = response.prURL,
              let firstMergeAuto = response.firstMergeAuto,
              let retryAfterConflicts = response.retryAfterConflicts,
              let retryMergeAuto = response.retryMergeAuto else {
            throw ReviewPatchWorkflowError.pullRequestUnavailable(
                "Rust patch merge execution context response was incomplete"
            )
        }
        return ReviewPatchMergeExecutionContext(
            prURL: prURL,
            firstMergeAuto: firstMergeAuto,
            retryAfterConflicts: retryAfterConflicts,
            retryMergeAuto: retryMergeAuto
        )
    }

    func resolveConflictsExecutionContext(
        artifact: ReviewPatchArtifact
    ) throws -> ReviewPatchResolveConflictsExecutionContext {
        let response: ReviewPatchResolveConflictsExecutionContextResponse? = ReviewCoreBridge.call(
            functionName: "review_core_patch_build_resolve_conflicts_context",
            request: ReviewPatchResolveConflictsExecutionContextRequest(
                schemaVersion: 1,
                worktreePath: artifact.worktreePath,
                branchName: artifact.branchName,
                baseBranchName: artifact.baseBranchName
            )
        )
        guard let response else {
            throw ReviewPatchWorkflowError.pullRequestUnavailable(
                "Rust patch resolve conflicts context runtime required but unavailable"
            )
        }
        if response.isError {
            throw ReviewPatchWorkflowError.pullRequestUnavailable(
                response.message ?? "Unable to derive patch resolve conflicts context"
            )
        }
        guard let worktreePath = response.worktreePath,
              let branchName = response.branchName,
              let baseBranchName = response.baseBranchName,
              let commitMessage = response.commitMessage else {
            throw ReviewPatchWorkflowError.pullRequestUnavailable(
                "Rust patch resolve conflicts context response was incomplete"
            )
        }
        return ReviewPatchResolveConflictsExecutionContext(
            worktreePath: worktreePath,
            branchName: branchName,
            baseBranchName: baseBranchName,
            commitMessage: commitMessage
        )
    }

    func mergePullRequest(
        artifact: ReviewPatchArtifact,
        preferredProviderId: String?,
        providerRegistry: ProviderRegistry,
        workspaceRoot: String,
        safeOnly: Bool
    ) async throws -> ReviewPatchArtifact {
        let context = try mergePullRequestExecutionContext(
            artifact: artifact,
            safeOnly: safeOnly
        )
        let prURL = context.prURL
        let gitRoot = try gitService.resolveGitRoot(from: workspaceRoot)

        do {
            try gitService.mergePullRequest(gitRoot: gitRoot, prURL: prURL, auto: context.firstMergeAuto)
            return try mergePullRequestResult(artifact: artifact)
        } catch {
            guard context.retryAfterConflicts else {
                throw ReviewPatchWorkflowError.pullRequestUnavailable(error.localizedDescription)
            }
            let resolved = try await resolveConflicts(
                artifact: artifact,
                preferredProviderId: preferredProviderId,
                providerRegistry: providerRegistry
            )
            try gitService.mergePullRequest(gitRoot: gitRoot, prURL: prURL, auto: context.retryMergeAuto)
            return try mergePullRequestResult(artifact: resolved)
        }
    }

    func resolveConflicts(
        artifact: ReviewPatchArtifact,
        preferredProviderId: String?,
        providerRegistry: ProviderRegistry
    ) async throws -> ReviewPatchArtifact {
        let context = try resolveConflictsExecutionContext(artifact: artifact)
        let worktreePath = context.worktreePath
        let branchName = context.branchName
        let baseBranch = context.baseBranchName

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
            message: context.commitMessage
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

struct ReviewPatchResolveConflictsExecutionContext {
    let worktreePath: String
    let branchName: String
    let baseBranchName: String
    let commitMessage: String
}

struct ReviewPatchMergeExecutionContext {
    let prURL: String
    let firstMergeAuto: Bool
    let retryAfterConflicts: Bool
    let retryMergeAuto: Bool
}

private struct ReviewPatchMergeResultBridgeRequest: Encodable {
    let schemaVersion: Int
    let patchId: String
    let prURL: String?
    let success: Bool
    let errorMessage: String?

    enum CodingKeys: String, CodingKey {
        case schemaVersion
        case patchId
        case prURL = "prUrl"
        case success
        case errorMessage
    }
}

private struct ReviewPatchMergeResultBridgeResponse: Decodable {
    let isError: Bool
    let message: String?
    let status: String?
    let mergeStatus: String?
    let prURL: String?
    let conflicts: [String]?

    enum CodingKeys: String, CodingKey {
        case isError
        case message
        case status
        case mergeStatus
        case prURL = "prUrl"
        case conflicts
    }
}

private struct ReviewPatchMergeExecutionContextRequest: Encodable {
    let schemaVersion: Int
    let prURL: String?
    let safeOnly: Bool

    enum CodingKeys: String, CodingKey {
        case schemaVersion
        case prURL = "prUrl"
        case safeOnly
    }
}

private struct ReviewPatchMergeExecutionContextResponse: Decodable {
    let isError: Bool
    let message: String?
    let prURL: String?
    let firstMergeAuto: Bool?
    let retryAfterConflicts: Bool?
    let retryMergeAuto: Bool?

    enum CodingKeys: String, CodingKey {
        case isError
        case message
        case prURL = "prUrl"
        case firstMergeAuto
        case retryAfterConflicts
        case retryMergeAuto
    }
}

private struct ReviewPatchResolveConflictsExecutionContextRequest: Encodable {
    let schemaVersion: Int
    let worktreePath: String?
    let branchName: String?
    let baseBranchName: String?
}

private struct ReviewPatchResolveConflictsExecutionContextResponse: Decodable {
    let isError: Bool
    let message: String?
    let worktreePath: String?
    let branchName: String?
    let baseBranchName: String?
    let commitMessage: String?
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
