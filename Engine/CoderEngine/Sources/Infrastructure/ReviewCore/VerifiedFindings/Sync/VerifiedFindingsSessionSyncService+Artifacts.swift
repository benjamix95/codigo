import Foundation

extension VerifiedFindingsSessionSyncService {
    static func buildEvidences(
        snapshot: CodeReviewSessionSnapshot,
        findings: [VerifiedFinding]
    ) -> [VerifiedEvidence] {
        findings.compactMap { finding in
            let raw = snapshot.findings.first(where: { $0.id == finding.id })?.evidence
                ?? snapshot.candidates.first(where: { $0.id == finding.id })?.evidence
            guard let raw, !raw.isEmpty else { return nil }
            let redacted = SensitiveDataRedactionService.redact(raw)
            return VerifiedEvidence(
                id: "evidence-\(finding.id)",
                findingId: finding.id,
                type: finding.domain == .security ? .toolOutput : .testFailure,
                source: finding.filePath,
                summary: redacted.value,
                payloadRef: "inline:\(finding.id)",
                originTool: snapshot.findings.first(where: { $0.id == finding.id })?.sourceTool
                    ?? snapshot.candidates.first(where: { $0.id == finding.id })?.sourceTool
                    ?? "review_sync",
                originCommandId: "command-\(snapshot.sessionId)-\(finding.id)",
                originRunId: snapshot.sessionId,
                originStep: "sync_snapshot",
                sourceType: finding.domain == .security ? .scanner : .test,
                capturedAt: snapshot.lastUpdatedAt,
                artifactRef: "snapshot:\(snapshot.sessionId)",
                hashOrFingerprint: "\(finding.findingFingerprint)|evidence",
                containsSensitiveData: redacted.wasRedacted,
                redactionApplied: redacted.wasRedacted,
                redactionReason: redacted.wasRedacted ? "secret_detected" : nil,
                retentionClass: redacted.wasRedacted ? .sensitive : .standard,
                visibilityLevel: redacted.wasRedacted ? .redacted : .full,
                createdAt: snapshot.lastUpdatedAt
            )
        }
    }

    static func buildVerificationReports(
        snapshot: CodeReviewSessionSnapshot,
        findings: [VerifiedFinding],
        evidences: [VerifiedEvidence]
    ) -> [VerifiedVerificationReport] {
        findings.compactMap { finding in
            let report = snapshot.findings.first(where: { $0.id == finding.id })?.verificationReport
                ?? snapshot.candidates.first(where: { $0.id == finding.id })?.verificationReport
            let method = snapshot.findings.first(where: { $0.id == finding.id })?.verificationMethod
                ?? snapshot.candidates.first(where: { $0.id == finding.id })?.verificationMethod
            guard let report, !report.isEmpty else { return nil }
            let verdict = verificationVerdict(for: finding.status)
            return VerifiedVerificationReport(
                id: "verification-\(finding.id)",
                findingId: finding.id,
                verifierType: method ?? "review_sync",
                verdict: verdict,
                confidence: max(0.0, finding.confidence),
                steps: [report],
                commandLogRefs: ["command-\(snapshot.sessionId)-\(finding.id)"],
                evidenceIds: evidences.filter { $0.findingId == finding.id }.map(\.id),
                reasoningSummary: report,
                errorCategory: verdict == .needsManualReview ? .unsupportedVerificationPath : nil,
                failureReasonCode: verdict == .needsManualReview ? "manual_review_required" : nil,
                retryable: false,
                failurePhase: verdict == .verified ? nil : .verification,
                retryCount: 0,
                maxRetryAllowed: 1,
                createdAt: snapshot.lastUpdatedAt
            )
        }
    }

