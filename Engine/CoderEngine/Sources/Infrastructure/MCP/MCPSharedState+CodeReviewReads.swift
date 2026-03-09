import Foundation

extension MCPSharedState {
    public static func readCodeReviewFindings(
        sessionId: String,
        kind: String? = nil,
        severity: String? = nil,
        status: String? = nil,
        origin: String? = nil,
        category: String? = nil,
        file: String? = nil,
        limit: Int = 50,
        includeSensitiveDetails: Bool = false
    ) -> [[String: String]] {
        guard let snapshot = readCodeReviewSnapshot(sessionId: sessionId) else { return [] }
        let normalizedKind = (kind ?? "verified").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return VerifiedFindingsQueryService.listPayloads(
            snapshot: snapshot,
            query: VerifiedFindingsQuery(
                kind: normalizedKind == "candidate" || normalizedKind == "candidates" ? .candidate : .verified,
                domain: nil,
                severity: severity,
                status: status,
                sourceOrigin: origin,
                category: category.map { FindingCategory.fromStoredValue($0).rawValue },
                file: file,
                limit: limit,
                includeSensitiveDetails: includeSensitiveDetails
            ),
            entryPoint: .mcp
        )
    }

    public static func readCodeReviewStatus(sessionId: String) -> [String: String]? {
        guard let snapshot = readCodeReviewSnapshot(sessionId: sessionId) else { return nil }
        let verifiedState = VerifiedFindingsService.resolve(snapshot: snapshot, entryPoint: .mcp)
        let securityGate = verifiedState.securityGate
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
        ]
        payload["false_positive_candidates"] = String(snapshot.falsePositiveCandidatesCount)
        payload["patches_ready"] = String(snapshot.outcome.patchesReady)
        payload["patches_applied"] = String(snapshot.outcome.patchesApplied)
        payload["prs_opened"] = String(snapshot.outcome.prsOpened)
        payload["merged_patches"] = String(snapshot.outcome.mergedPatches)
        payload["manual_action_required"] = snapshot.outcome.manualActionRequired ? "true" : "false"
        payload["audit_coverage_percent"] = String(format: "%.0f", snapshot.auditCoveragePercent)
        let projection = verifiedState.recovered.envelope.projectionSnapshot
        payload["verified_projection_candidates"] = String(projection.candidateQueue.count)
        payload["verified_projection_findings"] = String(projection.verifiedQueue.count)
        payload["verified_projection_duplicates"] = String(projection.duplicatesCount)
        payload["verified_projection_stale_candidates"] = String(projection.staleCandidatesCount)
        let recovered = verifiedState.recovered
        let replay = verifiedState.replayReport
        payload["verified_envelope_source"] = recovered.source.rawValue
        if let checkpoint = recovered.checkpoint {
            payload["verified_checkpoint_findings"] = String(checkpoint.findingCount)
            payload["verified_checkpoint_events"] = String(checkpoint.eventCount)
            payload["verified_checkpoint_traces"] = String(checkpoint.traceCount)
            payload["verified_checkpointed_at"] = ISO8601DateFormatter().string(from: checkpoint.checkpointedAt)
        }
        payload["verified_replay_candidates"] = String(replay.candidateCount)
        payload["verified_replay_findings"] = String(replay.verifiedCount)
        payload["verified_replay_duplicates"] = String(replay.duplicatesCount)
        payload["verified_replay_stale_candidates"] = String(replay.staleCandidatesCount)
        payload["security_gate_ready"] = securityGate.ready ? "true" : "false"
        payload["security_gate_summary"] = securityGate.summary
        payload["security_gate_projection_mismatches"] = String(securityGate.canonicalProjectionMismatchCount)
        payload["security_gate_undetected_duplicates"] = String(securityGate.undetectedDuplicateCount)
        payload["security_gate_missing_evidence"] = String(securityGate.findingsMissingEvidenceCount)
        payload["security_gate_missing_verification"] = String(securityGate.findingsMissingVerificationCount)
        payload["security_gate_apply_revalidate_success_rate"] = String(format: "%.2f", securityGate.applyRevalidateSuccessRate)
        if !snapshot.audit.toolCoverage.isEmpty {
            payload["findings_by_origin"] = snapshot.findingsByOrigin.map { "\($0.key.rawValue)=\($0.value.count)" }.sorted().joined(separator: ",")
            payload["audit_tools"] = snapshot.audit.toolCoverage.map { "\($0.key)=\($0.value ? "covered" : "unavailable")" }.sorted().joined(separator: ",")
            payload["audit_durations_ms"] = snapshot.audit.toolDurationsMs.map { "\($0.key)=\($0.value)" }.sorted().joined(separator: ",")
            payload["audit_findings_counts"] = snapshot.audit.toolFindingsCounts.map { "\($0.key)=\($0.value)" }.sorted().joined(separator: ",")
            payload["audit_adapters"] = snapshot.audit.toolAdapters.map { "\($0.key)=\($0.value.joined(separator: "+"))" }.sorted().joined(separator: ",")
        }
        if let conversationId = snapshot.conversationId { payload["conversation_id"] = conversationId.uuidString.lowercased() }
        if let scope = snapshot.scope {
            payload["scope"] = scope.type.rawValue
            payload["scope_files"] = String(scope.files.count)
            if let ref = scope.ref { payload["scope_ref"] = ref }
        }
        if let workspacePath = snapshot.workspacePath { payload["workspace_path"] = workspacePath }
        if let jobId = snapshot.currentJobId { payload["job_id"] = jobId }
        if let error = snapshot.lastError { payload["error"] = error }
        if let testStatus = snapshot.lastTestStatus { payload["last_test_status"] = testStatus.rawValue }
        return payload
    }
}
