import CryptoKit
import Foundation

extension PostgresPersistenceStore {
    public func persistVerifiedFindingsEnvelope(
        _ envelope: VerifiedFindingsSessionEnvelope
    ) throws {
        try ensureReady()

        let previousEnvelope = try readVerifiedFindingsEnvelope(sessionId: envelope.sessionId)
            ?? readVerifiedFindingsEnvelopeFromFullCheckpointFallback(sessionId: envelope.sessionId)
        let previousCheckpoint = previousEnvelope.map(makeCompactCheckpoint)
        let checkpoint = makeCompactCheckpoint(envelope)
        let canonicalMetadata = makeCompactCanonicalMetadata(envelope)
        let sessionId = PersistenceSupport.sqlLiteral(envelope.sessionId)
        let reviewSessionReference = """
        (SELECT session_id FROM review_sessions WHERE session_id = \(sessionId) LIMIT 1)
        """
        let projectionJSON = try PersistenceSupport.jsonLiteral(envelope.projectionSnapshot)
        let checkpointJSON = try PersistenceSupport.jsonLiteral(checkpoint)
        let canonicalMetadataJSON = try PersistenceSupport.jsonLiteral(canonicalMetadata)
        let resolvedOriginRunId = envelope.canonicalSnapshot.runs.count == 1
            ? envelope.canonicalSnapshot.runs.keys.first
            : nil

        var statements = ["BEGIN;"]
        statements.append(contentsOf: workspaceUpserts(for: envelope))
        statements.append(contentsOf: artifactPayloadPlaceholderUpserts(for: envelope))
        statements.append(contentsOf: deltaDeleteStatements(
            previous: previousCheckpoint,
            current: checkpoint,
            sessionIdSQL: sessionId
        ))
        statements.append(contentsOf: deltaUpsertRunStatements(
            envelope: envelope,
            previous: previousCheckpoint,
            sessionIdSQL: sessionId,
            reviewSessionReference: reviewSessionReference
        ))
        statements.append(contentsOf: deltaUpsertFindingStatements(
            envelope: envelope,
            previous: previousCheckpoint,
            sessionIdSQL: sessionId,
            resolvedOriginRunId: resolvedOriginRunId
        ))
        statements.append(contentsOf: deltaUpsertEvidenceStatements(
            envelope: envelope,
            previous: previousCheckpoint,
            sessionIdSQL: sessionId
        ))
        statements.append(contentsOf: deltaUpsertVerificationReportStatements(
            envelope: envelope,
            previous: previousCheckpoint,
            sessionIdSQL: sessionId
        ))
        statements.append(contentsOf: deltaUpsertPatchStatements(
            envelope: envelope,
            previous: previousCheckpoint,
            sessionIdSQL: sessionId
        ))
        statements.append(contentsOf: deltaUpsertRevalidationStatements(
            envelope: envelope,
            previous: previousCheckpoint,
            sessionIdSQL: sessionId
        ))
        statements.append(contentsOf: deltaUpsertEventStatements(
            envelope: envelope,
            previous: previousCheckpoint,
            sessionIdSQL: sessionId
        ))
        statements.append(contentsOf: deltaUpsertCommandLogStatements(
            envelope: envelope,
            previous: previousCheckpoint,
            sessionIdSQL: sessionId
        ))
        statements.append(contentsOf: deltaTraceStatements(
            envelope: envelope,
            previous: previousCheckpoint,
            sessionIdSQL: sessionId
        ))
        statements.append(reviewChatProjectionStatement(
            envelope: envelope,
            sessionIdSQL: sessionId
        ))
        statements.append(checkpointStatement(
            sessionIdSQL: sessionId,
            checkpointJSON: checkpointJSON,
            canonicalMetadataJSON: canonicalMetadataJSON,
            projectionJSON: projectionJSON,
            checkpointedAt: envelope.lastUpdatedAt,
            eventSchemaVersion: envelope.eventSchemaVersion,
            projectionSchemaVersion: envelope.projectionSchemaVersion,
            entitySchemaVersion: envelope.entitySchemaVersion
        ))
        statements.append("COMMIT;")

        _ = try execute(sql: statements.joined(separator: "\n"))
    }

