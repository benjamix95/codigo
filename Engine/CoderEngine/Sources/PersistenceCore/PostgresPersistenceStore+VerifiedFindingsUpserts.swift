import CryptoKit
import Foundation

extension PostgresPersistenceStore {
    func deltaUpsertEvidenceStatements(
        envelope: VerifiedFindingsSessionEnvelope,
        previous: VerifiedFindingsDeltaCheckpoint?,
        sessionIdSQL: String
    ) -> [String] {
        envelope.canonicalSnapshot.evidences.values.sorted { $0.id < $1.id }.compactMap { evidence in
            guard shouldUpsert(id: evidence.id, hash: hashPayload(evidence), previous: previous?.evidenceHashes) else {
                return nil
            }
            let payload = try? PersistenceSupport.jsonLiteral(evidence)
            guard let payload else { return nil }
            return """
            INSERT INTO evidence(id, session_id, finding_id, type, source, summary, payload_ref, origin_tool, origin_command_id, origin_run_id, origin_step, source_type, captured_at, artifact_ref, hash_or_fingerprint, contains_sensitive_data, redaction_applied, redaction_reason, retention_class, visibility_level, payload, created_at)
            VALUES (\(PersistenceSupport.sqlLiteral(evidence.id)), \(sessionIdSQL), \(PersistenceSupport.sqlLiteral(evidence.findingId)),
                \(PersistenceSupport.sqlLiteral(evidence.type.rawValue)), \(PersistenceSupport.sqlLiteral(evidence.source)),
                \(PersistenceSupport.sqlLiteral(evidence.summary)), \(sqlNullable(evidence.payloadRef)),
                \(PersistenceSupport.sqlLiteral(evidence.originTool)), \(PersistenceSupport.sqlLiteral(evidence.originCommandId)),
                \(PersistenceSupport.sqlLiteral(evidence.originRunId)), \(PersistenceSupport.sqlLiteral(evidence.originStep)),
                \(PersistenceSupport.sqlLiteral(evidence.sourceType.rawValue)), \(sqlTimestamp(evidence.capturedAt)),
                \(sqlNullable(evidence.artifactRef)), \(PersistenceSupport.sqlLiteral(evidence.hashOrFingerprint)),
                \(evidence.containsSensitiveData), \(evidence.redactionApplied), \(sqlNullable(evidence.redactionReason)),
                \(PersistenceSupport.sqlLiteral(evidence.retentionClass.rawValue)), \(PersistenceSupport.sqlLiteral(evidence.visibilityLevel.rawValue)),
                \(payload)::jsonb, \(sqlTimestamp(evidence.createdAt)))
            ON CONFLICT (id) DO UPDATE SET
                finding_id = EXCLUDED.finding_id,
                type = EXCLUDED.type,
                source = EXCLUDED.source,
                summary = EXCLUDED.summary,
                payload_ref = EXCLUDED.payload_ref,
                origin_tool = EXCLUDED.origin_tool,
                origin_command_id = EXCLUDED.origin_command_id,
                origin_run_id = EXCLUDED.origin_run_id,
                origin_step = EXCLUDED.origin_step,
                source_type = EXCLUDED.source_type,
                captured_at = EXCLUDED.captured_at,
                artifact_ref = EXCLUDED.artifact_ref,
                hash_or_fingerprint = EXCLUDED.hash_or_fingerprint,
                contains_sensitive_data = EXCLUDED.contains_sensitive_data,
                redaction_applied = EXCLUDED.redaction_applied,
                redaction_reason = EXCLUDED.redaction_reason,
                retention_class = EXCLUDED.retention_class,
                visibility_level = EXCLUDED.visibility_level,
                payload = EXCLUDED.payload,
                created_at = EXCLUDED.created_at;
            """
        }
    }

