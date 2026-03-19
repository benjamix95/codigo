import CoderEngine
import Foundation

enum ReviewPatchWorkflowError: LocalizedError, Equatable {
    case missingWorkspace
    case reviewNotVerified
    case providerUnavailable
    case emptyDiff
    case invalidPatch
    case patchNotVerified
    case rollbackUnavailable
    case validationFailed(String)
    case applyFailed(String)
    case pullRequestUnavailable(String)

    var errorDescription: String? {
        switch self {
        case .missingWorkspace:
            return "Workspace Git non disponibile per il workflow patch review."
        case .reviewNotVerified:
            return "Il finding non è verificato e non può produrre una patch applicabile."
        case .providerUnavailable:
            return "Nessun provider agente disponibile per preparare la patch."
        case .emptyDiff:
            return "La preparazione patch non ha prodotto alcuna modifica concreta."
        case .invalidPatch:
            return "La patch salvata non è valida o non è applicabile al workspace corrente."
        case .patchNotVerified:
            return "La patch non è stata verificata con successo e non può essere applicata."
        case .rollbackUnavailable:
            return "Rollback non disponibile per questa patch."
        case .validationFailed(let message):
            return "La validation pipeline della patch ha fallito: \(message)"
        case .applyFailed(let message):
            return "Apply patch fallito: \(message)"
        case .pullRequestUnavailable(let message):
            return "Impossibile aprire o mergeare la PR: \(message)"
        }
    }
}

@MainActor
final class ReviewPatchWorkflowService {
    let gitService = GitService()
    let mergeAIService = WorktreeMergeAIService()