    public func readVerifiedFindingsEnvelope(sessionId: String) throws -> VerifiedFindingsSessionEnvelope? {
        if let envelope = try readVerifiedFindingsEnvelopeFromNormalizedTables(sessionId: sessionId) {
            return envelope
        }
        return readVerifiedFindingsEnvelopeFromFullCheckpointFallback(sessionId: sessionId)
    }

    private func readVerifiedFindingsEnvelopeFromNormalizedTables(
        sessionId: String
    ) throws -> VerifiedFindingsSessionEnvelope? {
        guard let checkpoint = try readCompactCheckpoint(sessionId: sessionId) else {
            return nil
        }

        let sessionIdSQL = PersistenceSupport.sqlLiteral(sessionId)
        let runs = try payloadArray(
            table: "pipeline_runs",
            sessionIdSQL: sessionIdSQL,
            orderBy: "created_at",
            as: [VerifiedPipelineRun].self
        )
        let findings = try payloadArray(
            table: "findings",
            sessionIdSQL: sessionIdSQL,
            orderBy: "created_at",
            as: [VerifiedFinding].self
        )
        let evidences = try payloadArray(
            table: "evidence",
            sessionIdSQL: sessionIdSQL,
            orderBy: "created_at",
            as: [VerifiedEvidence].self
        )
        let verificationReports = try payloadArray(
            table: "verification_reports",
            sessionIdSQL: sessionIdSQL,
            orderBy: "created_at",
            as: [VerifiedVerificationReport].self
        )
        let patchArtifacts = try payloadArray(
            table: "patch_artifacts",
            sessionIdSQL: sessionIdSQL,
            orderBy: "created_at",
            as: [VerifiedPatchArtifact].self
        )
        let revalidationReports = try payloadArray(
            table: "revalidation_reports",
            sessionIdSQL: sessionIdSQL,
            orderBy: "created_at",
            as: [VerifiedRevalidationReport].self
        )
        let commandLog = try queryJSONArray(
            """
            SELECT COALESCE(
                jsonb_agg(
                    jsonb_build_object(
                        'commandId', command_id,
                        'requestFingerprint', request_fingerprint,
                        'entityId', entity_id,
                        'resultSummary', COALESCE(result_summary, ''),
                        'recordedAt', issued_at
                    )
                    ORDER BY issued_at
                ),
                '[]'::jsonb
            )::text
            FROM command_log
            WHERE domain = 'verified_findings' AND session_id = \(sessionIdSQL);
            """,
            as: [VerifiedCommandDeduplicationRecord].self
        )
        let eventLog = try queryJSONArray(
            """
            SELECT COALESCE(
                jsonb_agg(
                    jsonb_build_object(
                        'id', id,
                        'runId', run_id,
                        'entityId', entity_id,
                        'entityType', entity_type,
                        'eventType', event_type,
                        'payload', payload,
                        'eventSchemaVersion', event_schema_version,
                        'entitySchemaVersion', entity_schema_version,
                        'migrationHint', migration_hint,
                        'createdAt', created_at
                    )
                    ORDER BY created_at
                ),
                '[]'::jsonb
            )::text
            FROM pipeline_events
            WHERE session_id = \(sessionIdSQL);
            """,
            as: [VerifiedPipelineEvent].self
        )
        let traceLog = try queryJSONArray(
            """
            SELECT COALESCE(
                jsonb_agg(trace_line ORDER BY id),
                '[]'::jsonb
            )::text
            FROM pipeline_trace_log
            WHERE session_id = \(sessionIdSQL);
            """,
            as: [String].self
        )
        let projection = try querySingleJSON(
            """
            SELECT projection_payload::text
            FROM verified_findings_checkpoints
            WHERE session_id = \(sessionIdSQL);
            """,
            as: VerifiedFindingsProjectionSnapshot.self
        )

        let canonical = VerifiedFindingsCanonicalSnapshot(
            runs: Dictionary(uniqueKeysWithValues: runs.map { ($0.id, $0) }),
            findings: Dictionary(uniqueKeysWithValues: findings.map { ($0.id, $0) }),
            evidences: Dictionary(uniqueKeysWithValues: evidences.map { ($0.id, $0) }),
            verificationReports: Dictionary(uniqueKeysWithValues: verificationReports.map { ($0.id, $0) }),
            patchArtifacts: Dictionary(uniqueKeysWithValues: patchArtifacts.map { ($0.id, $0) }),
            revalidationReports: Dictionary(uniqueKeysWithValues: revalidationReports.map { ($0.id, $0) }),
            commandLog: commandLog,
            eventLog: eventLog,
            traceLog: traceLog
        )

        return VerifiedFindingsSessionEnvelope(
            sessionId: sessionId,
            canonicalSnapshot: canonical,
            projectionSnapshot: projection ?? VerifiedFindingsProjectionBuilder.build(from: canonical),
            eventSchemaVersion: checkpoint.eventSchemaVersion,
            projectionSchemaVersion: checkpoint.projectionSchemaVersion,
            entitySchemaVersion: checkpoint.entitySchemaVersion,
            lastUpdatedAt: checkpoint.lastUpdatedAt
        )
    }

