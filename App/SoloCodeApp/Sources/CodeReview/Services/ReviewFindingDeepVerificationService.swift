import CoderEngine
import Foundation

/// Deep verification (Rust `review_core_verify_candidates`) before any patch preparation.
enum ReviewFindingDeepVerificationService {

    static func snapshotAfterVerification(
        snapshot: CodeReviewSessionSnapshot,
        findingId: String,
        workspaceRoot: String
    ) throws -> CodeReviewSessionSnapshot {
        let workspaceURL = URL(fileURLWithPath: workspaceRoot)
        let scopeFiles = Set((snapshot.scope?.files ?? []).map {
            $0.hasPrefix("./") ? String($0.dropFirst(2)) : $0
        })

        var candidates = snapshot.candidates
        if let index = candidates.firstIndex(where: { $0.id == findingId }) {
            let result = ReviewCandidateVerificationService.verify(
                candidate: candidates[index],
                workspacePath: workspaceURL,
                scopeFiles: scopeFiles
            )
            candidates[index].verificationStatus = result.status
            candidates[index].verificationMethod = result.method
            candidates[index].verificationReport = result.report
            candidates[index].falsePositiveReason = result.falsePositiveReason
            candidates[index].verifiedAt = result.status == .verified ? Date() : nil
            var findings = snapshot.findings
            if result.status == .verified && !findings.contains(where: { $0.id == findingId }) {
                findings.append(.fromCandidate(candidates[index]))
            }
            return snapshot.copying(
                findings: findings,
                candidates: candidates,
                events: snapshot.events + [verificationEvent(findingId: findingId, result: result)],
                outcome: snapshot.copying(findings: findings, candidates: candidates).buildOutcomeSummary()
            )
        }

        guard let fIndex = snapshot.findings.firstIndex(where: { $0.id == findingId }) else {
            return snapshot
        }
        let finding = snapshot.findings[fIndex]
        if finding.isBugConfirmedForPatchPreparation {
            return snapshot
        }

        let candidate = ReviewCandidateVerificationService.candidate(from: finding, signalType: .semantic)
            ?? ReviewCandidateVerificationService.candidate(from: finding, signalType: .pattern)
            ?? ReviewCandidateVerificationService.candidate(from: finding, signalType: .llmVerified)
            ?? ReviewCandidateVerificationService.candidate(from: finding, signalType: .manual)

        guard let candidate else {
            throw ReviewPatchWorkflowError.applyFailed(
                "Verifica profonda non disponibile: il finding non può essere adattato per il motore Rust."
            )
        }

        let result = ReviewCandidateVerificationService.verify(
            candidate: candidate,
            workspacePath: workspaceURL,
            scopeFiles: scopeFiles
        )

        var findings = snapshot.findings
        findings[fIndex] = Self.mergingFinding(finding, result: result)

        return snapshot.copying(
            findings: findings,
            events: snapshot.events + [verificationEvent(findingId: findingId, result: result)],
            outcome: snapshot.copying(findings: findings, candidates: snapshot.candidates).buildOutcomeSummary()
        )
    }

    private static func verificationEvent(
        findingId: String,
        result: ReviewCandidateVerificationResult
    ) -> CodeReviewSessionEvent {
        switch result.status {
        case .verified:
            return .candidateVerified(candidateId: findingId)
        case .rejectedFalsePositive:
            return .candidateRejected(
                candidateId: findingId,
                reason: result.falsePositiveReason ?? result.status.rawValue
            )
        default:
            return CodeReviewSessionEvent(
                type: .error,
                detail: "Verifica inconclusiva per \(findingId): \(result.report)"
            )
        }
    }

    private static func mergingFinding(
        _ finding: CodeReviewFinding,
        result: ReviewCandidateVerificationResult
    ) -> CodeReviewFinding {
        CodeReviewFinding(
            id: finding.id,
            severity: finding.severity,
            category: finding.category,
            origin: finding.origin,
            filePath: finding.filePath,
            lineNumber: finding.lineNumber,
            endLineNumber: finding.endLineNumber,
            message: finding.message,
            suggestedFix: finding.suggestedFix,
            expectedInvariant: finding.expectedInvariant,
            reproOrReasoning: finding.reproOrReasoning,
            confidence: finding.confidence,
            evidence: finding.evidence,
            sourceTool: finding.sourceTool,
            blocking: finding.blocking,
            status: finding.status,
            verificationReport: result.report,
            verifiedAt: result.status == .verified ? Date() : nil,
            verificationMethod: result.method,
            falsePositiveReason: result.falsePositiveReason,
            patchArtifactId: finding.patchArtifactId,
            comments: finding.comments,
            createdAt: finding.createdAt
        )
    }
}