    func deltaUpsertVerificationReportStatements(
        envelope: VerifiedFindingsSessionEnvelope,
        previous: VerifiedFindingsDeltaCheckpoint?,
        sessionIdSQL: String
    ) -> [String] {
        envelope.canonicalSnapshot.verificationReports.values.sorted { $0.id < $1.id }.compactMap { report in
            guard shouldUpsert(id: report.id, hash: hashPayload(report), previous: previous?.verificationReportHashes) else {
                return nil
            }
            let steps = try? PersistenceSupport.jsonLiteral(report.steps)
            let refs = try? PersistenceSupport.jsonLiteral(report.commandLogRefs)
            let payload = try? PersistenceSupport.jsonLiteral(report)
            guard let steps, let refs, let payload else { return nil }
            return """
            INSERT INTO verification_reports(id, session_id, finding_id, verifier_type, verdict, confidence, steps, command_log_refs, reasoning_summary, error_category, failure_reason_code, retryable, retry_count, max_retry_allowed, payload, created_at)
            VALUES (\(PersistenceSupport.sqlLiteral(report.id)), \(sessionIdSQL), \(PersistenceSupport.sqlLiteral(report.findingId)),
                \(PersistenceSupport.sqlLiteral(report.verifierType)), \(PersistenceSupport.sqlLiteral(report.verdict.rawValue)),
                \(report.confidence), \(steps), \(refs), \(PersistenceSupport.sqlLiteral(report.reasoningSummary)),
                \(sqlNullable(report.errorCategory?.rawValue)), \(sqlNullable(report.failureReasonCode)), \(report.retryable),
                \(report.retryCount), \(report.maxRetryAllowed), \(payload)::jsonb, \(sqlTimestamp(report.createdAt)));
            """
        }
    }

    func deltaUpsertPatchStatements(
        envelope: VerifiedFindingsSessionEnvelope,
        previous: VerifiedFindingsDeltaCheckpoint?,
        sessionIdSQL: String
    ) -> [String] {
        envelope.canonicalSnapshot.patchArtifacts.values.sorted { $0.id < $1.id }.compactMap { patch in
            guard shouldUpsert(id: patch.id, hash: hashPayload(patch), previous: previous?.patchArtifactHashes) else {
                return nil
            }
            let changes = try? PersistenceSupport.jsonLiteral(patch.fileChanges)
            let payload = try? PersistenceSupport.jsonLiteral(patch)
            guard let changes, let payload else { return nil }
            return """
            INSERT INTO patch_artifacts(id, session_id, finding_id, title, strategy, file_changes, rationale, regression_risk, reversible, workspace_id, base_revision, target_revision, apply_strategy, apply_status, apply_error, error_category, retryable, retry_count, max_retry_allowed, contains_sensitive_data, redaction_applied, retention_class, visibility_level, payload, created_at, updated_at)
            VALUES (\(PersistenceSupport.sqlLiteral(patch.id)), \(sessionIdSQL), \(PersistenceSupport.sqlLiteral(patch.findingId)),
                \(PersistenceSupport.sqlLiteral(patch.title)), \(PersistenceSupport.sqlLiteral(patch.strategy.rawValue)), \(changes),
                \(PersistenceSupport.sqlLiteral(patch.rationale)), \(PersistenceSupport.sqlLiteral(patch.regressionRisk.rawValue)),
                \(patch.reversible), \(PersistenceSupport.sqlLiteral(patch.workspaceId)), \(sqlNullable(patch.baseRevision)),
                \(sqlNullable(patch.targetRevision)), \(PersistenceSupport.sqlLiteral(patch.applyStrategy)),
                \(PersistenceSupport.sqlLiteral(patch.applyStatus.rawValue)), \(sqlNullable(patch.applyError)),
                \(sqlNullable(patch.errorCategory?.rawValue)), \(patch.retryable), \(patch.retryCount), \(patch.maxRetryAllowed),
                \(patch.containsSensitiveData), \(patch.redactionApplied), \(PersistenceSupport.sqlLiteral(patch.retentionClass.rawValue)),
                \(PersistenceSupport.sqlLiteral(patch.visibilityLevel.rawValue)), \(payload)::jsonb, \(sqlTimestamp(patch.createdAt)), \(sqlTimestamp(patch.updatedAt)));
            """
        }
    }

