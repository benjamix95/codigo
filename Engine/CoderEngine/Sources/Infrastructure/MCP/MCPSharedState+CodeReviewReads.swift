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
        let canonicalFindings = snapshot.canonicalVerifiedFindingsSnapshot.findings
        if normalizedKind == "candidate" || normalizedKind == "candidates" {
            return mappedCandidatePayloads(
                from: snapshot,
                canonicalFindings: canonicalFindings,
                severity: severity,
                origin: origin,
                category: category,
                file: file,
                limit: limit,
                includeSensitiveDetails: includeSensitiveDetails
            )
        }
        return mappedFindingPayloads(
            from: snapshot,
            canonicalFindings: canonicalFindings,
            severity: severity,
            status: status,
            origin: origin,
            category: category,
            file: file,
            limit: limit,
            includeSensitiveDetails: includeSensitiveDetails
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

    private static func mappedCandidatePayloads(
        from snapshot: CodeReviewSessionSnapshot,
        canonicalFindings: [String: VerifiedFinding],
        severity: String?,
        origin: String?,
        category: String?,
        file: String?,
        limit: Int,
        includeSensitiveDetails: Bool
    ) -> [[String: String]] {
        var candidates = snapshot.candidates
        if let severity, !severity.isEmpty { candidates = candidates.filter { $0.severity.rawValue == severity } }
        if let origin, !origin.isEmpty { candidates = candidates.filter { $0.origin.rawValue == origin } }
        if let category, !category.isEmpty { candidates = candidates.filter { $0.category.rawValue == FindingCategory.fromStoredValue(category).rawValue } }
        if let file, !file.isEmpty { candidates = candidates.filter { $0.filePath.contains(file) } }
        return Array(candidates.prefix(limit)).map { candidate in
            var payload: [String: String] = [
                "id": candidate.id,
                "kind": "candidate",
                "severity": candidate.severity.rawValue,
                "category": candidate.category.rawValue,
                "origin": candidate.origin.rawValue,
                "status": candidate.verificationStatus.rawValue,
            ]
            if let canonical = canonicalFindings[candidate.id] {
                payload["domain"] = canonical.domain.rawValue
                payload["stale_status"] = canonical.staleStatus.rawValue
                if !canonical.possibleDuplicateOf.isEmpty {
                    payload["possible_duplicate_of"] = canonical.possibleDuplicateOf.joined(separator: ",")
                }
            }
            if let confidence = candidate.confidence { payload["confidence"] = String(format: "%.2f", confidence) }
            if includeSensitiveDetails {
                payload["file_path"] = candidate.filePath
                payload["message"] = candidate.message
                payload["evidence"] = candidate.evidence
                if let lineNumber = candidate.lineNumber { payload["line_number"] = String(lineNumber) }
            } else {
                payload["file_label"] = redactedFindingReference(for: CodeReviewFinding.fromCandidate(candidate))
                payload["message_summary"] = redactedFindingSummary(for: CodeReviewFinding.fromCandidate(candidate))
            }
            return payload
        }
    }

    private static func mappedFindingPayloads(
        from snapshot: CodeReviewSessionSnapshot,
        canonicalFindings: [String: VerifiedFinding],
        severity: String?,
        status: String?,
        origin: String?,
        category: String?,
        file: String?,
        limit: Int,
        includeSensitiveDetails: Bool
    ) -> [[String: String]] {
        var findings = snapshot.findings
        if let severity, !severity.isEmpty { findings = findings.filter { $0.severity.rawValue == severity } }
        if let status, !status.isEmpty { findings = findings.filter { $0.status.rawValue == status } }
        if let origin, !origin.isEmpty { findings = findings.filter { $0.origin.rawValue == origin } }
        if let category, !category.isEmpty { findings = findings.filter { $0.category.rawValue == FindingCategory.fromStoredValue(category).rawValue } }
        if let file, !file.isEmpty { findings = findings.filter { $0.filePath.contains(file) } }
        return Array(findings.prefix(limit)).map { finding in
            var payload: [String: String] = [
                "id": finding.id,
                "kind": "verified",
                "severity": finding.severity.rawValue,
                "category": finding.category.rawValue,
                "origin": finding.origin.rawValue,
                "status": finding.status.rawValue,
                "blocking": finding.blocking ? "true" : "false",
            ]
            if let canonical = canonicalFindings[finding.id] {
                payload["domain"] = canonical.domain.rawValue
                payload["stale_status"] = canonical.staleStatus.rawValue
                if !canonical.possibleDuplicateOf.isEmpty {
                    payload["possible_duplicate_of"] = canonical.possibleDuplicateOf.joined(separator: ",")
                }
                if let mergedIntoFindingId = canonical.mergedIntoFindingId { payload["merged_into_finding_id"] = mergedIntoFindingId }
                if let recurrenceGroupId = canonical.recurrenceGroupId { payload["recurrence_group_id"] = recurrenceGroupId }
            }
            if let confidence = finding.confidence { payload["confidence"] = String(format: "%.2f", confidence) }
            if let sourceTool = finding.sourceTool { payload["source_tool"] = sourceTool }
            if includeSensitiveDetails {
                payload["file_path"] = finding.filePath
                payload["message"] = finding.message
                if let lineNumber = finding.lineNumber { payload["line_number"] = String(lineNumber) }
                if let endLineNumber = finding.endLineNumber { payload["end_line_number"] = String(endLineNumber) }
            } else {
                payload["file_label"] = redactedFindingReference(for: finding)
                payload["message_summary"] = redactedFindingSummary(for: finding)
                if let lineNumber = finding.lineNumber { payload["line_number"] = String(lineNumber) }
            }
            return payload
        }
    }
}
