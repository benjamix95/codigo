import CoderEngine
import Foundation

/// Quando `reducePatchPrepareFailure` non restituisce uno snapshot (bridge assente, decode, ecc.),
/// aggiorna comunque il finding in Swift per non lasciare la UI in uno stato incoerente.
func snapshotApplyingPatchPrepareFailure(
    _ snapshot: CodeReviewSessionSnapshot,
    findingId: String,
    message: String
) -> CodeReviewSessionSnapshot? {
    var findings = snapshot.findings
    guard let idx = findings.firstIndex(where: { $0.id == findingId }) else { return nil }
    findings[idx].status = .patchFailed
    let note = FindingComment(
        id: "patch-prepare-failed-\(findingId)",
        author: "system",
        content: "Patch preview non disponibile: \(message)",
        createdAt: Date()
    )
    findings[idx].comments.append(note)
    return CodeReviewSessionSnapshot(
        sessionId: snapshot.sessionId,
        conversationId: snapshot.conversationId,
        mutationSequence: snapshot.mutationSequence + 1,
        phase: snapshot.phase,
        stage: snapshot.stage,
        findings: findings,
        candidates: snapshot.candidates,
        patches: snapshot.patches,
        events: snapshot.events,
        config: snapshot.config,
        scope: snapshot.scope,
        workspacePath: snapshot.workspacePath,
        currentRound: snapshot.currentRound,
        activeWorkerCount: snapshot.activeWorkerCount,
        startedAt: snapshot.startedAt,
        completedAt: snapshot.completedAt,
        analysisCompletedAt: snapshot.analysisCompletedAt,
        lastError: snapshot.lastError,
        currentJobId: snapshot.currentJobId,
        lastTestStatus: snapshot.lastTestStatus,
        audit: snapshot.audit,
        outcome: snapshot.outcome,
        verifiedFindings: snapshot.verifiedFindings,
        phaseLedger: snapshot.phaseLedger,
        fileLedger: snapshot.fileLedger,
        lastUpdatedAt: Date()
    )
}