    private func readVerifiedFindingsEnvelopeFromFullCheckpointFallback(
        sessionId: String
    ) -> VerifiedFindingsSessionEnvelope? {
        try? querySingleJSON(
            "SELECT envelope_payload::text FROM verified_findings_checkpoints WHERE session_id = \(PersistenceSupport.sqlLiteral(sessionId));",
            as: VerifiedFindingsSessionEnvelope.self
        )
    }

    private func readCompactCheckpoint(
        sessionId: String
    ) throws -> VerifiedFindingsDeltaCheckpoint? {
        try querySingleJSON(
            "SELECT envelope_payload::text FROM verified_findings_checkpoints WHERE session_id = \(PersistenceSupport.sqlLiteral(sessionId));",
            as: VerifiedFindingsDeltaCheckpoint.self
        )
    }

    private func payloadArray<T: Decodable>(
        table: String,
        sessionIdSQL: String,
        orderBy: String,
        as type: [T].Type
    ) throws -> [T] {
        try queryJSONArray(
            """
            SELECT COALESCE(
                jsonb_agg(payload ORDER BY \(orderBy)),
                '[]'::jsonb
            )::text
            FROM \(table)
            WHERE session_id = \(sessionIdSQL);
            """,
            as: type
        )
    }

    private func workspaceUpserts(for envelope: VerifiedFindingsSessionEnvelope) -> [String] {
        let workspaceIDs = Set(
            envelope.canonicalSnapshot.runs.values.map(\.workspaceId)
                + envelope.canonicalSnapshot.patchArtifacts.values.map(\.workspaceId)
        )
        return workspaceIDs.sorted().compactMap { workspaceID in
            guard workspaceID.isEmpty == false else { return nil }
            return """
            INSERT INTO workspaces(id, root_path, created_at, updated_at)
            VALUES (\(PersistenceSupport.sqlLiteral(workspaceID)), \(PersistenceSupport.sqlLiteral(workspaceID)), NOW(), NOW())
            ON CONFLICT (id) DO UPDATE SET root_path = EXCLUDED.root_path, updated_at = NOW(), version = workspaces.version + 1;
            """
        }
    }

