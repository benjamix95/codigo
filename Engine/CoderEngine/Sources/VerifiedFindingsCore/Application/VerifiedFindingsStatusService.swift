import Foundation

public enum VerifiedFindingAdmissionPolicy {
    public static func canPromoteFinding(
        _ finding: VerifiedFinding,
        verificationReports: [VerifiedVerificationReport],
        evidences: [VerifiedEvidence],
        minimumConfidence: Double = 0.80
    ) -> Bool {
        guard finding.confidence >= minimumConfidence else { return false }
        guard verificationReports.contains(where: { report in
            report.verdict == .verified && report.confidence >= minimumConfidence
        }) else {
            return false
        }
        return evidences.contains(where: hasValidProvenance)
    }

    public static func requiresManualReview(
        _ report: VerifiedVerificationReport
    ) -> Bool {
        report.verdict == .needsManualReview || report.errorCategory == .unsupportedVerificationPath
    }

    private static func hasValidProvenance(_ evidence: VerifiedEvidence) -> Bool {
        !evidence.originTool.isEmpty &&
        !evidence.originCommandId.isEmpty &&
        !evidence.originRunId.isEmpty &&
        !evidence.originStep.isEmpty &&
        !evidence.hashOrFingerprint.isEmpty
    }
}

extension CodeReviewSessionSnapshot {
    public var verifiedFindingsProjection: VerifiedFindingsProjectionSnapshot {
        VerifiedFindingsService.projection(snapshot: self)
    }

    public var canonicalVerifiedFindingsSnapshot: VerifiedFindingsCanonicalSnapshot {
        VerifiedFindingsService.canonicalSnapshot(snapshot: self)
    }
}

public enum VerifiedFindingsStatusService {
    public static func payload(
        snapshot: CodeReviewSessionSnapshot,
        entryPoint: VerifiedFindingOriginEntryPoint = .mcp
    ) -> [String: String] {
        let verifiedState = VerifiedFindingsService.resolve(
            snapshot: snapshot,
            entryPoint: entryPoint
        )
        let securityGate = verifiedState.securityGate
        let replay = verifiedState.replayReport
        let projection = verifiedState.recovered.envelope.projectionSnapshot
        let pipeline = VerifiedFindingsPipelineStatusService.evaluate(
            snapshot: snapshot,
            entryPoint: entryPoint
        )

        var payload: [String: String] = [
            "session_id": snapshot.sessionId,
            "phase": snapshot.phase.rawValue,
            "stage": snapshot.stage.rawValue,
            "findings_total": String(snapshot.findings.count),
            "candidates_total": String(snapshot.candidates.count),
            "patches_total": String(snapshot.patches.count),
            "findings_open": String(snapshot.openFindings.count),
            "findings_blocking_open": String(snapshot.blockingOpenFindings.count),
            "current_round": String(snapshot.currentRound),
            "active_workers": String(snapshot.activeWorkerCount),
            "summary": snapshot.statusSummary,
            "false_positive_candidates": String(snapshot.falsePositiveCandidatesCount),
            "patches_ready": String(snapshot.outcome.patchesReady),
            "patches_applied": String(snapshot.outcome.patchesApplied),
            "prs_opened": String(snapshot.outcome.prsOpened),
            "merged_patches": String(snapshot.outcome.mergedPatches),
            "manual_action_required": snapshot.outcome.manualActionRequired ? "true" : "false",
            "audit_coverage_percent": String(format: "%.0f", snapshot.auditCoveragePercent),
            "verified_projection_candidates": String(projection.candidateQueue.count),
            "verified_projection_findings": String(projection.verifiedQueue.count),
            "verified_projection_duplicates": String(projection.duplicatesCount),
            "verified_projection_stale_candidates": String(projection.staleCandidatesCount),
            "verified_envelope_source": verifiedState.recovered.source.rawValue,
            "verified_replay_candidates": String(replay.candidateCount),
            "verified_replay_findings": String(replay.verifiedCount),
            "verified_replay_duplicates": String(replay.duplicatesCount),
            "verified_replay_stale_candidates": String(replay.staleCandidatesCount),
            "security_gate_ready": securityGate.ready ? "true" : "false",
            "security_gate_summary": securityGate.summary,
            "security_gate_projection_mismatches": String(securityGate.canonicalProjectionMismatchCount),
            "security_gate_undetected_duplicates": String(securityGate.undetectedDuplicateCount),
            "security_gate_missing_evidence": String(securityGate.findingsMissingEvidenceCount),
            "security_gate_missing_verification": String(securityGate.findingsMissingVerificationCount),
            "security_gate_apply_revalidate_success_rate": String(format: "%.2f", securityGate.applyRevalidateSuccessRate),
            "pipeline_phase": pipeline.pipelinePhase,
            "progress_percent": String(pipeline.progressPercent),
            "steps_total": String(pipeline.stepsTotal),
            "steps_completed": String(pipeline.stepsCompleted),
            "tools_total": String(pipeline.toolsTotal),
            "tools_completed": String(pipeline.toolsCompleted),
            "tools_running": String(pipeline.toolsRunning),
            "verification_gate_ready": pipeline.verificationGateReady ? "true" : "false",
            "patch_gate_ready": pipeline.patchGateReady ? "true" : "false",
            "publish_ready": pipeline.publishReady ? "true" : "false",
            "bundle_modes": pipeline.bundleModes.joined(separator: ","),
        ]

        if let checkpoint = verifiedState.recovered.checkpoint {
            payload["verified_checkpoint_findings"] = String(checkpoint.findingCount)
            payload["verified_checkpoint_events"] = String(checkpoint.eventCount)
            payload["verified_checkpoint_traces"] = String(checkpoint.traceCount)
            payload["verified_checkpointed_at"] = ISO8601DateFormatter().string(from: checkpoint.checkpointedAt)
        }
        if !snapshot.audit.toolCoverage.isEmpty {
            payload["findings_by_origin"] = snapshot.findingsByOrigin
                .map { "\($0.key.rawValue)=\($0.value.count)" }
                .sorted()
                .joined(separator: ",")
            payload["audit_tools"] = snapshot.audit.toolCoverage
                .map { "\($0.key)=\($0.value ? "covered" : "unavailable")" }
                .sorted()
                .joined(separator: ",")
            payload["audit_durations_ms"] = snapshot.audit.toolDurationsMs
                .map { "\($0.key)=\($0.value)" }
                .sorted()
                .joined(separator: ",")
            payload["audit_findings_counts"] = snapshot.audit.toolFindingsCounts
                .map { "\($0.key)=\($0.value)" }
                .sorted()
                .joined(separator: ",")
            payload["audit_adapters"] = snapshot.audit.toolAdapters
                .map { "\($0.key)=\($0.value.joined(separator: "+"))" }
                .sorted()
                .joined(separator: ",")
        }
        if let conversationId = snapshot.conversationId {
            payload["conversation_id"] = conversationId.uuidString.lowercased()
        }
        if let scope = snapshot.scope {
            payload["scope"] = scope.type.rawValue
            payload["scope_files"] = String(scope.files.count)
            if let ref = scope.ref {
                payload["scope_ref"] = ref
            }
        }
        if let workspacePath = snapshot.workspacePath {
            payload["workspace_path"] = workspacePath
        }
        if let jobId = snapshot.currentJobId {
            payload["job_id"] = jobId
        }
        if let error = snapshot.lastError {
            payload["error"] = error
        }
        if let testStatus = snapshot.lastTestStatus {
            payload["last_test_status"] = testStatus.rawValue
        }
        return payload
    }
}

