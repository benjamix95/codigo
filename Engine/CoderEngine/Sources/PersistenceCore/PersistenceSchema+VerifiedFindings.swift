import Foundation

extension PersistenceSchema {
    static let verifiedFindingsSQL = """
    CREATE TABLE IF NOT EXISTS pipeline_runs (
        id TEXT PRIMARY KEY,
        session_id TEXT NOT NULL,
        review_session_id TEXT REFERENCES review_sessions(session_id) ON DELETE SET NULL,
        status TEXT NOT NULL,
        domain_scope JSONB NOT NULL DEFAULT '[]'::jsonb,
        workspace_id TEXT REFERENCES workspaces(id) ON DELETE SET NULL,
        entry_point TEXT NOT NULL,
        budget_policy JSONB NOT NULL DEFAULT '{}'::jsonb,
        max_duration DOUBLE PRECISION NOT NULL,
        max_tool_calls INTEGER NOT NULL,
        max_verification_attempts INTEGER NOT NULL,
        max_patch_attempts INTEGER NOT NULL,
        max_revalidation_attempts INTEGER NOT NULL,
        timeout_at TIMESTAMPTZ,
        cancelled_at TIMESTAMPTZ,
        cancel_reason TEXT,
        tool_call_count INTEGER NOT NULL DEFAULT 0,
        verification_attempt_count INTEGER NOT NULL DEFAULT 0,
        patch_attempt_count INTEGER NOT NULL DEFAULT 0,
        revalidation_attempt_count INTEGER NOT NULL DEFAULT 0,
        is_cancellable BOOLEAN NOT NULL DEFAULT TRUE,
        event_schema_version INTEGER NOT NULL DEFAULT 1,
        entity_schema_version INTEGER NOT NULL DEFAULT 1,
        projection_schema_version INTEGER NOT NULL DEFAULT 1,
        payload JSONB NOT NULL DEFAULT '{}'::jsonb,
        created_at TIMESTAMPTZ NOT NULL,
        updated_at TIMESTAMPTZ NOT NULL,
        version BIGINT NOT NULL DEFAULT 1
    );
    CREATE TABLE IF NOT EXISTS findings (
        id TEXT PRIMARY KEY,
        session_id TEXT NOT NULL,
        origin_run_id TEXT REFERENCES pipeline_runs(id) ON DELETE SET NULL,
        domain TEXT NOT NULL,
        title TEXT NOT NULL,
        summary TEXT NOT NULL,
        category TEXT NOT NULL,
        severity TEXT NOT NULL,
        confidence DOUBLE PRECISION NOT NULL,
        status TEXT NOT NULL,
        file_path TEXT NOT NULL,
        line_start INTEGER,
        line_end INTEGER,
        rule_id TEXT,
        root_cause TEXT,
        impact TEXT,
        exploitability TEXT,
        reproducibility TEXT NOT NULL,
        version BIGINT NOT NULL DEFAULT 1,
        origin_entry_point TEXT NOT NULL,
        last_command_id TEXT,
        stale_status TEXT NOT NULL,
        closed_reason TEXT,
        policy_flags JSONB NOT NULL DEFAULT '[]'::jsonb,
        finding_fingerprint TEXT NOT NULL,
        identity_version INTEGER NOT NULL DEFAULT 1,
        merged_into_finding_id TEXT REFERENCES findings(id) ON DELETE SET NULL,
        recurrence_group_id TEXT,
        payload JSONB NOT NULL DEFAULT '{}'::jsonb,
        created_at TIMESTAMPTZ NOT NULL,
        updated_at TIMESTAMPTZ NOT NULL
    );
    CREATE TABLE IF NOT EXISTS evidence (
        id TEXT PRIMARY KEY,
        session_id TEXT NOT NULL,
        finding_id TEXT NOT NULL REFERENCES findings(id) ON DELETE CASCADE,
        type TEXT NOT NULL,
        source TEXT NOT NULL,
        summary TEXT NOT NULL,
        payload_ref TEXT REFERENCES artifact_payloads(id) ON DELETE SET NULL,
        origin_tool TEXT NOT NULL,
        origin_command_id TEXT NOT NULL,
        origin_run_id TEXT NOT NULL,
        origin_step TEXT NOT NULL,
        source_type TEXT NOT NULL,
        captured_at TIMESTAMPTZ NOT NULL,
        artifact_ref TEXT REFERENCES artifact_payloads(id) ON DELETE SET NULL,
        hash_or_fingerprint TEXT NOT NULL,
        contains_sensitive_data BOOLEAN NOT NULL DEFAULT FALSE,
        redaction_applied BOOLEAN NOT NULL DEFAULT FALSE,
        redaction_reason TEXT,
        retention_class TEXT NOT NULL,
        visibility_level TEXT NOT NULL,
        payload JSONB NOT NULL DEFAULT '{}'::jsonb,
        created_at TIMESTAMPTZ NOT NULL
    );
    CREATE TABLE IF NOT EXISTS verification_reports (
        id TEXT PRIMARY KEY,
        session_id TEXT NOT NULL,
        finding_id TEXT NOT NULL REFERENCES findings(id) ON DELETE CASCADE,
        verifier_type TEXT NOT NULL,
        verdict TEXT NOT NULL,
        confidence DOUBLE PRECISION NOT NULL,
        steps JSONB NOT NULL DEFAULT '[]'::jsonb,
        command_log_refs JSONB NOT NULL DEFAULT '[]'::jsonb,
        reasoning_summary TEXT NOT NULL,
        error_category TEXT,
        failure_reason_code TEXT,
        retryable BOOLEAN NOT NULL DEFAULT FALSE,
        retry_count INTEGER NOT NULL DEFAULT 0,
        max_retry_allowed INTEGER NOT NULL DEFAULT 0,
        payload JSONB NOT NULL DEFAULT '{}'::jsonb,
        created_at TIMESTAMPTZ NOT NULL
    );
    CREATE TABLE IF NOT EXISTS patch_artifacts (
        id TEXT PRIMARY KEY,
        session_id TEXT NOT NULL,
        finding_id TEXT NOT NULL REFERENCES findings(id) ON DELETE CASCADE,
        title TEXT NOT NULL,
        strategy TEXT NOT NULL,
        file_changes JSONB NOT NULL DEFAULT '[]'::jsonb,
        rationale TEXT NOT NULL,
        regression_risk TEXT NOT NULL,
        reversible BOOLEAN NOT NULL DEFAULT FALSE,
        workspace_id TEXT REFERENCES workspaces(id) ON DELETE SET NULL,
        base_revision TEXT,
        target_revision TEXT,
        apply_strategy TEXT NOT NULL,
        apply_status TEXT NOT NULL,
        apply_error TEXT,
        error_category TEXT,
        retryable BOOLEAN NOT NULL DEFAULT FALSE,
        retry_count INTEGER NOT NULL DEFAULT 0,
        max_retry_allowed INTEGER NOT NULL DEFAULT 0,
        contains_sensitive_data BOOLEAN NOT NULL DEFAULT FALSE,
        redaction_applied BOOLEAN NOT NULL DEFAULT FALSE,
        retention_class TEXT NOT NULL,
        visibility_level TEXT NOT NULL,
        payload JSONB NOT NULL DEFAULT '{}'::jsonb,
        created_at TIMESTAMPTZ NOT NULL,
        updated_at TIMESTAMPTZ NOT NULL
    );
    CREATE TABLE IF NOT EXISTS revalidation_reports (
        id TEXT PRIMARY KEY,
        session_id TEXT NOT NULL,
        finding_id TEXT NOT NULL REFERENCES findings(id) ON DELETE CASCADE,
        patch_id TEXT NOT NULL REFERENCES patch_artifacts(id) ON DELETE CASCADE,
        verdict TEXT NOT NULL,
        checks_run JSONB NOT NULL DEFAULT '[]'::jsonb,
        summary TEXT NOT NULL,
        error_category TEXT,
        failure_reason_code TEXT,
        retryable BOOLEAN NOT NULL DEFAULT FALSE,
        retry_count INTEGER NOT NULL DEFAULT 0,
        max_retry_allowed INTEGER NOT NULL DEFAULT 0,
        payload JSONB NOT NULL DEFAULT '{}'::jsonb,
        created_at TIMESTAMPTZ NOT NULL
    );
    CREATE TABLE IF NOT EXISTS pipeline_events (
        id TEXT PRIMARY KEY,
        session_id TEXT NOT NULL,
        run_id TEXT REFERENCES pipeline_runs(id) ON DELETE CASCADE,
        entity_id TEXT NOT NULL,
        entity_type TEXT NOT NULL,
        event_type TEXT NOT NULL,
        payload JSONB NOT NULL DEFAULT '{}'::jsonb,
        event_schema_version INTEGER NOT NULL DEFAULT 1,
        entity_schema_version INTEGER NOT NULL DEFAULT 1,
        migration_hint TEXT,
        created_at TIMESTAMPTZ NOT NULL
    );
    CREATE TABLE IF NOT EXISTS command_log (
        id BIGSERIAL PRIMARY KEY,
        domain TEXT NOT NULL,
        session_id TEXT NOT NULL,
        command_id TEXT NOT NULL UNIQUE,
        entity_id TEXT NOT NULL,
        issued_by TEXT NOT NULL,
        issued_from TEXT NOT NULL,
        issued_at TIMESTAMPTZ NOT NULL,
        request_fingerprint TEXT NOT NULL,
        expected_entity_version BIGINT,
        deduplicated BOOLEAN NOT NULL DEFAULT FALSE,
        result_summary TEXT,
        created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
        UNIQUE (entity_id, request_fingerprint)
    );
    CREATE TABLE IF NOT EXISTS pipeline_trace_log (
        id BIGSERIAL PRIMARY KEY,
        session_id TEXT NOT NULL,
        trace_line TEXT NOT NULL,
        created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
    );
    CREATE TABLE IF NOT EXISTS verified_findings_checkpoints (
        session_id TEXT PRIMARY KEY,
        event_schema_version INTEGER NOT NULL DEFAULT 1,
        projection_schema_version INTEGER NOT NULL DEFAULT 1,
        entity_schema_version INTEGER NOT NULL DEFAULT 1,
        envelope_payload JSONB NOT NULL,
        canonical_payload JSONB NOT NULL,
        projection_payload JSONB NOT NULL,
        checkpointed_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
    );
    CREATE INDEX IF NOT EXISTS idx_findings_fingerprint ON findings(finding_fingerprint);
    CREATE INDEX IF NOT EXISTS idx_findings_domain ON findings(domain);
    CREATE INDEX IF NOT EXISTS idx_findings_status ON findings(status);
    CREATE INDEX IF NOT EXISTS idx_findings_file ON findings(file_path);
    CREATE INDEX IF NOT EXISTS idx_pipeline_events_run ON pipeline_events(run_id);
    CREATE INDEX IF NOT EXISTS idx_pipeline_events_entity ON pipeline_events(entity_id, entity_type);
    CREATE INDEX IF NOT EXISTS idx_pipeline_events_type ON pipeline_events(event_type);
    CREATE INDEX IF NOT EXISTS idx_command_log_command_id ON command_log(command_id);
    CREATE INDEX IF NOT EXISTS idx_command_log_entity_fingerprint ON command_log(entity_id, request_fingerprint);
    ALTER TABLE pipeline_runs ADD COLUMN IF NOT EXISTS payload JSONB NOT NULL DEFAULT '{}'::jsonb;
    ALTER TABLE findings ADD COLUMN IF NOT EXISTS payload JSONB NOT NULL DEFAULT '{}'::jsonb;
    ALTER TABLE evidence ADD COLUMN IF NOT EXISTS payload JSONB NOT NULL DEFAULT '{}'::jsonb;
    ALTER TABLE verification_reports ADD COLUMN IF NOT EXISTS payload JSONB NOT NULL DEFAULT '{}'::jsonb;
    ALTER TABLE patch_artifacts ADD COLUMN IF NOT EXISTS payload JSONB NOT NULL DEFAULT '{}'::jsonb;
    ALTER TABLE revalidation_reports ADD COLUMN IF NOT EXISTS payload JSONB NOT NULL DEFAULT '{}'::jsonb;
    """
}
