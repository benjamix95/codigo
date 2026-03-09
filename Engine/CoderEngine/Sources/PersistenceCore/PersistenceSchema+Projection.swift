import Foundation

extension PersistenceSchema {
    static let projectionSQL = """
    CREATE TABLE IF NOT EXISTS panel_projection (
        finding_id TEXT PRIMARY KEY REFERENCES findings(id) ON DELETE CASCADE,
        severity TEXT NOT NULL,
        status TEXT NOT NULL,
        candidate_or_verified TEXT NOT NULL,
        duplicate_flag BOOLEAN NOT NULL DEFAULT FALSE,
        recurrence_flag BOOLEAN NOT NULL DEFAULT FALSE,
        patch_available BOOLEAN NOT NULL DEFAULT FALSE,
        updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
    );
    CREATE TABLE IF NOT EXISTS review_chat_projection (
        run_id TEXT PRIMARY KEY,
        summary TEXT NOT NULL,
        verified_count INTEGER NOT NULL DEFAULT 0,
        candidate_count INTEGER NOT NULL DEFAULT 0,
        rejected_count INTEGER NOT NULL DEFAULT 0,
        needs_manual_review_count INTEGER NOT NULL DEFAULT 0,
        updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
    );
    CREATE TABLE IF NOT EXISTS main_chat_projection (
        finding_id TEXT PRIMARY KEY REFERENCES findings(id) ON DELETE CASCADE,
        card_summary TEXT NOT NULL,
        severity TEXT NOT NULL,
        status TEXT NOT NULL,
        patch_available BOOLEAN NOT NULL DEFAULT FALSE,
        updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
    );
    CREATE TABLE IF NOT EXISTS debug_projection (
        run_id TEXT PRIMARY KEY REFERENCES debug_runs(id) ON DELETE CASCADE,
        phase TEXT NOT NULL,
        status TEXT NOT NULL,
        error_summary TEXT,
        active_hypotheses_count INTEGER NOT NULL DEFAULT 0,
        marker_count INTEGER NOT NULL DEFAULT 0,
        breakpoint_count INTEGER NOT NULL DEFAULT 0,
        updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
    );
    CREATE TABLE IF NOT EXISTS plan_projection (
        plan_id TEXT PRIMARY KEY REFERENCES plans(id) ON DELETE CASCADE,
        conversation_id TEXT REFERENCES conversations(id) ON DELETE SET NULL,
        goal TEXT NOT NULL,
        status TEXT NOT NULL,
        step_count INTEGER NOT NULL DEFAULT 0,
        running_step_count INTEGER NOT NULL DEFAULT 0,
        completed_step_count INTEGER NOT NULL DEFAULT 0,
        updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
    );
    """

    static let archiveSQL = """
    CREATE TABLE IF NOT EXISTS pipeline_events_archive (LIKE pipeline_events INCLUDING ALL);
    CREATE TABLE IF NOT EXISTS plan_events_archive (LIKE plan_events INCLUDING ALL);
    CREATE TABLE IF NOT EXISTS debug_events_archive (LIKE debug_events INCLUDING ALL);
    CREATE TABLE IF NOT EXISTS audit_log_archive (LIKE audit_log INCLUDING ALL);
    CREATE TABLE IF NOT EXISTS debug_runtime_logs_archive (LIKE debug_runtime_logs INCLUDING ALL);
    """

    static let seedSQL = """
    INSERT INTO retention_jobs (id, job_kind, status, details)
    VALUES
        ('events-archive-90d', 'events_archive', 'idle', '{"retention_days":90}'::jsonb),
        ('audit-archive-90d', 'audit_archive', 'idle', '{"retention_days":90}'::jsonb)
    ON CONFLICT (id) DO NOTHING;
    """
}
