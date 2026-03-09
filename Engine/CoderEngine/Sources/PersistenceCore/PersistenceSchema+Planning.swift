import Foundation

extension PersistenceSchema {
    static let planningSQL = """
    CREATE TABLE IF NOT EXISTS plans (
        id TEXT PRIMARY KEY,
        conversation_id TEXT REFERENCES conversations(id) ON DELETE SET NULL,
        workspace_id TEXT REFERENCES workspaces(id) ON DELETE SET NULL,
        title TEXT NOT NULL,
        status TEXT NOT NULL,
        goal TEXT NOT NULL,
        chosen_path_summary TEXT,
        walkthrough_markdown TEXT,
        summary TEXT,
        outcome TEXT,
        version BIGINT NOT NULL DEFAULT 1,
        created_at TIMESTAMPTZ NOT NULL,
        updated_at TIMESTAMPTZ NOT NULL
    );
    CREATE TABLE IF NOT EXISTS plan_steps (
        id TEXT PRIMARY KEY,
        plan_id TEXT NOT NULL REFERENCES plans(id) ON DELETE CASCADE,
        step_index INTEGER NOT NULL,
        title TEXT NOT NULL,
        description TEXT NOT NULL,
        target_file TEXT,
        status TEXT NOT NULL,
        notes TEXT,
        linked_files JSONB NOT NULL DEFAULT '[]'::jsonb,
        updated_at TIMESTAMPTZ NOT NULL
    );
    CREATE TABLE IF NOT EXISTS plan_step_dependencies (
        plan_id TEXT NOT NULL REFERENCES plans(id) ON DELETE CASCADE,
        step_id TEXT NOT NULL REFERENCES plan_steps(id) ON DELETE CASCADE,
        depends_on_step_id TEXT NOT NULL,
        PRIMARY KEY (plan_id, step_id, depends_on_step_id)
    );
    CREATE TABLE IF NOT EXISTS plan_snapshots (
        id TEXT PRIMARY KEY,
        plan_id TEXT NOT NULL REFERENCES plans(id) ON DELETE CASCADE,
        conversation_id TEXT REFERENCES conversations(id) ON DELETE SET NULL,
        goal TEXT NOT NULL,
        chosen_path_summary TEXT,
        summary TEXT,
        outcome TEXT,
        signature TEXT NOT NULL,
        snapshot_payload JSONB NOT NULL,
        created_at TIMESTAMPTZ NOT NULL,
        updated_at TIMESTAMPTZ NOT NULL
    );
    CREATE TABLE IF NOT EXISTS plan_snapshot_steps (
        id BIGSERIAL PRIMARY KEY,
        snapshot_id TEXT NOT NULL REFERENCES plan_snapshots(id) ON DELETE CASCADE,
        step_id TEXT NOT NULL,
        step_index INTEGER NOT NULL,
        title TEXT NOT NULL,
        description TEXT NOT NULL,
        target_file TEXT,
        status TEXT NOT NULL,
        linked_files JSONB NOT NULL DEFAULT '[]'::jsonb,
        depends_on JSONB NOT NULL DEFAULT '[]'::jsonb,
        notes TEXT,
        updated_at TIMESTAMPTZ NOT NULL
    );
    CREATE TABLE IF NOT EXISTS plan_events (
        id TEXT PRIMARY KEY,
        plan_id TEXT NOT NULL REFERENCES plans(id) ON DELETE CASCADE,
        event_type TEXT NOT NULL,
        payload JSONB NOT NULL DEFAULT '{}'::jsonb,
        event_schema_version INTEGER NOT NULL DEFAULT 1,
        entity_schema_version INTEGER NOT NULL DEFAULT 1,
        migration_hint TEXT,
        created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
    );
    CREATE TABLE IF NOT EXISTS plan_user_input_requests (
        id TEXT PRIMARY KEY,
        plan_id TEXT REFERENCES plans(id) ON DELETE CASCADE,
        conversation_id TEXT REFERENCES conversations(id) ON DELETE SET NULL,
        title TEXT,
        phase TEXT,
        round INTEGER,
        context TEXT,
        questionnaire JSONB NOT NULL DEFAULT '{}'::jsonb,
        status TEXT NOT NULL DEFAULT 'pending',
        created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
        updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
    );
    CREATE TABLE IF NOT EXISTS plan_history_entries (
        id TEXT PRIMARY KEY,
        conversation_id TEXT REFERENCES conversations(id) ON DELETE SET NULL,
        context_id TEXT,
        context_folder_path TEXT,
        title TEXT NOT NULL,
        markdown TEXT NOT NULL,
        chosen_path TEXT,
        tags JSONB NOT NULL DEFAULT '[]'::jsonb,
        source_message_id TEXT,
        is_pinned BOOLEAN NOT NULL DEFAULT FALSE,
        rebuild_count INTEGER NOT NULL DEFAULT 0,
        last_build_at TIMESTAMPTZ,
        created_at TIMESTAMPTZ NOT NULL,
        updated_at TIMESTAMPTZ NOT NULL
    );
    """
}
