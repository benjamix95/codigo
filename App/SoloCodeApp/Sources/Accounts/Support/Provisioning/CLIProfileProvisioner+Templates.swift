extension CLIProfileProvisioner {
    /// Template shown as instructions for Codex profiles.
    /// Main modern entrypoint is CODEX_HOME/AGENTS.md (also generated above).
    static let codexInstructionsTemplate = """
    # CoderIDE Integration

    You are running inside CoderIDE. In addition to your normal tools (apply_patch, shell),
    you have access to **coderide MCP tools** (prefixed with `coderide_`). These are the
    approved tools for workspace discovery, search, file inspection, and file editing.
    Do NOT use shell `grep`/`rg`/`find`/`fd`/`cat`/`ls`/`tree` for workspace inspection when
    a `coderide_*` tool exists — use the MCP tool instead.

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
    - `coderide_semantic_search` — Meaning-first code search for natural-language queries.
    - `coderide_grep` — Instant grep for exact text/regex search across files.
    - `coderide_glob` — Find files by glob pattern.
    - `coderide_find_files` — Fuzzy file name search.
    - `coderide_codebase_search` — Indexed symbol/code search.
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

    1. **INVESTIGATE** — Use `coderide_semantic_search` for intent/meaning queries,
       `coderide_grep` for exact text or regex, `coderide_codebase_search` / `coderide_find_symbol`
       for indexed symbol lookup, and `coderide_read` / `coderide_file_outline` for file inspection
       BEFORE making changes.
    2. **TODO WORKFLOW (USE ONLY WHEN TRULY NEEDED)** — After investigation, create todos only if
       the task is genuinely multi-step (for example 3+ concrete or interdependent steps).
       If the task is simple (single action or <=2 concrete operations), do NOT emit todo markers.
       When todos are needed, create one coherent list with concrete executable steps only,
       never placeholder items like "Task", "Analysis", "Step 1", or "Todo update".
       Emit the first `coderide_todo_write` update BEFORE the first command/edit/tool action,
       and ALWAYS include `activeForm` for `in_progress` items.
       Emit `coderide_show_task_panel` only when a real todo list exists or when the user explicitly asks.
       Use `coderide_todo_read` only for resume/reconciliation, never as the default first action.
    3. **RESOLVE** — Use `coderide_str_replace` for surgical edits. Only use `coderide_write`
       for new files or complete rewrites. Always `coderide_read` before editing.
       Update todo status via `coderide_todo_write` only for real tasks: `in_progress` before work,
       `done` after completion, `blocked` only when genuinely blocked.
    4. **VERIFY** — Use `coderide_read_lints` (fast) or `coderide_diagnostics` (full build).
    5. **FINALIZE** — If provider-native subagent/task capability is available for the current provider/runtime,
       prefer that native delegation path. Do NOT use `coderide_subagent_*` as a proxy for real subagent execution
       in main chat. Before finalizing an implementation task, run
       `subagent_reviewer` and `subagent_testWriter`.

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
    - Prefer `coderide_semantic_search`, `coderide_grep`, `coderide_codebase_search`, `coderide_find_symbol`,
      `coderide_read`, `coderide_list_dir`, `coderide_find_files`, and `coderide_glob` for workspace work.
    - Shell `bash` is allowed for git operations, builds, tests, and dependency management only.
      Never use shell `grep`, `rg`, `find`, `fd`, `cat`, `ls`, or `tree` for workspace discovery when
      a `coderide_*` tool is available.
    - Use `coderide_todo_write` only when the task is truly multi-step after investigation.
    - ALWAYS include `activeForm` when setting a todo to `in_progress`.
    - Do NOT emit todo markers for simple single-action tasks or tasks with <=2 concrete operations.
    - Never create placeholder todos.
    - If the context includes `[CODERIDE:policy_ack|hash=...]`, emit it once before any operational tool action.
    - Do NOT stop until the task is fully resolved.
    """
}