    private func artifactPayloadPlaceholderUpserts(
        for envelope: VerifiedFindingsSessionEnvelope
    ) -> [String] {
        let refs = envelope.canonicalSnapshot.evidences.values.reduce(into: [String: ArtifactPayloadPlaceholder]()) { partialResult, evidence in
            for reference in [evidence.payloadRef, evidence.artifactRef].filter({ !$0.isEmpty }) {
                let candidate = ArtifactPayloadPlaceholder(
                    id: reference,
                    contentText: reference,
                    containsSensitiveData: evidence.containsSensitiveData,
                    redactionApplied: evidence.redactionApplied,
                    retentionClass: evidence.retentionClass.rawValue,
                    visibilityLevel: evidence.visibilityLevel.rawValue
                )
                if let existing = partialResult[reference] {
                    partialResult[reference] = existing.merging(with: candidate)
                } else {
                    partialResult[reference] = candidate
                }
            }
        }

        return refs.values.sorted { $0.id < $1.id }.map { placeholder in
            """
            INSERT INTO artifact_payloads(id, payload_kind, content_json, content_text, content_bytes, contains_sensitive_data, redaction_applied, retention_class, visibility_level)
            VALUES (
                \(PersistenceSupport.sqlLiteral(placeholder.id)),
                'legacy_placeholder',
                NULL,
                \(PersistenceSupport.sqlLiteral(placeholder.contentText)),
                NULL,
                \(placeholder.containsSensitiveData),
                \(placeholder.redactionApplied),
                \(PersistenceSupport.sqlLiteral(placeholder.retentionClass)),
                \(PersistenceSupport.sqlLiteral(placeholder.visibilityLevel))
            )
            ON CONFLICT (id) DO UPDATE SET
                payload_kind = EXCLUDED.payload_kind,
                content_text = COALESCE(artifact_payloads.content_text, EXCLUDED.content_text),
                contains_sensitive_data = artifact_payloads.contains_sensitive_data OR EXCLUDED.contains_sensitive_data,
                redaction_applied = artifact_payloads.redaction_applied OR EXCLUDED.redaction_applied,
                retention_class = EXCLUDED.retention_class,
                visibility_level = EXCLUDED.visibility_level;
            """
        }
    }

    private func deltaDeleteStatements(
        previous: VerifiedFindingsDeltaCheckpoint?,
        current: VerifiedFindingsDeltaCheckpoint,
        sessionIdSQL: String
    ) -> [String] {
        guard let previous else { return [] }
        var statements: [String] = []
        statements.append(contentsOf: deleteStatements(
            table: "pipeline_events",
            idColumn: "id",
            ids: Set(previous.eventHashes.keys).subtracting(current.eventHashes.keys)
        ))
        statements.append(contentsOf: deleteStatements(
            table: "command_log",
            idColumn: "command_id",
            extraWhere: "domain = 'verified_findings'",
            ids: Set(previous.commandLogHashes.keys).subtracting(current.commandLogHashes.keys)
        ))
        statements.append(contentsOf: deleteStatements(
            table: "revalidation_reports",
            idColumn: "id",
            ids: Set(previous.revalidationReportHashes.keys).subtracting(current.revalidationReportHashes.keys)
        ))
        statements.append(contentsOf: deleteStatements(
            table: "patch_artifacts",
            idColumn: "id",
            ids: Set(previous.patchArtifactHashes.keys).subtracting(current.patchArtifactHashes.keys)
        ))
        statements.append(contentsOf: deleteStatements(
            table: "verification_reports",
            idColumn: "id",
            ids: Set(previous.verificationReportHashes.keys).subtracting(current.verificationReportHashes.keys)
        ))
        statements.append(contentsOf: deleteStatements(
            table: "evidence",
            idColumn: "id",
            ids: Set(previous.evidenceHashes.keys).subtracting(current.evidenceHashes.keys)
        ))
        statements.append(contentsOf: deleteStatements(
            table: "findings",
            idColumn: "id",
            ids: Set(previous.findingHashes.keys).subtracting(current.findingHashes.keys)
        ))
        statements.append(contentsOf: deleteStatements(
            table: "pipeline_runs",
            idColumn: "id",
            ids: Set(previous.runHashes.keys).subtracting(current.runHashes.keys)
        ))
        if previous.traceHash != current.traceHash {
            statements.append("DELETE FROM pipeline_trace_log WHERE session_id = \(sessionIdSQL);")
        }
        return statements
    }

    private func deleteStatements(
        table: String,
        idColumn: String,
        extraWhere: String? = nil,
        ids: Set<String>
    ) -> [String] {
        guard !ids.isEmpty else { return [] }
        let idsSQL = ids.sorted().map(PersistenceSupport.sqlLiteral).joined(separator: ", ")
        let predicate = "\(idColumn) IN (\(idsSQL))"
        if let extraWhere {
            return ["DELETE FROM \(table) WHERE \(extraWhere) AND \(predicate);"]
        }
        return ["DELETE FROM \(table) WHERE \(predicate);"]
    }

