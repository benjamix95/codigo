import Foundation

extension PersistenceSchema {
    static let debugSQL = """
    CREATE TABLE IF NOT EXISTS debug_runs (
        id TEXT PRIMARY KEY,
        conversation_id TEXT REFERENCES conversations(id) ON DELETE SET NULL,
        workspace_id TEXT REFERENCES workspaces(id) ON DELETE SET NULL,
        review_session_id TEXT REFERENCES review_sessions(session_id) ON DELETE SET NULL,
        target_scope TEXT,
        phase TEXT NOT NULL,
        status TEXT NOT NULL,
        error_summary TEXT,
        resolution_summary TEXT,
        fix_loop_iteration INTEGER NOT NULL DEFAULT 0,
        native_target_path TEXT,
        native_arguments TEXT,
        current_run_id TEXT,
        user_confirmed_reproduce BOOLEAN NOT NULL DEFAULT FALSE,
        awaiting_debug_clean BOOLEAN NOT NULL DEFAULT FALSE,
        version BIGINT NOT NULL DEFAULT 1,
        created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
        updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
    );
    CREATE TABLE IF NOT EXISTS debug_steps (
        id TEXT PRIMARY KEY,
        run_id TEXT NOT NULL REFERENCES debug_runs(id) ON DELETE CASCADE,
        step_type TEXT NOT NULL,
        description TEXT NOT NULL,
        result TEXT,
        created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
        updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
    );
    CREATE TABLE IF NOT EXISTS debug_events (
        id TEXT PRIMARY KEY,
        run_id TEXT NOT NULL REFERENCES debug_runs(id) ON DELETE CASCADE,
        event_type TEXT NOT NULL,
        payload JSONB NOT NULL DEFAULT '{}'::jsonb,
        event_schema_version INTEGER NOT NULL DEFAULT 1,
        entity_schema_version INTEGER NOT NULL DEFAULT 1,
        migration_hint TEXT,
        created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
    );
    CREATE TABLE IF NOT EXISTS debug_artifacts (
        id TEXT PRIMARY KEY,
        run_id TEXT NOT NULL REFERENCES debug_runs(id) ON DELETE CASCADE,
        artifact_type TEXT NOT NULL,
        payload JSONB NOT NULL DEFAULT '{}'::jsonb,
        created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
    );
    CREATE TABLE IF NOT EXISTS debug_logs (
        id TEXT PRIMARY KEY,
        run_id TEXT NOT NULL REFERENCES debug_runs(id) ON DELETE CASCADE,
        severity TEXT NOT NULL,
        source TEXT NOT NULL,
        message TEXT NOT NULL,
        detail TEXT,
        category TEXT,
        created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
    );
    CREATE TABLE IF NOT EXISTS debug_hypotheses (
        id TEXT PRIMARY KEY,
        run_id TEXT NOT NULL REFERENCES debug_runs(id) ON DELETE CASCADE,
        title TEXT NOT NULL,
        description TEXT NOT NULL,
        status TEXT NOT NULL,
        evidence JSONB NOT NULL DEFAULT '[]'::jsonb,
        created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
    );
    CREATE TABLE IF NOT EXISTS debug_markers (
        id TEXT PRIMARY KEY,
        run_id TEXT NOT NULL REFERENCES debug_runs(id) ON DELETE CASCADE,
        file_path TEXT NOT NULL,
        line_number INTEGER NOT NULL,
        marker_comment TEXT NOT NULL,
        original_content TEXT,
        inserted_at TIMESTAMPTZ NOT NULL
    );
    CREATE TABLE IF NOT EXISTS debug_instrumentation_points (
        id TEXT PRIMARY KEY,
        run_id TEXT NOT NULL REFERENCES debug_runs(id) ON DELETE CASCADE,
        file_path TEXT NOT NULL,
        line_number INTEGER NOT NULL,
        type TEXT NOT NULL,
        code TEXT NOT NULL,
        hypothesis_id TEXT,
        inserted_at TIMESTAMPTZ NOT NULL
    );
    CREATE TABLE IF NOT EXISTS debug_breakpoints (
        id TEXT PRIMARY KEY,
        run_id TEXT NOT NULL REFERENCES debug_runs(id) ON DELETE CASCADE,
        file_path TEXT NOT NULL,
        line_number INTEGER NOT NULL,
        condition TEXT,
        is_active BOOLEAN NOT NULL DEFAULT TRUE,
        created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
    );
    CREATE TABLE IF NOT EXISTS debug_runtime_logs (
        id TEXT PRIMARY KEY,
        run_id TEXT NOT NULL REFERENCES debug_runs(id) ON DELETE CASCADE,
        location TEXT NOT NULL,
        message TEXT NOT NULL,
        data JSONB NOT NULL DEFAULT '{}'::jsonb,
        session_correlation_id TEXT,
        reproduce_run_id TEXT,
        hypothesis_id TEXT,
        created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
    );
    CREATE TABLE IF NOT EXISTS debug_snapshots (
        id TEXT PRIMARY KEY,
        run_id TEXT NOT NULL REFERENCES debug_runs(id) ON DELETE CASCADE,
        snapshot_label TEXT NOT NULL,
        snapshot_payload JSONB NOT NULL,
        created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
    );
    """
}
