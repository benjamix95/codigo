import CoderEngine
import Foundation

extension CodeReviewPanelStore {
    /// Runs Rust-backed deep verification for a candidate or an existing finding (before any patch work).
    func verifyFindingDeepAnalysis(sessionId: String, findingId: String) async {
        guard let workspaceRoot = workspaceStore.activeWorkspacePaths.first?.path else {
            await markPatchFailure(
                sessionId: sessionId,
                findingId: findingId,
                message: ReviewPatchWorkflowError.missingWorkspace.localizedDescription
            )
            return
        }
        guard let snapshot = taskActivityStore.codeReviewSnapshot(
            sessionId: sessionId,
            conversationId: conversationId
        ),
              snapshot.findings.contains(where: { $0.id == findingId })
              || snapshot.candidates.contains(where: { $0.id == findingId }) else {
            return
        }

        do {
            let updated = try ReviewFindingDeepVerificationService.snapshotAfterVerification(
                snapshot: snapshot,
                findingId: findingId,
                workspaceRoot: workspaceRoot
            )
            await ingestUpdatedPatchSnapshot(updated)
            if let finding = updated.findings.first(where: { $0.id == findingId }) {
                let title = finding.isBugConfirmedForPatchPreparation
                    ? "Bug confermato"
                    : "Verifica completata"
                let detail = finding.isBugConfirmedForPatchPreparation
                    ? "Analisi profonda OK. Puoi ora usare «Prepare Patch» per generare il diff."
                    : (finding.verificationReport
                        ?? "Il problema non risulta confermato come bug reale; non preparare patch finché non rientra nei criteri.")
                appendVerifiedFindingSystemMessage(
                    sessionId: sessionId,
                    findingId: findingId,
                    title: title,
                    detail: String(detail.prefix(2000)),
                    selectChatTab: false
                )
            }
        } catch {
            await markPatchFailure(
                sessionId: sessionId,
                findingId: findingId,
                message: error.localizedDescription
            )
        }
    }
}
