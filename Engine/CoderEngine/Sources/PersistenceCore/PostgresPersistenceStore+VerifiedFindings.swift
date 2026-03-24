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
}