    func deltaUpsertRevalidationStatements(
        envelope: VerifiedFindingsSessionEnvelope,
        previous: VerifiedFindingsDeltaCheckpoint?,
        sessionIdSQL: String
    ) -> [String] {
        envelope.canonicalSnapshot.revalidationReports.values.sorted { $0.id < $1.id }.compactMap { report in
            guard shouldUpsert(id: report.id, hash: hashPayload(report), previous: previous?.revalidationReportHashes) else {
                return nil
            }
            let checksRun = try? PersistenceSupport.jsonLiteral(report.checksRun)
            let payload = try? PersistenceSupport.jsonLiteral(report)
            guard let checksRun, let payload else { return nil }
            return """
            INSERT INTO revalidation_reports(id, session_id, finding_id, patch_id, verdict, checks_run, summary, error_category, failure_reason_code, retryable, retry_count, max_retry_allowed, payload, created_at)
            VALUES (\(PersistenceSupport.sqlLiteral(report.id)), \(sessionIdSQL), \(PersistenceSupport.sqlLiteral(report.findingId)),
                \(PersistenceSupport.sqlLiteral(report.patchId)), \(PersistenceSupport.sqlLiteral(report.verdict.rawValue)),
                \(checksRun), \(PersistenceSupport.sqlLiteral(report.summary)),
                \(sqlNullable(report.errorCategory?.rawValue)), \(sqlNullable(report.failureReasonCode)),
                \(report.retryable), \(report.retryCount), \(report.maxRetryAllowed), \(payload)::jsonb, \(sqlTimestamp(report.createdAt)));
            """
        }
    }

    func deltaUpsertEventStatements(
        envelope: VerifiedFindingsSessionEnvelope,
        previous: VerifiedFindingsDeltaCheckpoint?,
        sessionIdSQL: String
    ) -> [String] {
        envelope.canonicalSnapshot.eventLog.sorted { $0.id < $1.id }.compactMap { event in
            guard shouldUpsert(id: event.id, hash: hashPayload(event), previous: previous?.eventHashes) else {
                return nil
            }
            let payload = try? PersistenceSupport.jsonLiteral(event.payload)
            guard let payload else { return nil }
            return """
            INSERT INTO pipeline_events(id, session_id, run_id, entity_id, entity_type, event_type, payload, event_schema_version, entity_schema_version, migration_hint, created_at)
            VALUES (\(PersistenceSupport.sqlLiteral(event.id)), \(sessionIdSQL), \(PersistenceSupport.sqlLiteral(event.runId)),
                \(PersistenceSupport.sqlLiteral(event.entityId)), \(PersistenceSupport.sqlLiteral(event.entityType.rawValue)),
                \(PersistenceSupport.sqlLiteral(event.eventType)), \(payload), \(event.eventSchemaVersion), \(event.entitySchemaVersion),
                \(sqlNullable(event.migrationHint)), \(sqlTimestamp(event.createdAt)))
            ON CONFLICT (id) DO UPDATE SET
                run_id = EXCLUDED.run_id,
                entity_id = EXCLUDED.entity_id,
                entity_type = EXCLUDED.entity_type,
                event_type = EXCLUDED.event_type,
                payload = EXCLUDED.payload,
                event_schema_version = EXCLUDED.event_schema_version,
                entity_schema_version = EXCLUDED.entity_schema_version,
                migration_hint = EXCLUDED.migration_hint,
                created_at = EXCLUDED.created_at;
            """
        }
    }

