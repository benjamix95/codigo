import CryptoKit
import Foundation

extension PostgresPersistenceStore {
    func workspaceUpserts(for envelope: VerifiedFindingsSessionEnvelope) -> [String] {
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

    func artifactPayloadPlaceholderUpserts(
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

    func deltaDeleteStatements(
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

    func deltaUpsertRunStatements(
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

    func deltaUpsertFindingStatements(
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
}
