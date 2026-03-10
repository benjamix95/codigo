import Foundation

extension PostgresPersistenceStore {
    public func readHistoricalFindings(
        query: HistoricalFindingsQuery
    ) throws -> [HistoricalFindingRecord] {
        try queryJSONArray(
            historicalFindingsSQL(
                workspaceId: query.workspaceId,
                findingId: nil,
                limit: query.limit
            ),
            as: [HistoricalFindingRecord].self
        )
    }

    public func readHistoricalFinding(
        findingId: String,
        workspaceId: String
    ) throws -> HistoricalFindingRecord? {
        try queryJSONArray(
            historicalFindingsSQL(
                workspaceId: workspaceId,
                findingId: findingId,
                limit: 1
            ),
            as: [HistoricalFindingRecord].self
        ).first
    }

    private func historicalFindingsSQL(
        workspaceId: String,
        findingId: String?,
        limit: Int
    ) -> String {
        let workspaceLiteral = PersistenceSupport.sqlLiteral(workspaceId)
        let findingFilter = findingId.map {
            " AND f.id = \(PersistenceSupport.sqlLiteral($0))"
        } ?? ""

        let recordSQL = """
        SELECT jsonb_build_object(
            'findingId', f.id,
            'sessionId', f.session_id,
            'workspaceId', COALESCE(rs.workspace_id, pa.workspace_id, \(workspaceLiteral)),
            'domain', f.domain,
            'severity', f.severity,
            'title', f.title,
            'summary', f.summary,
            'status', f.status,
            'filePath', f.file_path,
            'lineStart', f.line_start,
            'sourceOrigin', origin.source_origin,
            'closedReason', f.closed_reason,
            'patchId', pa.patch_id,
            'patchApplyStatus', pa.apply_status,
            'revalidationReportId', rv.revalidation_id,
            'revalidationVerdict', rv.verdict,
            'createdAt', to_char(f.created_at AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"'),
            'updatedAt', to_char(f.updated_at AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"'),
            'resolvedAt', CASE
                WHEN f.status IN ('fixed_verified', 'closed') THEN to_char(COALESCE(rv.created_at, pa.updated_at, f.updated_at) AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"')
                ELSE NULL
            END,
            'resumeEligible', CASE
                WHEN f.status IN ('fixed_verified', 'closed', 'rejected') THEN false
                ELSE true
            END,
            'timeline', COALESCE((
                SELECT jsonb_agg(
                    jsonb_build_object(
                        'eventId', pe.id,
                        'eventType', pe.event_type,
                        'detail', pe.payload->>'detail',
                        'createdAt', to_char(pe.created_at AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"'),
                        'metadata', COALESCE((
                            SELECT jsonb_object_agg(
                                replace(meta.key, 'meta_', ''),
                                meta.value
                            )
                            FROM jsonb_each_text(pe.payload) AS meta(key, value)
                            WHERE meta.key LIKE 'meta_%'
                        ), '{}'::jsonb)
                    )
                    ORDER BY pe.created_at ASC
                )
                FROM pipeline_events pe
                WHERE pe.session_id = f.session_id
                  AND pe.entity_id = f.id
            ), '[]'::jsonb)
        ) AS item
        FROM findings f
        LEFT JOIN review_sessions rs
            ON rs.session_id = f.session_id
        LEFT JOIN LATERAL (
            SELECT
                p.id AS patch_id,
                p.workspace_id,
                p.apply_status,
                p.updated_at
            FROM patch_artifacts p
            WHERE p.session_id = f.session_id
              AND p.finding_id = f.id
            ORDER BY p.updated_at DESC
            LIMIT 1
        ) pa ON TRUE
        LEFT JOIN LATERAL (
            SELECT
                r.id AS revalidation_id,
                r.verdict,
                r.created_at
            FROM revalidation_reports r
            WHERE r.session_id = f.session_id
              AND r.finding_id = f.id
            ORDER BY r.created_at DESC
            LIMIT 1
        ) rv ON TRUE
        LEFT JOIN verified_findings_checkpoints checkpoint
            ON checkpoint.session_id = f.session_id
        LEFT JOIN LATERAL (
            SELECT entry.value->>'sourceOrigin' AS source_origin
            FROM jsonb_each(checkpoint.canonical_payload->'findings') AS entry(key, value)
            WHERE entry.key = f.id
            LIMIT 1
        ) origin ON TRUE
        WHERE COALESCE(rs.workspace_id, pa.workspace_id) = \(workspaceLiteral)\(findingFilter)
        ORDER BY CASE
            WHEN f.status IN ('fixed_verified', 'closed', 'rejected') THEN 1
            ELSE 0
        END ASC,
        f.updated_at DESC
        LIMIT \(max(1, min(limit, 500)))
        """

        if findingId != nil {
            return "SELECT COALESCE(jsonb_agg(item), '[]'::jsonb)::text FROM (\(recordSQL)) AS item;"
        }

        return "SELECT COALESCE(jsonb_agg(item), '[]'::jsonb)::text FROM (\(recordSQL)) AS item;"
    }
}