public enum VerifiedFindingsCheckpointService {
    public static func loadCanonicalSnapshot(
        sessionId: String
    ) -> VerifiedFindingsCanonicalSnapshot? {
        MCPSharedState.readVerifiedFindingsCanonicalSnapshot(sessionId: sessionId)
    }

    public static func loadCheckpoint(
        sessionId: String
    ) -> MCPSharedVerifiedFindingsCheckpoint? {
        MCPSharedState.readVerifiedFindingsCheckpoint(sessionId: sessionId)
    }

    public static func rebuildEnvelope(
        sessionId: String
    ) -> VerifiedFindingsRecoveredEnvelope? {
        guard let canonical = loadCanonicalSnapshot(sessionId: sessionId) else { return nil }
        let checkpoint = loadCheckpoint(sessionId: sessionId)
        let envelope = VerifiedFindingsSessionEnvelope(
            sessionId: sessionId,
            canonicalSnapshot: canonical,
            projectionSnapshot: VerifiedFindingsProjectionBuilder.build(from: canonical),
            eventSchemaVersion: checkpoint?.eventSchemaVersion ?? 1,
            projectionSchemaVersion: checkpoint?.projectionSchemaVersion ?? 1,
            entitySchemaVersion: checkpoint?.entitySchemaVersion ?? 1,
            lastUpdatedAt: checkpoint?.checkpointedAt ?? Date()
        )
        return VerifiedFindingsRecoveredEnvelope(
            source: .rebuiltFromCanonical,
            envelope: envelope,
            checkpoint: checkpoint
        )
    }

    public static func resolveEnvelope(
        snapshot: CodeReviewSessionSnapshot,
        entryPoint: VerifiedFindingOriginEntryPoint = .reviewChat
    ) -> VerifiedFindingsRecoveredEnvelope {
        if let envelope = snapshot.verifiedFindings {
            return VerifiedFindingsRecoveredEnvelope(
                source: .embeddedSnapshot,
                envelope: envelope,
                checkpoint: loadCheckpoint(sessionId: snapshot.sessionId)
            )
        }
        if let storedEnvelope = MCPSharedState.readVerifiedFindingsEnvelope(sessionId: snapshot.sessionId) {
            return VerifiedFindingsRecoveredEnvelope(
                source: .storedEnvelope,
                envelope: storedEnvelope,
                checkpoint: loadCheckpoint(sessionId: snapshot.sessionId)
            )
        }
        if let rebuilt = rebuildEnvelope(sessionId: snapshot.sessionId) {
            return rebuilt
        }
        let synced = VerifiedFindingsSessionSyncService.sync(
            snapshot: snapshot,
            entryPoint: entryPoint
        )
        return VerifiedFindingsRecoveredEnvelope(
            source: .syncedFromSnapshot,
            envelope: synced,
            checkpoint: nil
        )
    }
}