    static func buildPatchArtifacts(snapshot: CodeReviewSessionSnapshot) -> [VerifiedPatchArtifact] {
        snapshot.patches.map { patch in
            VerifiedPatchArtifact(
                id: patch.id,
                findingId: patch.findingId,
                title: "Patch for \(patch.findingId)",
                strategy: .minimalFix,
                fileChanges: patch.touchedFiles.map {
                    VerifiedPatchFileChange(
                        filePath: $0,
                        hunks: [VerifiedPatchHunk(startLineOld: nil, startLineNew: nil, diff: patch.diffPreview, summary: "Patch preview")]
                    )
                },
                rationale: patch.verificationReport ?? patch.applyMessage ?? "Review patch workflow artifact",
                regressionRisk: patch.riskScore < 0.34 ? .low : (patch.riskScore < 0.67 ? .medium : .high),
                linkedTestIds: patch.validationRunId.map { [$0] } ?? [],
                reversible: patch.rollbackRef != nil,
                version: 1,
                workspaceId: patch.worktreePath ?? snapshot.workspacePath ?? "workspace",
                baseRevision: patch.baseBranchName,
                targetRevision: patch.branchName,
                applyPreconditions: patch.touchedFiles,
                rollbackAvailable: patch.rollbackRef != nil,
                applyStrategy: "git_apply_3way",
                applyStatus: mapApplyStatus(patch.status),
                applyError: patch.applyMessage,
                errorCategory: patch.status == .applyFailed ? .patchApplyFailed : nil,
                failureReasonCode: patch.status == .applyFailed ? "apply_failed" : nil,
                retryable: patch.status == .applyFailed,
                retryCount: 0,
                maxRetryAllowed: 1,
                containsSensitiveData: false,
                redactionApplied: false,
                retentionClass: .standard,
                visibilityLevel: .full,
                createdAt: patch.createdAt,
                updatedAt: patch.updatedAt
            )
        }
    }

    static func buildRevalidationReports(snapshot: CodeReviewSessionSnapshot) -> [VerifiedRevalidationReport] {
        snapshot.patches.compactMap { patch in
            guard patch.status == .applied || patch.status == .applyFailed else { return nil }
            let verdict: RevalidationVerdict = patch.validationStatus == .passed ? .fixedVerified : .fixFailed
            return VerifiedRevalidationReport(
                id: "revalidation-\(patch.id)",
                findingId: patch.findingId,
                patchId: patch.id,
                verdict: verdict,
                checksRun: patch.validationRunId.map { [$0] } ?? [],
                evidenceIds: [],
                summary: patch.validationSummary ?? patch.applyMessage ?? "Revalidation unavailable",
                errorCategory: verdict == .fixFailed ? .revalidationFailed : nil,
                failureReasonCode: verdict == .fixFailed ? "validation_failed" : nil,
                retryable: verdict == .fixFailed,
                retryCount: 0,
                maxRetryAllowed: 1,
                createdAt: patch.updatedAt
            )
        }
    }

    static func buildRun(
        snapshot: CodeReviewSessionSnapshot,
        entryPoint: VerifiedFindingOriginEntryPoint
    ) -> VerifiedPipelineRun {
        let hasSecurity = snapshot.findings.contains { $0.origin == .securityAuditor || $0.category == .security }
            || snapshot.candidates.contains { $0.origin == .securityAuditor || $0.category == .security }
        return VerifiedPipelineRun(
            id: snapshot.sessionId,
            status: mapRunStatus(snapshot.phase),
            domainScope: hasSecurity ? [.bug, .security] : [.bug],
            workspaceId: snapshot.workspacePath ?? "workspace",
            entryPoint: entryPoint,
            budgetPolicy: VerifiedRunBudgetPolicy(),
            maxDuration: 600,
            maxToolCalls: 128,
            maxVerificationAttempts: 3,
            maxPatchAttempts: 2,
            maxRevalidationAttempts: 2,
            timeoutAt: nil,
            cancelledAt: nil,
            cancelReason: nil,
            toolCallCount: snapshot.events.count,
            verificationAttemptCount: snapshot.candidates.count,
            patchAttemptCount: snapshot.patches.count,
            revalidationAttemptCount: snapshot.patches.filter { $0.validationRunId != nil }.count,
            isCancellable: snapshot.isActive,
            createdAt: snapshot.startedAt ?? snapshot.lastUpdatedAt,
            updatedAt: snapshot.lastUpdatedAt
        )
    }
}