    func deltaUpsertCommandLogStatements(
        envelope: VerifiedFindingsSessionEnvelope,
        previous: VerifiedFindingsDeltaCheckpoint?,
        sessionIdSQL: String
    ) -> [String] {
        envelope.canonicalSnapshot.commandLog.sorted { $0.commandId < $1.commandId }.compactMap { record in
            guard shouldUpsert(id: record.commandId, hash: hashPayload(record), previous: previous?.commandLogHashes) else {
                return nil
            }
            return """
            INSERT INTO command_log(domain, session_id, command_id, entity_id, issued_by, issued_from, issued_at, request_fingerprint, expected_entity_version, deduplicated, result_summary)
            VALUES ('verified_findings', \(sessionIdSQL), \(PersistenceSupport.sqlLiteral(record.commandId)), \(PersistenceSupport.sqlLiteral(record.entityId)),
                'delta-checkpoint', 'shared_state', \(sqlTimestamp(record.recordedAt)), \(PersistenceSupport.sqlLiteral(record.requestFingerprint)),
                NULL, TRUE, \(PersistenceSupport.sqlLiteral(record.resultSummary)))
            ON CONFLICT (command_id) DO UPDATE SET
                session_id = EXCLUDED.session_id,
                entity_id = EXCLUDED.entity_id,
                issued_at = EXCLUDED.issued_at,
                request_fingerprint = EXCLUDED.request_fingerprint,
                result_summary = EXCLUDED.result_summary;
            """
        }
    }

    func deltaTraceStatements(
        envelope: VerifiedFindingsSessionEnvelope,
        previous: VerifiedFindingsDeltaCheckpoint?,
        sessionIdSQL: String
    ) -> [String] {
        guard previous?.traceHash != makeTraceHash(envelope.canonicalSnapshot.traceLog) else {
            return []
        }
        var statements = ["DELETE FROM pipeline_trace_log WHERE session_id = \(sessionIdSQL);"]
        statements.append(contentsOf: envelope.canonicalSnapshot.traceLog.map {
            "INSERT INTO pipeline_trace_log(session_id, trace_line) VALUES (\(sessionIdSQL), \(PersistenceSupport.sqlLiteral($0)));"
        })
        return statements
    }

    func reviewChatProjectionStatement(
        envelope: VerifiedFindingsSessionEnvelope,
        sessionIdSQL: String
    ) -> String {
        let projection = envelope.projectionSnapshot
        let findingStatuses = envelope.canonicalSnapshot.findings.values
        let summary = "verified=\(projection.verifiedQueue.count) candidates=\(projection.candidateQueue.count)"
        let rejectedCount = findingStatuses.filter { $0.status == .rejected }.count
        let manualReviewCount = findingStatuses.filter { $0.status == .needsManualReview }.count
        return """
        INSERT INTO review_chat_projection(run_id, summary, verified_count, candidate_count, rejected_count, needs_manual_review_count, updated_at)
        VALUES (\(sessionIdSQL), \(PersistenceSupport.sqlLiteral(summary)),
            \(projection.verifiedQueue.count), \(projection.candidateQueue.count),
            \(rejectedCount), \(manualReviewCount), \(sqlTimestamp(envelope.lastUpdatedAt)))
        ON CONFLICT (run_id) DO UPDATE SET
            summary = EXCLUDED.summary,
            verified_count = EXCLUDED.verified_count,
            candidate_count = EXCLUDED.candidate_count,
            rejected_count = EXCLUDED.rejected_count,
            needs_manual_review_count = EXCLUDED.needs_manual_review_count,
            updated_at = EXCLUDED.updated_at;
        """
    }

