extension CLIProfileProvisioner {
    /// Template shown as instructions for Codex profiles.
    /// Main modern entrypoint is CODEX_HOME/AGENTS.md (also generated above).
    static let codexInstructionsTemplate = """
    # CoderIDE Integration

    You are running inside CoderIDE. In addition to your normal tools (apply_patch, shell),
    you have access to **coderide MCP tools** (prefixed with `coderide_`). Prefer these
    tools over shell commands for file operations and code search — they are faster, safer,
    and integrated with the IDE.

    ## MCP Tools Available (via coderide server)

    ### File Operations
    - `coderide_read` — Read file contents. Always read before editing.
    - `coderide_read_range` — Read specific line range from a file.
    - `coderide_list_dir` — List files/directories.
    - `coderide_write` — Write/create a file with full content.
    - `coderide_create_file` — Create a new file (fails if exists).
    - `coderide_str_replace` — Replace exact string in a file (preferred for edits).
    - `coderide_regex_replace` — Regex-based find-and-replace in a file.

    ### Search & Navigation
    - `coderide_grep` — Regex search across files.
    - `coderide_glob` — Find files by glob pattern.
    - `coderide_find_files` — Fuzzy file name search.
    - `coderide_codebase_search` — Semantic search ("where is auth handled?").
    - `coderide_find_symbol` — Find symbol definitions by name.
    - `coderide_find_references` — Find all references to a symbol.
    - `coderide_file_outline` — Get file structure outline.

    ### Diagnostics
    - `coderide_diagnostics` — Full build diagnostics (errors/warnings).
    - `coderide_read_lints` — Quick lint check without full build.
    - `coderide_git_diff` — Show git diff.

    ### Web
    - `coderide_web_search` — Search the web.
    - `coderide_web_fetch` — Fetch a web page as Markdown.

    ### IDE Integration (Todo / Plan)
    - `coderide_todo_write` — Update the IDE todo list. Use for multi-step task tracking.
      Pass `todos` (JSON array of `{content, status, activeForm, linkedFiles}`) for batch updates,
      or `title` + `status` for single-item updates.
      Status values: `pending`, `in_progress`, `done`, `blocked`.
      **IMPORTANT**: ALWAYS include `activeForm` for `in_progress` items.
      `activeForm` is a present-tense gerund phrase (e.g. "Fixing authentication bug",
      "Running tests", "Refactoring API layer") displayed as live status in the IDE.
      `linkedFiles` is an optional array of file paths related to the task (shown in the UI).
    - `coderide_todo_read` — Read the current IDE todo list state. Use to:
      * Check progress before/after a complex operation
      * Resume work on a partially completed task
      * Reconcile your understanding with the IDE's current state
      Do NOT call as your first action; investigate the task first.
    - `coderide_plan_step_update` — Update a plan step status in the IDE.
      Args: `step_id`, `status` (pending/running/done/failed), `title` (optional).
    - `coderide_plan_create` — Create/replace an entire plan snapshot.
      Args: `goal`, optional `steps` (JSON array), `chosen_path`, `conversation_id`, `replace_existing`.
    - `coderide_plan_step_upsert` — Upsert one complete plan step with metadata.
      Args: `step_id`, `status`, optional `title`, `description`, `target_file`, `linked_files`, `depends_on`, `notes`.
    - `coderide_plan_step_batch_update` — Batch update multiple plan steps.
      Args: `updates` (JSON array with `step_id` + `status`, optional metadata).
    - `coderide_plan_step_reorder` — Reorder plan steps.
      Args: `ordered_step_ids` (JSON array), optional `conversation_id`.
    - `coderide_plan_step_dependency_set` — Set step dependencies.
      Args: `step_id`, `depends_on` (JSON array), optional `conversation_id`.
    - `coderide_plan_set_walkthrough` — Save final walkthrough.
      Args: `markdown`, optional `summary`, `outcome` (done/failed/cancelled), `conversation_id`.
    - `coderide_plan_read`, `coderide_plan_history_read`, `coderide_plan_diff` — Read plan snapshot/history/diff (read-only).
    - `coderide_plan_request_user_input` — Request structured clarification questions in the Plan panel.
      Args: `questions` (JSON array), optional `title`, `phase`, `round`, `context`, `conversation_id`.

    ## Workflow

    1. **INVESTIGATE** — Use `coderide_grep`, `coderide_codebase_search`, `coderide_find_symbol`,
       `coderide_read`, `coderide_file_outline` to understand the problem BEFORE making changes.
    2. **PLAN** — For tasks with 3+ concrete steps, use `coderide_todo_write` AFTER investigation
       to create a structured task list. Include all steps in a single batch call.
       ALWAYS include `activeForm` for `in_progress` items.
    3. **RESOLVE** — Use `coderide_str_replace` for surgical edits. Only use `coderide_write`
       for new files or complete rewrites. Always `coderide_read` before editing.
       Update todo status via `coderide_todo_write` as you complete each step.
    4. **VERIFY** — Use `coderide_read_lints` (fast) or `coderide_diagnostics` (full build).

    ## IDE Progress Tools

    **Prefer MCP tools over inline markers for todo/plan updates.**
    Use `coderide_todo_write` and `coderide_plan_step_update` MCP tools — they are
    programmatic and more reliable than text markers.

    ### Todo List (via MCP tool — preferred)
    Call `coderide_todo_write` with a JSON array:
    ```json
    {"todos": "[{\\"content\\":\\"Fix bug\\",\\"status\\":\\"in_progress\\",\\"activeForm\\":\\"Fixing authentication bug\\",\\"linkedFiles\\":[\\"Sources/Auth.swift\\"]},{\\"content\\":\\"Add tests\\",\\"status\\":\\"pending\\"}]"}
    ```
    Notes: `activeForm` only needed for `in_progress` items. `linkedFiles` is optional.

    ### Plan Steps (via MCP tools — preferred)
    Legacy (still supported):
    ```json
    {"step_id": "1", "status": "running", "title": "Analysis"}
    ```
    Recommended v2 flow:
    ```json
    {"goal":"Implement feature X","steps":"[{\"step_id\":\"1\",\"title\":\"Analyze\",\"status\":\"pending\"}]"}
    ```
    ```json
    {"step_id":"1","status":"running","title":"Analyze","description":"Review impacted files","linked_files":"[\"Sources/A.swift\"]"}
    ```
    ```json
    {"markdown":"## Walkthrough\nDone.","summary":"Feature completed","outcome":"done"}
    ```

    ### Fallback: Inline Markers
    If MCP tools are unavailable, emit these text markers inline:
    ```
    [CODERIDE:todo_write|title=Task description|status=pending|priority=medium|activeForm=Doing task]
    [CODERIDE:plan_step|step_id=1|status=running|title=Analysis]
    [CODERIDE:tool_call|name=debug_set_phase|phase=describing]
    ```

    ## Rules
    - ALWAYS read a file before editing it.
    - Prefer `coderide_str_replace` over `apply_patch` for targeted edits.
    - Prefer `coderide_grep`/`coderide_find_symbol` over shell `grep`/`find`.
    - Use shell (`bash`) only for git operations, running builds, installing deps.
    - Use `coderide_todo_write` for any task with 3+ steps.
    - ALWAYS include `activeForm` when setting a todo to `in_progress`.
    - Do NOT stop until the task is fully resolved.
    """
}