    private func deltaUpsertRunStatements(
        envelope: VerifiedFindingsSessionEnvelope,
        previous: VerifiedFindingsDeltaCheckpoint?,
        sessionIdSQL: String,
        reviewSessionReference: String
    ) -> [String] {
        envelope.canonicalSnapshot.runs.values.sorted { $0.id < $1.id }.compactMap { run in
            guard shouldUpsert(
                id: run.id,
                hash: hashPayload(run),
                previous: previous?.runHashes
            ) else { return nil }
            let domainScope = try? PersistenceSupport.jsonLiteral(run.domainScope.map(\.rawValue))
            let budgetPolicy = try? PersistenceSupport.jsonLiteral(run.budgetPolicy)
            let payload = try? PersistenceSupport.jsonLiteral(run)
            guard let domainScope, let budgetPolicy, let payload else { return nil }
            return """
            INSERT INTO pipeline_runs (
                id, session_id, review_session_id, status, domain_scope, workspace_id, entry_point, budget_policy, max_duration,
                max_tool_calls, max_verification_attempts, max_patch_attempts, max_revalidation_attempts, timeout_at,
                cancelled_at, cancel_reason, tool_call_count, verification_attempt_count, patch_attempt_count,
                revalidation_attempt_count, is_cancellable, event_schema_version, entity_schema_version,
                projection_schema_version, payload, created_at, updated_at
            ) VALUES (
                \(PersistenceSupport.sqlLiteral(run.id)), \(sessionIdSQL), \(reviewSessionReference), \(PersistenceSupport.sqlLiteral(run.status.rawValue)),
                \(domainScope), \(PersistenceSupport.sqlLiteral(run.workspaceId)), \(PersistenceSupport.sqlLiteral(run.entryPoint.rawValue)),
                \(budgetPolicy), \(run.maxDuration), \(run.maxToolCalls), \(run.maxVerificationAttempts), \(run.maxPatchAttempts),
                \(run.maxRevalidationAttempts), \(sqlTimestamp(run.timeoutAt)), \(sqlTimestamp(run.cancelledAt)),
                \(sqlNullable(run.cancelReason)), \(run.toolCallCount), \(run.verificationAttemptCount), \(run.patchAttemptCount),
                \(run.revalidationAttemptCount), \(run.isCancellable), \(run.eventSchemaVersion), \(run.entitySchemaVersion),
                \(run.projectionSchemaVersion), \(payload)::jsonb, \(sqlTimestamp(run.createdAt)), \(sqlTimestamp(run.updatedAt)))
            ON CONFLICT (id) DO UPDATE SET
                review_session_id = EXCLUDED.review_session_id,
                status = EXCLUDED.status,
                domain_scope = EXCLUDED.domain_scope,
                workspace_id = EXCLUDED.workspace_id,
                entry_point = EXCLUDED.entry_point,
                budget_policy = EXCLUDED.budget_policy,
                max_duration = EXCLUDED.max_duration,
                max_tool_calls = EXCLUDED.max_tool_calls,
                max_verification_attempts = EXCLUDED.max_verification_attempts,
                max_patch_attempts = EXCLUDED.max_patch_attempts,
                max_revalidation_attempts = EXCLUDED.max_revalidation_attempts,
                timeout_at = EXCLUDED.timeout_at,
                cancelled_at = EXCLUDED.cancelled_at,
                cancel_reason = EXCLUDED.cancel_reason,
                tool_call_count = EXCLUDED.tool_call_count,
                verification_attempt_count = EXCLUDED.verification_attempt_count,
                patch_attempt_count = EXCLUDED.patch_attempt_count,
                revalidation_attempt_count = EXCLUDED.revalidation_attempt_count,
                is_cancellable = EXCLUDED.is_cancellable,
                event_schema_version = EXCLUDED.event_schema_version,
                entity_schema_version = EXCLUDED.entity_schema_version,
                projection_schema_version = EXCLUDED.projection_schema_version,
                payload = EXCLUDED.payload,
                updated_at = EXCLUDED.updated_at,
                version = pipeline_runs.version + 1;
            """
        }
    }

