import Foundation

extension PersistenceSchema {
    static let metadataSQL = """
    CREATE TABLE IF NOT EXISTS schema_migrations (
        version INTEGER PRIMARY KEY,
        applied_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
    );
    """

    static let identitySQL = """
    CREATE TABLE IF NOT EXISTS workspaces (
        id TEXT PRIMARY KEY,
        root_path TEXT NOT NULL,
        created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
        updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
        version BIGINT NOT NULL DEFAULT 1
    );
    CREATE TABLE IF NOT EXISTS conversations (
        id TEXT PRIMARY KEY,
        workspace_id TEXT REFERENCES workspaces(id) ON DELETE SET NULL,
        created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
        updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
        version BIGINT NOT NULL DEFAULT 1
    );
    CREATE TABLE IF NOT EXISTS artifact_payloads (
        id TEXT PRIMARY KEY,
        payload_kind TEXT NOT NULL,
        content_json JSONB,
        content_text TEXT,
        content_bytes BYTEA,
        contains_sensitive_data BOOLEAN NOT NULL DEFAULT FALSE,
        redaction_applied BOOLEAN NOT NULL DEFAULT FALSE,
        retention_class TEXT NOT NULL DEFAULT 'standard',
        visibility_level TEXT NOT NULL DEFAULT 'internal',
        created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
    );
    CREATE TABLE IF NOT EXISTS audit_log (
        id BIGSERIAL PRIMARY KEY,
        domain TEXT NOT NULL,
        entity_id TEXT NOT NULL,
        entity_type TEXT NOT NULL,
        action TEXT NOT NULL,
        actor TEXT,
        source TEXT,
        command_id TEXT,
        correlation_id TEXT,
        outcome TEXT NOT NULL,
        request_fingerprint TEXT,
        redaction_flags JSONB NOT NULL DEFAULT '{}'::jsonb,
        duration_ms BIGINT,
        metadata JSONB NOT NULL DEFAULT '{}'::jsonb,
        created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
    );
    CREATE TABLE IF NOT EXISTS projection_watermarks (
        projection_name TEXT PRIMARY KEY,
        last_event_id TEXT,
        last_event_created_at TIMESTAMPTZ,
        updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
    );
    CREATE TABLE IF NOT EXISTS retention_jobs (
        id TEXT PRIMARY KEY,
        job_kind TEXT NOT NULL,
        status TEXT NOT NULL,
        last_run_at TIMESTAMPTZ,
        next_run_at TIMESTAMPTZ,
        details JSONB NOT NULL DEFAULT '{}'::jsonb,
        created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
        updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
    );
    CREATE TABLE IF NOT EXISTS review_sessions (
        session_id TEXT PRIMARY KEY,
        conversation_id TEXT REFERENCES conversations(id) ON DELETE SET NULL,
        workspace_id TEXT REFERENCES workspaces(id) ON DELETE SET NULL,
        mutation_sequence BIGINT NOT NULL DEFAULT 0,
        phase TEXT NOT NULL,
        stage TEXT NOT NULL,
        findings_count INTEGER NOT NULL DEFAULT 0,
        open_findings_count INTEGER NOT NULL DEFAULT 0,
        current_round INTEGER NOT NULL DEFAULT 0,
        active_worker_count INTEGER NOT NULL DEFAULT 0,
        scope_type TEXT,
        scope_ref TEXT,
        started_at TIMESTAMPTZ,
        completed_at TIMESTAMPTZ,
        analysis_completed_at TIMESTAMPTZ,
        status_payload JSONB NOT NULL DEFAULT '{}'::jsonb,
        last_updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
        version BIGINT NOT NULL DEFAULT 1
    );
    CREATE TABLE IF NOT EXISTS bug_hunter_runs (
        run_id TEXT PRIMARY KEY,
        conversation_id TEXT REFERENCES conversations(id) ON DELETE SET NULL,
        review_session_id TEXT REFERENCES review_sessions(session_id) ON DELETE SET NULL,
        workspace_id TEXT REFERENCES workspaces(id) ON DELETE SET NULL,
        source_kind TEXT NOT NULL,
        trigger_kind TEXT NOT NULL,
        git_root TEXT NOT NULL,
        branch_name TEXT,
        primary_commit TEXT,
        related_commits JSONB NOT NULL DEFAULT '[]'::jsonb,
        status TEXT NOT NULL,
        started_at TIMESTAMPTZ,
        completed_at TIMESTAMPTZ,
        last_updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
        last_message TEXT,
        auto_fix_mode TEXT NOT NULL,
        clean_after_fix BOOLEAN NOT NULL DEFAULT FALSE,
        verified_findings_count INTEGER NOT NULL DEFAULT 0,
        candidate_findings_count INTEGER NOT NULL DEFAULT 0,
        last_revalidation_verdict TEXT,
        security_gate_ready BOOLEAN,
        status_payload JSONB NOT NULL DEFAULT '{}'::jsonb,
        version BIGINT NOT NULL DEFAULT 1
    );
    """
}