    func preparePatch(
        finding: CodeReviewFinding,
        snapshot: CodeReviewSessionSnapshot,
        preferredProviderId: String?,
        providerRegistry: ProviderRegistry,
        workspaceRoot: String
    ) async throws -> ReviewPatchArtifact {
        guard finding.verifiedAt != nil || finding.verificationReport != nil else {
            throw ReviewPatchWorkflowError.reviewNotVerified
        }
        let prepareContext = try preparePatchContext(
            finding: finding,
            snapshot: snapshot
        )

        let gitRoot = try gitService.resolveGitRoot(from: workspaceRoot)
        let baseBranch = try gitService.currentBranch(gitRoot: gitRoot)
        let branchName = prepareContext.branchName
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

        let provider = try mergeAIService.resolveProvider(
            preferredProviderId: preferredProviderId,
            providerRegistry: providerRegistry
        )

        _ = try await mergeAIService.runHeadlessPrompt(
            provider: provider,
            gitRoot: worktreePath,
            prompt: prepareContext.prompt
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
        let artifact = try prepareDraftArtifact(
            finding: finding,
            patchText: patchText,
            touchedFiles: touchedFiles,
            baseBranchName: baseBranch
        )
        let validated = try await validatePreparedArtifact(
            artifact,
            workspaceRoot: worktreePath,
            trigger: .reviewPatchPreview,
            workspaceContainsPatch: true
        )
        return validated
    }

    func preparePatchPrompt(
        finding: CodeReviewFinding,
        snapshot: CodeReviewSessionSnapshot
    ) throws -> String {
        try preparePatchContext(finding: finding, snapshot: snapshot).prompt
    }

    func verifyPatch(
        artifact: ReviewPatchArtifact,
        workspaceRoot: String
    ) async throws -> ReviewPatchArtifact {
        guard artifact.validationStatus == .passed else {
            throw ReviewPatchWorkflowError.validationFailed(
                artifact.validationSummary ?? "validation status non passed"
            )
        }
        let gitRoot = try gitService.resolveGitRoot(from: workspaceRoot)
        let patchFile = try writePatchTempFile(artifact.patchText, prefix: artifact.id)
        defer { try? FileManager.default.removeItem(at: patchFile) }

        do {
            _ = try gitService.runGit(["apply", "--check", patchFile.path], gitRoot: gitRoot)
        } catch {
            return try verifyPatchResult(
                artifact: artifact,
                checkPassed: false,
                failureMessage: error.localizedDescription
            )
        }

        return try verifyPatchResult(
            artifact: artifact,
            checkPassed: true,
            failureMessage: nil
        )
    }

    func verifyPatchResult(
        artifact: ReviewPatchArtifact,
        checkPassed: Bool,
        failureMessage: String?
    ) throws -> ReviewPatchArtifact {
        let response: ReviewPatchVerifyResultBridgeResponse? = ReviewCoreBridge.call(
            functionName: "review_core_patch_build_verify_result",
            request: ReviewPatchVerifyResultBridgeRequest(
                schemaVersion: 1,
                patchId: artifact.id,
                findingId: artifact.findingId,
                success: checkPassed,
                errorMessage: failureMessage
            )
        )
        guard let response else {
            throw ReviewPatchWorkflowError.applyFailed(
                "Rust patch verify result runtime required but unavailable"
            )
        }
        if response.isError {
            throw ReviewPatchWorkflowError.applyFailed(
                response.message ?? "Unable to derive patch verify result"
            )
        }
        guard let statusRaw = response.status,
              let status = ReviewPatchStatus(rawValue: statusRaw),
              let verifyStatusRaw = response.verifyStatus,
              let verifyStatus = ReviewPatchVerifyStatus(rawValue: verifyStatusRaw) else {
            throw ReviewPatchWorkflowError.applyFailed(
                "Rust patch verify result response was incomplete"
            )
        }

        var updated = artifact
        updated.status = status
        updated.verifyStatus = verifyStatus
        updated.conflicts = response.conflicts ?? []
        updated.applyMessage = response.applyMessage
        updated.updatedAt = Date()
        return updated
    }

    func openPullRequest(
        artifact: ReviewPatchArtifact,
        title: String,
        body: String?,
        workspaceRoot: String
    ) throws -> ReviewPatchArtifact {
        let gitRoot = try gitService.resolveGitRoot(from: workspaceRoot)
        let currentBranch = try gitService.currentBranch(gitRoot: gitRoot)
        let executionContext = try openPullRequestExecutionContext(
            artifact: artifact,
            currentBranchName: currentBranch
        )
        let baseBranch = executionContext.baseBranchName
        let branchName = executionContext.branchName
        let worktreePath = executionContext.worktreePath

        try? gitService.removeWorktree(gitRoot: gitRoot, worktreePath: worktreePath, force: true)
        try? gitService.deleteBranch(name: branchName, gitRoot: gitRoot, force: true)
        try gitService.createWorktree(gitRoot: gitRoot, branchName: branchName, fromBranch: baseBranch, worktreePath: worktreePath)

        let patchFile = try writePatchTempFile(artifact.patchText, prefix: artifact.id)
        defer { try? FileManager.default.removeItem(at: patchFile) }
        do {
            _ = try gitService.runGit(["apply", "--3way", "--whitespace=nowarn", patchFile.path], gitRoot: worktreePath)
            try gitService.autoCommitAllChanges(gitRoot: worktreePath, message: title)
            try gitService.push(gitRoot: worktreePath, branch: branchName)
            let pr = try gitService.createPullRequest(gitRoot: worktreePath, base: baseBranch, title: title, body: body)
            return try openPullRequestResult(
                artifact: artifact,
                branchName: branchName,
                baseBranchName: baseBranch,
                worktreePath: worktreePath,
                prURL: pr.url
            )
        } catch {
            throw ReviewPatchWorkflowError.pullRequestUnavailable(error.localizedDescription)
        }
    }

    func openPullRequestResult(
        artifact: ReviewPatchArtifact,
        branchName: String,
        baseBranchName: String,
        worktreePath: String,
        prURL: String
    ) throws -> ReviewPatchArtifact {
        let response: ReviewPatchOpenPrResultBridgeResponse? = ReviewCoreBridge.call(
            functionName: "review_core_patch_build_open_pr_result",
            request: ReviewPatchOpenPrResultBridgeRequest(
                schemaVersion: 1,
                patchId: artifact.id,
                branchName: branchName,
                baseBranchName: baseBranchName,
                worktreePath: worktreePath,
                prURL: prURL
            )
        )
        guard let response else {
            throw ReviewPatchWorkflowError.pullRequestUnavailable(
                "Rust patch open pr result runtime required but unavailable"
            )
        }
        if response.isError {
            throw ReviewPatchWorkflowError.pullRequestUnavailable(
                response.message ?? "Unable to derive patch open pr result"
            )
        }
        guard let statusRaw = response.status,
              let status = ReviewPatchStatus(rawValue: statusRaw),
              let prStatusRaw = response.prStatus,
              let prStatus = ReviewPatchPRStatus(rawValue: prStatusRaw),
              let resolvedBranchName = response.branchName,
              let resolvedBaseBranchName = response.baseBranchName,
              let resolvedWorktreePath = response.worktreePath,
              let resolvedPrURL = response.prURL else {
            throw ReviewPatchWorkflowError.pullRequestUnavailable(
                "Rust patch open pr result response was incomplete"
            )
        }

        var opened = artifact
        opened.branchName = resolvedBranchName
        opened.baseBranchName = resolvedBaseBranchName
        opened.worktreePath = resolvedWorktreePath
        opened.prURL = resolvedPrURL
        opened.prStatus = prStatus
        opened.status = status
        opened.updatedAt = Date()
        return opened
    }

    func writePatchTempFile(_ patchText: String, prefix: String) throws -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("\(prefix)-\(UUID().uuidString).patch")
        try patchText.write(to: url, atomically: true, encoding: .utf8)
        return url
    }
}

private struct ReviewPatchVerifyResultBridgeRequest: Encodable {
    let schemaVersion: Int
    let patchId: String
    let findingId: String
    let success: Bool
    let errorMessage: String?
}

private struct ReviewPatchVerifyResultBridgeResponse: Decodable {
    let isError: Bool
    let message: String?
    let status: String?
    let verifyStatus: String?
    let conflicts: [String]?
    let applyMessage: String?
}

private struct ReviewPatchOpenPrResultBridgeRequest: Encodable {
    let schemaVersion: Int
    let patchId: String
    let branchName: String
    let baseBranchName: String
    let worktreePath: String
    let prURL: String

    enum CodingKeys: String, CodingKey {
        case schemaVersion
        case patchId
        case branchName
        case baseBranchName
        case worktreePath
        case prURL = "prUrl"
    }
}

private struct ReviewPatchOpenPrResultBridgeResponse: Decodable {
    let isError: Bool
    let message: String?
    let status: String?
    let prStatus: String?
    let branchName: String?
    let baseBranchName: String?
    let worktreePath: String?
    let prURL: String?

    enum CodingKeys: String, CodingKey {
        case isError
        case message
        case status
        case prStatus
        case branchName
        case baseBranchName
        case worktreePath
        case prURL = "prUrl"
    }
}