    private func deltaUpsertFindingStatements(
        envelope: VerifiedFindingsSessionEnvelope,
        previous: VerifiedFindingsDeltaCheckpoint?,
        sessionIdSQL: String,
        resolvedOriginRunId: String?
    ) -> [String] {
        envelope.canonicalSnapshot.findings.values.sorted { $0.id < $1.id }.compactMap { finding in
            guard shouldUpsert(
                id: finding.id,
                hash: hashPayload(finding),
                previous: previous?.findingHashes
            ) else { return nil }
            let flags = try? PersistenceSupport.jsonLiteral(finding.policyFlags)
            let payload = try? PersistenceSupport.jsonLiteral(finding)
            guard let flags, let payload else { return nil }
            let projectionCandidateState: String = {
                switch finding.status {
                case .verified, .patchPreparing, .patchPrepared, .patchReviewed, .patchApplied, .revalidating, .fixedVerified, .fixFailed, .rollbackApplied, .closed:
                    return "verified"
                default:
                    return "candidate"
                }
            }()
            return """
            INSERT INTO findings (
                id, session_id, origin_run_id, domain, title, summary, category, severity, confidence, status, file_path,
                line_start, line_end, rule_id, root_cause, impact, exploitability, reproducibility, version,
                origin_entry_point, last_command_id, stale_status, closed_reason, policy_flags, finding_fingerprint,
                identity_version, merged_into_finding_id, recurrence_group_id, payload, created_at, updated_at
            ) VALUES (
                \(PersistenceSupport.sqlLiteral(finding.id)), \(sessionIdSQL), \(sqlNullable(resolvedOriginRunId)), \(PersistenceSupport.sqlLiteral(finding.domain.rawValue)),
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
                \(payload)::jsonb, \(sqlTimestamp(finding.createdAt)), \(sqlTimestamp(finding.updatedAt)))
            ON CONFLICT (id) DO UPDATE SET
                origin_run_id = EXCLUDED.origin_run_id,
                domain = EXCLUDED.domain,
                title = EXCLUDED.title,
                summary = EXCLUDED.summary,
                category = EXCLUDED.category,
                severity = EXCLUDED.severity,
                confidence = EXCLUDED.confidence,
                status = EXCLUDED.status,
                file_path = EXCLUDED.file_path,
                line_start = EXCLUDED.line_start,
                line_end = EXCLUDED.line_end,
                rule_id = EXCLUDED.rule_id,
                root_cause = EXCLUDED.root_cause,
                impact = EXCLUDED.impact,
                exploitability = EXCLUDED.exploitability,
                reproducibility = EXCLUDED.reproducibility,
                version = EXCLUDED.version,
                origin_entry_point = EXCLUDED.origin_entry_point,
                last_command_id = EXCLUDED.last_command_id,
                stale_status = EXCLUDED.stale_status,
                closed_reason = EXCLUDED.closed_reason,
                policy_flags = EXCLUDED.policy_flags,
                finding_fingerprint = EXCLUDED.finding_fingerprint,
                identity_version = EXCLUDED.identity_version,
                merged_into_finding_id = EXCLUDED.merged_into_finding_id,
                recurrence_group_id = EXCLUDED.recurrence_group_id,
                payload = EXCLUDED.payload,
                updated_at = EXCLUDED.updated_at;
            INSERT INTO panel_projection(finding_id, severity, status, candidate_or_verified, duplicate_flag, recurrence_flag, patch_available, updated_at)
            VALUES (\(PersistenceSupport.sqlLiteral(finding.id)), \(PersistenceSupport.sqlLiteral(finding.severity.rawValue)),
                \(PersistenceSupport.sqlLiteral(finding.status.rawValue)),
                \(PersistenceSupport.sqlLiteral(projectionCandidateState)),
                \(finding.mergedIntoFindingId != nil), \(finding.recurrenceGroupId != nil), \(finding.patchId != nil), \(sqlTimestamp(finding.updatedAt)))
            ON CONFLICT (finding_id) DO UPDATE SET
                severity = EXCLUDED.severity,
                status = EXCLUDED.status,
                candidate_or_verified = EXCLUDED.candidate_or_verified,
                duplicate_flag = EXCLUDED.duplicate_flag,
                recurrence_flag = EXCLUDED.recurrence_flag,
                patch_available = EXCLUDED.patch_available,
                updated_at = EXCLUDED.updated_at;
            INSERT INTO main_chat_projection(finding_id, card_summary, severity, status, patch_available, updated_at)
            VALUES (\(PersistenceSupport.sqlLiteral(finding.id)), \(PersistenceSupport.sqlLiteral(finding.summary)),
                \(PersistenceSupport.sqlLiteral(finding.severity.rawValue)), \(PersistenceSupport.sqlLiteral(finding.status.rawValue)),
                \(finding.patchId != nil), \(sqlTimestamp(finding.updatedAt)))
            ON CONFLICT (finding_id) DO UPDATE SET
                card_summary = EXCLUDED.card_summary,
                severity = EXCLUDED.severity,
                status = EXCLUDED.status,
                patch_available = EXCLUDED.patch_available,
                updated_at = EXCLUDED.updated_at;
            """
        }
    }