    func checkpointStatement(
        sessionIdSQL: String,
        checkpointJSON: String,
        canonicalMetadataJSON: String,
        projectionJSON: String,
        checkpointedAt: Date,
        eventSchemaVersion: Int,
        projectionSchemaVersion: Int,
        entitySchemaVersion: Int
    ) -> String {
        """
        INSERT INTO verified_findings_checkpoints(session_id, event_schema_version, projection_schema_version, entity_schema_version, envelope_payload, canonical_payload, projection_payload, checkpointed_at)
        VALUES (\(sessionIdSQL), \(eventSchemaVersion), \(projectionSchemaVersion), \(entitySchemaVersion), \(checkpointJSON)::jsonb, \(canonicalMetadataJSON)::jsonb, \(projectionJSON)::jsonb, \(sqlTimestamp(checkpointedAt)))
        ON CONFLICT (session_id) DO UPDATE SET
            event_schema_version = EXCLUDED.event_schema_version,
            projection_schema_version = EXCLUDED.projection_schema_version,
            entity_schema_version = EXCLUDED.entity_schema_version,
            envelope_payload = EXCLUDED.envelope_payload,
            canonical_payload = EXCLUDED.canonical_payload,
            projection_payload = EXCLUDED.projection_payload,
            checkpointed_at = EXCLUDED.checkpointed_at;
        """
    }

    func shouldUpsert(
        id: String,
        hash: String,
        previous: [String: String]?
    ) -> Bool {
        previous?[id] != hash
    }

    func makeCompactCheckpoint(
        _ envelope: VerifiedFindingsSessionEnvelope
    ) -> VerifiedFindingsDeltaCheckpoint {
        VerifiedFindingsDeltaCheckpoint(
            sessionId: envelope.sessionId,
            eventSchemaVersion: envelope.eventSchemaVersion,
            projectionSchemaVersion: envelope.projectionSchemaVersion,
            entitySchemaVersion: envelope.entitySchemaVersion,
            lastUpdatedAt: envelope.lastUpdatedAt,
            checkpointedAt: envelope.lastUpdatedAt,
            runHashes: hashedMap(envelope.canonicalSnapshot.runs),
            findingHashes: hashedMap(envelope.canonicalSnapshot.findings),
            evidenceHashes: hashedMap(envelope.canonicalSnapshot.evidences),
            verificationReportHashes: hashedMap(envelope.canonicalSnapshot.verificationReports),
            patchArtifactHashes: hashedMap(envelope.canonicalSnapshot.patchArtifacts),
            revalidationReportHashes: hashedMap(envelope.canonicalSnapshot.revalidationReports),
            eventHashes: Dictionary(uniqueKeysWithValues: envelope.canonicalSnapshot.eventLog.map { ($0.id, hashPayload($0)) }),
            commandLogHashes: Dictionary(uniqueKeysWithValues: envelope.canonicalSnapshot.commandLog.map { ($0.commandId, hashPayload($0)) }),
            traceHash: makeTraceHash(envelope.canonicalSnapshot.traceLog)
        )
    }

    func makeCompactCanonicalMetadata(
        _ envelope: VerifiedFindingsSessionEnvelope
    ) -> VerifiedFindingsCompactCanonicalMetadata {
        VerifiedFindingsCompactCanonicalMetadata(
            runIds: envelope.canonicalSnapshot.runs.keys.sorted(),
            findingIds: envelope.canonicalSnapshot.findings.keys.sorted(),
            evidenceIds: envelope.canonicalSnapshot.evidences.keys.sorted(),
            verificationReportIds: envelope.canonicalSnapshot.verificationReports.keys.sorted(),
            patchArtifactIds: envelope.canonicalSnapshot.patchArtifacts.keys.sorted(),
            revalidationReportIds: envelope.canonicalSnapshot.revalidationReports.keys.sorted(),
            eventIds: envelope.canonicalSnapshot.eventLog.map(\.id),
            commandIds: envelope.canonicalSnapshot.commandLog.map(\.commandId),
            traceCount: envelope.canonicalSnapshot.traceLog.count
        )
    }

    func hashedMap<T: Encodable>(_ dictionary: [String: T]) -> [String: String] {
        Dictionary(uniqueKeysWithValues: dictionary.map { ($0.key, hashPayload($0.value)) })
    }

    func hashPayload<T: Encodable>(_ value: T) -> String {
        let data = (try? JSONEncoder.persistence.encode(value)) ?? Data()
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    func makeTraceHash(_ traceLog: [String]) -> String {
        hashPayload(traceLog)
    }
}

