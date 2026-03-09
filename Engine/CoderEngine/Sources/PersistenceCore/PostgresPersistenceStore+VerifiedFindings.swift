import Foundation

extension PostgresPersistenceStore {
    public func persistVerifiedFindingsEnvelope(
        _ envelope: VerifiedFindingsSessionEnvelope
    ) throws {
        try ensureReady()
        let sessionId = PersistenceSupport.sqlLiteral(envelope.sessionId)
        let envelopeJSON = try PersistenceSupport.jsonLiteral(envelope)
        let canonicalJSON = try PersistenceSupport.jsonLiteral(envelope.canonicalSnapshot)
        let projectionJSON = try PersistenceSupport.jsonLiteral(envelope.projectionSnapshot)

        var statements: [String] = [
            "BEGIN;",
            "DELETE FROM panel_projection WHERE finding_id IN (SELECT id FROM findings WHERE session_id = \(sessionId));",
            "DELETE FROM main_chat_projection WHERE finding_id IN (SELECT id FROM findings WHERE session_id = \(sessionId));",
            "DELETE FROM revalidation_reports WHERE session_id = \(sessionId);",
            "DELETE FROM patch_artifacts WHERE session_id = \(sessionId);",
            "DELETE FROM verification_reports WHERE session_id = \(sessionId);",
            "DELETE FROM evidence WHERE session_id = \(sessionId);",
            "DELETE FROM findings WHERE session_id = \(sessionId);",
            "DELETE FROM pipeline_events WHERE session_id = \(sessionId);",
            "DELETE FROM command_log WHERE session_id = \(sessionId);",
            "DELETE FROM pipeline_trace_log WHERE session_id = \(sessionId);",
            "DELETE FROM pipeline_runs WHERE session_id = \(sessionId);",
        ]

        let workspaceIDs = Set(
            envelope.canonicalSnapshot.runs.values.map(\.workspaceId) +
            envelope.canonicalSnapshot.patchArtifacts.values.map(\.workspaceId)
        )
        for workspaceID in workspaceIDs.sorted() where workspaceID.isEmpty == false {
            statements.append("""
            INSERT INTO workspaces(id, root_path, created_at, updated_at)
            VALUES (\(PersistenceSupport.sqlLiteral(workspaceID)), \(PersistenceSupport.sqlLiteral(workspaceID)), NOW(), NOW())
            ON CONFLICT (id) DO UPDATE SET root_path = EXCLUDED.root_path, updated_at = NOW(), version = workspaces.version + 1;
            """)
        }

        for run in envelope.canonicalSnapshot.runs.values {
            let domainScope = try PersistenceSupport.jsonLiteral(run.domainScope.map(\.rawValue))
            let budgetPolicy = try PersistenceSupport.jsonLiteral(run.budgetPolicy)
            statements.append("""
            INSERT INTO pipeline_runs (
                id, session_id, status, domain_scope, workspace_id, entry_point, budget_policy, max_duration,
                max_tool_calls, max_verification_attempts, max_patch_attempts, max_revalidation_attempts, timeout_at,
                cancelled_at, cancel_reason, tool_call_count, verification_attempt_count, patch_attempt_count,
                revalidation_attempt_count, is_cancellable, event_schema_version, entity_schema_version,
                projection_schema_version, created_at, updated_at
            ) VALUES (
                \(PersistenceSupport.sqlLiteral(run.id)), \(sessionId), \(PersistenceSupport.sqlLiteral(run.status.rawValue)),
                \(domainScope), \(PersistenceSupport.sqlLiteral(run.workspaceId)), \(PersistenceSupport.sqlLiteral(run.entryPoint.rawValue)),
                \(budgetPolicy), \(run.maxDuration), \(run.maxToolCalls), \(run.maxVerificationAttempts), \(run.maxPatchAttempts),
                \(run.maxRevalidationAttempts), \(sqlTimestamp(run.timeoutAt)), \(sqlTimestamp(run.cancelledAt)),
                \(sqlNullable(run.cancelReason)), \(run.toolCallCount), \(run.verificationAttemptCount), \(run.patchAttemptCount),
                \(run.revalidationAttemptCount), \(run.isCancellable), \(run.eventSchemaVersion), \(run.entitySchemaVersion),
                \(run.projectionSchemaVersion), \(sqlTimestamp(run.createdAt)), \(sqlTimestamp(run.updatedAt)))
            ON CONFLICT (id) DO UPDATE SET status = EXCLUDED.status, updated_at = EXCLUDED.updated_at, version = pipeline_runs.version + 1;
            """)
        }

        for finding in envelope.canonicalSnapshot.findings.values {
            let flags = try PersistenceSupport.jsonLiteral(finding.policyFlags)
            statements.append("""
            INSERT INTO findings (
                id, session_id, domain, title, summary, category, severity, confidence, status, file_path,
                line_start, line_end, rule_id, root_cause, impact, exploitability, reproducibility, version,
                origin_entry_point, last_command_id, stale_status, closed_reason, policy_flags, finding_fingerprint,
                identity_version, merged_into_finding_id, recurrence_group_id, created_at, updated_at
            ) VALUES (
                \(PersistenceSupport.sqlLiteral(finding.id)), \(sessionId), \(PersistenceSupport.sqlLiteral(finding.domain.rawValue)),
                \(PersistenceSupport.sqlLiteral(finding.title)), \(PersistenceSupport.sqlLiteral(finding.summary)),
                \(PersistenceSupport.sqlLiteral(finding.category)), \(PersistenceSupport.sqlLiteral(finding.severity.rawValue)),
                \(finding.confidence), \(PersistenceSupport.sqlLiteral(finding.status.rawValue)), \(PersistenceSupport.sqlLiteral(finding.filePath)),
                \(sqlInteger(finding.lineStart)), \(sqlInteger(finding.lineEnd)), \(sqlNullable(finding.ruleId)),
                \(sqlNullable(finding.rootCause)), \(sqlNullable(finding.impact)), \(sqlNullable(finding.exploitability)),
                \(PersistenceSupport.sqlLiteral(finding.reproducibility.rawValue)), \(finding.version),
                \(PersistenceSupport.sqlLiteral(finding.originEntryPoint.rawValue)), \(sqlNullable(finding.lastCommandId)),
                \(PersistenceSupport.sqlLiteral(finding.staleStatus.rawValue)), \(sqlNullable(finding.closedReason)),
                \(flags), \(PersistenceSupport.sqlLiteral(finding.findingFingerprint)), \(finding.identityVersion),
                \(sqlNullable(finding.mergedIntoFindingId)), \(sqlNullable(finding.recurrenceGroupId)),
                \(sqlTimestamp(finding.createdAt)), \(sqlTimestamp(finding.updatedAt)))
            ON CONFLICT (id) DO UPDATE SET status = EXCLUDED.status, updated_at = EXCLUDED.updated_at, version = findings.version + 1;
            """)
            statements.append("""
            INSERT INTO panel_projection(finding_id, severity, status, candidate_or_verified, duplicate_flag, recurrence_flag, patch_available, updated_at)
            VALUES (\(PersistenceSupport.sqlLiteral(finding.id)), \(PersistenceSupport.sqlLiteral(finding.severity.rawValue)),
                \(PersistenceSupport.sqlLiteral(finding.status.rawValue)),
                \(PersistenceSupport.sqlLiteral(finding.status == .verified ? "verified" : "candidate")),
                \(finding.mergedIntoFindingId != nil), \(finding.recurrenceGroupId != nil), \(finding.patchId != nil), \(sqlTimestamp(finding.updatedAt)))
            ON CONFLICT (finding_id) DO UPDATE SET status = EXCLUDED.status, updated_at = EXCLUDED.updated_at;
            """)
            statements.append("""
            INSERT INTO main_chat_projection(finding_id, card_summary, severity, status, patch_available, updated_at)
            VALUES (\(PersistenceSupport.sqlLiteral(finding.id)), \(PersistenceSupport.sqlLiteral(finding.summary)),
                \(PersistenceSupport.sqlLiteral(finding.severity.rawValue)), \(PersistenceSupport.sqlLiteral(finding.status.rawValue)),
                \(finding.patchId != nil), \(sqlTimestamp(finding.updatedAt)))
            ON CONFLICT (finding_id) DO UPDATE SET status = EXCLUDED.status, updated_at = EXCLUDED.updated_at;
            """)
        }

        for evidence in envelope.canonicalSnapshot.evidences.values {
            statements.append("""
            INSERT INTO evidence(id, session_id, finding_id, type, source, summary, payload_ref, origin_tool, origin_command_id, origin_run_id, origin_step, source_type, captured_at, artifact_ref, hash_or_fingerprint, contains_sensitive_data, redaction_applied, redaction_reason, retention_class, visibility_level, created_at)
            VALUES (\(PersistenceSupport.sqlLiteral(evidence.id)), \(sessionId), \(PersistenceSupport.sqlLiteral(evidence.findingId)),
                \(PersistenceSupport.sqlLiteral(evidence.type.rawValue)), \(PersistenceSupport.sqlLiteral(evidence.source)),
                \(PersistenceSupport.sqlLiteral(evidence.summary)), \(sqlNullable(evidence.payloadRef)),
                \(PersistenceSupport.sqlLiteral(evidence.originTool)), \(PersistenceSupport.sqlLiteral(evidence.originCommandId)),
                \(PersistenceSupport.sqlLiteral(evidence.originRunId)), \(PersistenceSupport.sqlLiteral(evidence.originStep)),
                \(PersistenceSupport.sqlLiteral(evidence.sourceType.rawValue)), \(sqlTimestamp(evidence.capturedAt)),
                \(sqlNullable(evidence.artifactRef)), \(PersistenceSupport.sqlLiteral(evidence.hashOrFingerprint)),
                \(evidence.containsSensitiveData), \(evidence.redactionApplied), \(sqlNullable(evidence.redactionReason)),
                \(PersistenceSupport.sqlLiteral(evidence.retentionClass.rawValue)), \(PersistenceSupport.sqlLiteral(evidence.visibilityLevel.rawValue)),
                \(sqlTimestamp(evidence.createdAt)));
            """)
        }

        for report in envelope.canonicalSnapshot.verificationReports.values {
            let steps = try PersistenceSupport.jsonLiteral(report.steps)
            let refs = try PersistenceSupport.jsonLiteral(report.commandLogRefs)
            statements.append("""
            INSERT INTO verification_reports(id, session_id, finding_id, verifier_type, verdict, confidence, steps, command_log_refs, reasoning_summary, error_category, failure_reason_code, retryable, retry_count, max_retry_allowed, created_at)
            VALUES (\(PersistenceSupport.sqlLiteral(report.id)), \(sessionId), \(PersistenceSupport.sqlLiteral(report.findingId)),
                \(PersistenceSupport.sqlLiteral(report.verifierType)), \(PersistenceSupport.sqlLiteral(report.verdict.rawValue)),
                \(report.confidence), \(steps), \(refs), \(PersistenceSupport.sqlLiteral(report.reasoningSummary)),
                \(sqlNullable(report.errorCategory?.rawValue)), \(sqlNullable(report.failureReasonCode)), \(report.retryable),
                \(report.retryCount), \(report.maxRetryAllowed), \(sqlTimestamp(report.createdAt)));
            """)
        }

        for patch in envelope.canonicalSnapshot.patchArtifacts.values {
            let changes = try PersistenceSupport.jsonLiteral(patch.fileChanges)
            statements.append("""
            INSERT INTO patch_artifacts(id, session_id, finding_id, title, strategy, file_changes, rationale, regression_risk, reversible, workspace_id, base_revision, target_revision, apply_strategy, apply_status, apply_error, error_category, retryable, retry_count, max_retry_allowed, contains_sensitive_data, redaction_applied, retention_class, visibility_level, created_at, updated_at)
            VALUES (\(PersistenceSupport.sqlLiteral(patch.id)), \(sessionId), \(PersistenceSupport.sqlLiteral(patch.findingId)),
                \(PersistenceSupport.sqlLiteral(patch.title)), \(PersistenceSupport.sqlLiteral(patch.strategy.rawValue)), \(changes),
                \(PersistenceSupport.sqlLiteral(patch.rationale)), \(PersistenceSupport.sqlLiteral(patch.regressionRisk.rawValue)),
                \(patch.reversible), \(PersistenceSupport.sqlLiteral(patch.workspaceId)), \(sqlNullable(patch.baseRevision)),
                \(sqlNullable(patch.targetRevision)), \(PersistenceSupport.sqlLiteral(patch.applyStrategy)),
                \(PersistenceSupport.sqlLiteral(patch.applyStatus.rawValue)), \(sqlNullable(patch.applyError)),
                \(sqlNullable(patch.errorCategory?.rawValue)), \(patch.retryable), \(patch.retryCount), \(patch.maxRetryAllowed),
                \(patch.containsSensitiveData), \(patch.redactionApplied), \(PersistenceSupport.sqlLiteral(patch.retentionClass.rawValue)),
                \(PersistenceSupport.sqlLiteral(patch.visibilityLevel.rawValue)), \(sqlTimestamp(patch.createdAt)), \(sqlTimestamp(patch.updatedAt)));
            """)
        }

        for report in envelope.canonicalSnapshot.revalidationReports.values {
            let checksRun = try PersistenceSupport.jsonLiteral(report.checksRun)
            statements.append("""
            INSERT INTO revalidation_reports(id, session_id, finding_id, patch_id, verdict, checks_run, summary, error_category, failure_reason_code, retryable, retry_count, max_retry_allowed, created_at)
            VALUES (\(PersistenceSupport.sqlLiteral(report.id)), \(sessionId), \(PersistenceSupport.sqlLiteral(report.findingId)),
                \(PersistenceSupport.sqlLiteral(report.patchId)), \(PersistenceSupport.sqlLiteral(report.verdict.rawValue)),
                \(checksRun), \(PersistenceSupport.sqlLiteral(report.summary)),
                \(sqlNullable(report.errorCategory?.rawValue)), \(sqlNullable(report.failureReasonCode)),
                \(report.retryable), \(report.retryCount), \(report.maxRetryAllowed), \(sqlTimestamp(report.createdAt)));
            """)
        }

        for event in envelope.canonicalSnapshot.eventLog {
            let payload = try PersistenceSupport.jsonLiteral(event.payload)
            statements.append("""
            INSERT INTO pipeline_events(id, session_id, run_id, entity_id, entity_type, event_type, payload, event_schema_version, entity_schema_version, migration_hint, created_at)
            VALUES (\(PersistenceSupport.sqlLiteral(event.id)), \(sessionId), \(PersistenceSupport.sqlLiteral(event.runId)),
                \(PersistenceSupport.sqlLiteral(event.entityId)), \(PersistenceSupport.sqlLiteral(event.entityType.rawValue)),
                \(PersistenceSupport.sqlLiteral(event.eventType)), \(payload), \(event.eventSchemaVersion), \(event.entitySchemaVersion),
                \(sqlNullable(event.migrationHint)), \(sqlTimestamp(event.createdAt)));
            """)
        }

        for record in envelope.canonicalSnapshot.commandLog {
            statements.append("""
            INSERT INTO command_log(domain, session_id, command_id, entity_id, issued_by, issued_from, issued_at, request_fingerprint, expected_entity_version, deduplicated, result_summary)
            VALUES ('verified_findings', \(sessionId), \(PersistenceSupport.sqlLiteral(record.commandId)), \(PersistenceSupport.sqlLiteral(record.entityId)),
                'legacy-import', 'shared_state', \(sqlTimestamp(record.recordedAt)), \(PersistenceSupport.sqlLiteral(record.requestFingerprint)),
                NULL, TRUE, \(PersistenceSupport.sqlLiteral(record.resultSummary)))
            ON CONFLICT (command_id) DO NOTHING;
            """)
        }

        for trace in envelope.canonicalSnapshot.traceLog {
            statements.append("""
            INSERT INTO pipeline_trace_log(session_id, trace_line) VALUES (\(sessionId), \(PersistenceSupport.sqlLiteral(trace)));
            """)
        }

        statements.append("""
        INSERT INTO verified_findings_checkpoints(session_id, event_schema_version, projection_schema_version, entity_schema_version, envelope_payload, canonical_payload, projection_payload, checkpointed_at)
        VALUES (\(sessionId), \(envelope.eventSchemaVersion), \(envelope.projectionSchemaVersion), \(envelope.entitySchemaVersion), \(envelopeJSON)::jsonb, \(canonicalJSON)::jsonb, \(projectionJSON)::jsonb, \(sqlTimestamp(envelope.lastUpdatedAt)))
        ON CONFLICT (session_id) DO UPDATE SET envelope_payload = EXCLUDED.envelope_payload, canonical_payload = EXCLUDED.canonical_payload, projection_payload = EXCLUDED.projection_payload, checkpointed_at = EXCLUDED.checkpointed_at;
        """)
        statements.append("COMMIT;")
        _ = try execute(sql: statements.joined(separator: "\n"))
    }

    public func readVerifiedFindingsEnvelope(sessionId: String) throws -> VerifiedFindingsSessionEnvelope? {
        try querySingleJSON(
            "SELECT envelope_payload::text FROM verified_findings_checkpoints WHERE session_id = \(PersistenceSupport.sqlLiteral(sessionId));",
            as: VerifiedFindingsSessionEnvelope.self
        )
    }
}
