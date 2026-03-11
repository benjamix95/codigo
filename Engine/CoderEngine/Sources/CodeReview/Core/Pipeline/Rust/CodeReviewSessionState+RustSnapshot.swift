import Foundation

extension CodeReviewSessionState {
    func replaceCanonicalSnapshot(_ snapshot: CodeReviewSessionSnapshot) {
        guard snapshot.sessionId == sessionId else { return }
        mutationSequence = snapshot.mutationSequence
        phase = snapshot.phase
        stage = snapshot.stage
        findings = snapshot.findings
        candidates = snapshot.candidates
        patches = snapshot.patches
        events = snapshot.events
        config = snapshot.config
        scope = snapshot.scope
        workspacePath = snapshot.workspacePath
        currentRound = snapshot.currentRound
        activeWorkerCount = snapshot.activeWorkerCount
        startedAt = snapshot.startedAt
        completedAt = snapshot.completedAt
        analysisCompletedAt = snapshot.analysisCompletedAt
        lastError = snapshot.lastError
        currentJobId = snapshot.currentJobId
        lastTestStatus = snapshot.lastTestStatus
        audit = snapshot.audit
        outcome = snapshot.outcome
        if let handler = onStateChange {
            Task { @MainActor in handler(snapshot) }
        }
    }
}