    private func deltaUpsertEvidenceStatements(
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

    private func deltaUpsertVerificationReportStatements(
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

    private func deltaUpsertPatchStatements(
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

    private func deltaUpsertRevalidationStatements(
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

    private func deltaUpsertEventStatements(
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

    private func deltaUpsertCommandLogStatements(
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

    private func deltaTraceStatements(
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

    private func reviewChatProjectionStatement(
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

    private func checkpointStatement(
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

    private func shouldUpsert(
        id: String,
        hash: String,
        previous: [String: String]?
    ) -> Bool {
        previous?[id] != hash
    }

    private func makeCompactCheckpoint(
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

    private func makeCompactCanonicalMetadata(
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

    private func hashedMap<T: Encodable>(_ dictionary: [String: T]) -> [String: String] {
        Dictionary(uniqueKeysWithValues: dictionary.map { ($0.key, hashPayload($0.value)) })
    }

    private func hashPayload<T: Encodable>(_ value: T) -> String {
        let data = (try? JSONEncoder.persistence.encode(value)) ?? Data()
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private func makeTraceHash(_ traceLog: [String]) -> String {
        hashPayload(traceLog)
    }
}

private struct VerifiedFindingsDeltaCheckpoint: Codable, Equatable {
    let sessionId: String
    let eventSchemaVersion: Int
    let projectionSchemaVersion: Int
    let entitySchemaVersion: Int
    let lastUpdatedAt: Date
    let checkpointedAt: Date
    let runHashes: [String: String]
    let findingHashes: [String: String]
    let evidenceHashes: [String: String]
    let verificationReportHashes: [String: String]
    let patchArtifactHashes: [String: String]
    let revalidationReportHashes: [String: String]
    let eventHashes: [String: String]
    let commandLogHashes: [String: String]
    let traceHash: String
}

private struct VerifiedFindingsCompactCanonicalMetadata: Codable, Equatable {
    let runIds: [String]
    let findingIds: [String]
    let evidenceIds: [String]
    let verificationReportIds: [String]
    let patchArtifactIds: [String]
    let revalidationReportIds: [String]
    let eventIds: [String]
    let commandIds: [String]
    let traceCount: Int
}

private struct ArtifactPayloadPlaceholder {
    let id: String
    let contentText: String
    let containsSensitiveData: Bool
    let redactionApplied: Bool
    let retentionClass: String
    let visibilityLevel: String

    func merging(with other: ArtifactPayloadPlaceholder) -> ArtifactPayloadPlaceholder {
        ArtifactPayloadPlaceholder(
            id: id,
            contentText: contentText,
            containsSensitiveData: containsSensitiveData || other.containsSensitiveData,
            redactionApplied: redactionApplied || other.redactionApplied,
            retentionClass: other.retentionClass,
            visibilityLevel: other.visibilityLevel
        )
    }
}
