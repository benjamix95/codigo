import CoderEngine
import Foundation

extension PipelineIntegrationService {
    func upsertInlineReviewFindingSession(
        _ payload: ReviewFindingPayload,
        for conversationId: UUID
    ) {
        let sessionId = inlineReviewSessionId(for: conversationId)
        let existing = taskActivityStore?.codeReviewSnapshot(
            sessionId: sessionId,
            conversationId: conversationId
        )
        let finding = syntheticReviewFinding(from: payload)
        var findings = existing?.findings ?? []
        if let index = findings.firstIndex(where: { $0.id == finding.id }) {
            findings[index] = finding
        } else {
            findings.append(finding)
        }

        let event = CodeReviewSessionEvent.findingAdded(
            findingId: finding.id,
            severity: finding.severity.rawValue,
            filePath: finding.filePath
        )
        let phase: ReviewSessionPhase = isRunning(for: conversationId) ? .analyzing : .completed
        let stage: ReviewSessionStage = phase == .completed ? .findings : .analysis

        let snapshot = CodeReviewSessionSnapshot(
            sessionId: sessionId,
            conversationId: conversationId,
            mutationSequence: (existing?.mutationSequence ?? 0) + 1,
            phase: phase,
            stage: stage,
            findings: findings,
            candidates: existing?.candidates ?? [],
            patches: existing?.patches ?? [],
            events: (existing?.events ?? []) + [event],
            config: existing?.config ?? .default,
            scope: existing?.scope ?? ReviewSessionScope(type: .uncommitted, files: Array(Set(findings.map(\.filePath))).sorted()),
            workspacePath: existing?.workspacePath,
            currentRound: existing?.currentRound ?? 0,
            activeWorkerCount: existing?.activeWorkerCount ?? 0,
            startedAt: existing?.startedAt ?? Date(),
            completedAt: phase == .completed ? Date() : existing?.completedAt,
            analysisCompletedAt: existing?.analysisCompletedAt,
            lastError: existing?.lastError,
            currentJobId: payload.jobId,
            lastTestStatus: existing?.lastTestStatus,
            audit: existing?.audit ?? .empty,
            outcome: ReviewSessionOutcome.empty,
            verifiedFindings: nil,
            lastUpdatedAt: Date()
        )
        let synchronized = VerifiedFindingsSessionSyncService.sync(
            snapshot: snapshot,
            existingEnvelope: existing?.verifiedFindings,
            entryPoint: .mainChat
        )
        let persisted = snapshot.copying(
            outcome: snapshot.copying(findings: findings).buildOutcomeSummary(),
            verifiedFindings: synchronized
        )
        taskActivityStore?.ingestCodeReviewSnapshot(
            persisted,
            conversationId: conversationId
        )
    }

    private func inlineReviewSessionId(for conversationId: UUID) -> String {
        "inline-review-\(conversationId.uuidString.lowercased())"
    }

    private func syntheticReviewFinding(from payload: ReviewFindingPayload) -> CodeReviewFinding {
        let origin = inferredOrigin(for: payload)
        let category = inferredCategory(for: payload)
        return CodeReviewFinding(
            id: payload.finding.findingId,
            severity: payload.finding.severity,
            category: category,
            origin: origin,
            filePath: payload.finding.file,
            lineNumber: payload.finding.line,
            message: payload.finding.message,
            suggestedFix: payload.finding.suggestedFix,
            confidence: inferredConfidence(for: payload, origin: origin),
            evidence: payload.finding.message,
            sourceTool: "pipeline",
            status: payload.finding.status,
            verificationReport: "Captured from pipeline review finding event",
            verifiedAt: Date(),
            verificationMethod: "pipeline_event"
        )
    }

    private func inferredOrigin(for payload: ReviewFindingPayload) -> FindingOrigin {
        let text = "\(payload.jobId) \(payload.taskId) \(payload.finding.message)".lowercased()
        if text.contains("security")
            || text.contains("xss")
            || text.contains("csrf")
            || text.contains("ssrf")
            || text.contains("secret")
            || text.contains("authz")
        {
            return .securityAuditor
        }
        if text.contains("bughunter")
            || text.contains("regression")
            || text.contains("crash")
            || text.contains("nil")
            || text.contains("race")
        {
            return .bugHunter
        }
        return .reviewer
    }

    private func inferredCategory(for payload: ReviewFindingPayload) -> FindingCategory {
        CodeReviewFinding.fromRawTask(
            id: payload.finding.findingId,
            description: payload.finding.message,
            files: [payload.finding.file],
            severity: payload.finding.severity.rawValue,
            origin: inferredOrigin(for: payload),
            filePath: payload.finding.file,
            lineNumber: payload.finding.line
        ).category
    }

    private func inferredConfidence(
        for payload: ReviewFindingPayload,
        origin: FindingOrigin
    ) -> Double {
        switch origin {
        case .securityAuditor:
            return 0.92
        case .bugHunter:
            return 0.90
        case .reviewer, .auditTool:
            return 0.85
        }
    }
}
