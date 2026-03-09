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

        let provider = try mergeAIService.resolveProvider(
            preferredProviderId: preferredProviderId,
            providerRegistry: providerRegistry
        )

        let prompt = """
        Sei in una worktree temporanea creata solo per preparare una patch preview.
        Devi modificare i file target e fermarti senza fare commit.

        Sessione review: \(snapshot.sessionId)
        Finding: \(finding.id)
        File: \(finding.filePath)
        Riga: \(finding.lineNumber.map(String.init) ?? "n/a")
        Messaggio: \(finding.message)
        Verifica: \(finding.verificationReport ?? "n/a")
        Fix suggerito: \(finding.suggestedFix ?? "n/a")

        Regole:
        - modifica solo i file strettamente necessari a risolvere questo finding;
        - mantieni il patch set minimo e leggibile;
        - non fare commit, push o merge;
        - non introdurre refactor estranei;
        - al termine lascia le modifiche nel worktree e fermati.
        """

        _ = try await mergeAIService.runHeadlessPrompt(
            provider: provider,
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
        let validated = try await validatePreparedArtifact(
            artifact,
            workspaceRoot: worktreePath,
            trigger: .reviewPatchPreview,
            workspaceContainsPatch: true
        )
        return validated
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
            var failed = artifact
            failed.verifyStatus = .failed
            failed.status = .conflict
            failed.conflicts = [error.localizedDescription]
            failed.applyMessage = error.localizedDescription
            failed.updatedAt = Date()
            return failed
        }

        var verified = artifact
        verified.verifyStatus = .verified
        verified.status = .verified
        verified.updatedAt = Date()
        return verified
    }

    func applyPatch(
        artifact: ReviewPatchArtifact,
        workspaceRoot: String
    ) async throws -> ReviewPatchArtifact {
        guard artifact.verifyStatus == .verified else {
            throw ReviewPatchWorkflowError.patchNotVerified
        }
        let gitRoot = try gitService.resolveGitRoot(from: workspaceRoot)
        let patchFile = try writePatchTempFile(artifact.patchText, prefix: artifact.id)
        defer { try? FileManager.default.removeItem(at: patchFile) }

        do {
            _ = try gitService.runGit(["apply", "--3way", "--whitespace=nowarn", patchFile.path], gitRoot: gitRoot)
            let validation = try await runValidation(
                trigger: .reviewPatchApply,
                workspaceRoot: gitRoot,
                touchedFiles: artifact.touchedFiles,
                patchText: artifact.patchText,
                workspaceContainsPatch: true
            )
            guard validation.status == .passed else {
                _ = try? gitService.runGit(["apply", "-R", "--3way", patchFile.path], gitRoot: gitRoot)
                throw ReviewPatchWorkflowError.validationFailed(validation.summaryLine)
            }
            var applied = artifact
            applied.status = .applied
            applied.verifyStatus = .verified
            applied.validationRunId = validation.runId
            applied.validationStatus = validation.status
            applied.validationSummary = ValidationReportFormatter.summary(for: validation)
            applied.rollbackRef = "reverse:\(artifact.id)"
            applied.applyMessage = applied.validationSummary
            applied.updatedAt = Date()
            return applied
        } catch {
            _ = try? gitService.runGit(["apply", "-R", "--3way", patchFile.path], gitRoot: gitRoot)
            throw ReviewPatchWorkflowError.applyFailed(error.localizedDescription)
        }
    }

    func revalidatePatch(
        artifact: ReviewPatchArtifact,
        workspaceRoot: String
    ) async throws -> ReviewPatchArtifact {
        guard artifact.status == .applied else {
            throw ReviewPatchWorkflowError.applyFailed("La patch non risulta applicata nel workspace corrente.")
        }
        let gitRoot = try gitService.resolveGitRoot(from: workspaceRoot)
        let validation = try await runValidation(
            trigger: .reviewPatchApply,
            workspaceRoot: gitRoot,
            touchedFiles: artifact.touchedFiles,
            patchText: nil,
            workspaceContainsPatch: true
        )
        var updated = artifact
        updated.validationRunId = validation.runId
        updated.validationStatus = validation.status
        updated.validationSummary = ValidationReportFormatter.summary(for: validation)
        updated.applyMessage = updated.validationSummary
        updated.status = validation.status == .passed ? .applied : .applyFailed
        updated.updatedAt = Date()
        return updated
    }

    func rollbackPatch(
        artifact: ReviewPatchArtifact,
        workspaceRoot: String
    ) async throws -> ReviewPatchArtifact {
        guard artifact.status == .applied else {
            throw ReviewPatchWorkflowError.rollbackUnavailable
        }
        guard artifact.rollbackRef != nil else {
            throw ReviewPatchWorkflowError.rollbackUnavailable
        }
        let gitRoot = try gitService.resolveGitRoot(from: workspaceRoot)
        let patchFile = try writePatchTempFile(artifact.patchText, prefix: "\(artifact.id)-rollback")
        defer { try? FileManager.default.removeItem(at: patchFile) }

        do {
            _ = try gitService.runGit(["apply", "-R", "--3way", "--whitespace=nowarn", patchFile.path], gitRoot: gitRoot)
            var rolledBack = artifact
            rolledBack.status = .rolledBack
            rolledBack.applyMessage = "Rollback applied successfully"
            rolledBack.updatedAt = Date()
            return rolledBack
        } catch {
            throw ReviewPatchWorkflowError.applyFailed("Rollback fallito: \(error.localizedDescription)")
        }
    }

    func openPullRequest(
        artifact: ReviewPatchArtifact,
        title: String,
        body: String?,
        workspaceRoot: String
    ) throws -> ReviewPatchArtifact {
        let gitRoot = try gitService.resolveGitRoot(from: workspaceRoot)
        let baseBranch: String
        if let artifactBaseBranch = artifact.baseBranchName, !artifactBaseBranch.isEmpty {
            baseBranch = artifactBaseBranch
        } else {
            baseBranch = try gitService.currentBranch(gitRoot: gitRoot)
        }
        let branchName = artifact.branchName ?? "codex/review-pr-\(String(artifact.findingId.prefix(8)).lowercased())"
        let worktreePath = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("codigo-review-prs")
            .appendingPathComponent(branchName.replacingOccurrences(of: "/", with: "-"))
            .path

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
            var opened = artifact
            opened.branchName = branchName
            opened.baseBranchName = baseBranch
            opened.worktreePath = worktreePath
            opened.prURL = pr.url
            opened.prStatus = .opened
            opened.status = .prOpened
            opened.updatedAt = Date()
            return opened
        } catch {
            throw ReviewPatchWorkflowError.pullRequestUnavailable(error.localizedDescription)
        }
    }

    private func patchRiskScore(patchText: String, touchedFiles: [String]) -> Double {
        let changedLines = patchText.components(separatedBy: .newlines).filter {
            ($0.hasPrefix("+") || $0.hasPrefix("-")) && !$0.hasPrefix("+++") && !$0.hasPrefix("---")
        }.count
        let scorer = PatchRiskScorer()
        return scorer.score(from: PatchRiskInput(filesChanged: touchedFiles.count, linesChanged: changedLines))
    }

    func writePatchTempFile(_ patchText: String, prefix: String) throws -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("\(prefix)-\(UUID().uuidString).patch")
        try patchText.write(to: url, atomically: true, encoding: .utf8)
        return url
    }
}
