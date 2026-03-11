import CoderEngine
import Foundation

extension ReviewPatchWorkflowService {
    func preparePatch(
        finding: CodeReviewFinding,
        snapshot: CodeReviewSessionSnapshot,
        executionProvider: any LLMProvider,
        workspaceRoot: String
    ) async throws -> ReviewPatchArtifact {
        guard finding.verifiedAt != nil || finding.verificationReport != nil else {
            throw ReviewPatchWorkflowError.reviewNotVerified
        }

        let gitRoot = try gitService.resolveGitRoot(from: workspaceRoot)
        let baseBranch = try gitService.currentBranch(gitRoot: gitRoot)
        let branchName = "codex/review-patch-\(String(finding.id.prefix(8)).lowercased())"
        let worktreePath = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("codigo-review-patches")
            .appendingPathComponent(branchName.replacingOccurrences(of: "/", with: "-"))
            .path

        try? gitService.removeWorktree(gitRoot: gitRoot, worktreePath: worktreePath, force: true)
        try? gitService.deleteBranch(name: branchName, gitRoot: gitRoot, force: true)
        try gitService.createWorktree(
            gitRoot: gitRoot,
            branchName: branchName,
            fromBranch: baseBranch,
            worktreePath: worktreePath
        )
        defer {
            try? gitService.removeWorktree(gitRoot: gitRoot, worktreePath: worktreePath, force: true)
            try? gitService.deleteBranch(name: branchName, gitRoot: gitRoot, force: true)
        }

        let prompt = preparePatchPrompt(
            finding: finding,
            snapshot: snapshot
        )

        _ = try await mergeAIService.runHeadlessPrompt(
            provider: executionProvider,
            gitRoot: worktreePath,
            prompt: prompt
        )

        let patchText = try gitService.runGit(["diff", "--no-ext-diff"], gitRoot: worktreePath)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !patchText.isEmpty else {
            throw ReviewPatchWorkflowError.emptyDiff
        }

        let touchedFiles = try gitService.runGit(["diff", "--name-only"], gitRoot: worktreePath)
            .split(separator: "\n")
            .map(String.init)
            .filter { !$0.isEmpty }
        let riskScore = patchRiskScore(patchText: patchText, touchedFiles: touchedFiles)
        let preview = String(patchText.prefix(12_000))
        let artifact = ReviewPatchArtifact(
            findingId: finding.id,
            patchText: patchText,
            diffPreview: preview,
            touchedFiles: touchedFiles,
            riskScore: riskScore,
            status: .draft,
            verifyStatus: .pending,
            prStatus: .notRequested,
            mergeStatus: .notRequested,
            baseBranchName: baseBranch,
            verificationReport: finding.verificationReport
        )
        return try await validatePreparedArtifact(
            artifact,
            workspaceRoot: worktreePath,
            trigger: .reviewPatchPreview,
            workspaceContainsPatch: true
        )
    }
}
