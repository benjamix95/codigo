import Foundation

extension ToolSchemaCatalog {
    static let debugTools: [ToolSchemaEntry] = [
        // MARK: Debug Tools (Optimized)
        ToolSchemaEntry(
            name: "debug_context",
            description: "Gather comprehensive debugging context for the current workspace. Use at the START of every debug session (Describe phase). Collects git state, build errors, linter diagnostics, environment info, recent crash logs, dependencies, and open file context. Use 'scope' to focus on specific areas.",
            properties: [
                "scope": ["type": "string", "description": "What to collect: 'full' (default, everything), 'git' (status/diff/log only), 'build' (build errors), 'lints' (linter diagnostics), 'env' (Swift/Xcode/SDK versions), 'tests' (test listing), 'crashes' (recent crash reports). Comma-separated for multiple."],
                "include_file_content": ["type": "string", "description": "If 'true', includes source code around files with errors (20 lines context). Default: false."],
                "max_depth": ["type": "string", "description": "Max depth for directory scanning (default: 3)"]
            ],
            required: []
        ),
        ToolSchemaEntry(
            name: "debug_log",
            description: "Write one or more entries to the debug log. Use throughout the debug session to record observations, findings, and evidence. Supports batch mode for multiple entries in one call. Use category='runtime' or 'instrumentation' for runtime logs that link to hypotheses.",
            properties: [
                "severity": ["type": "string", "description": "error|warning|info|verbose|trace"],
                "source": ["type": "string", "description": "Source component, file:line, or module name"],
                "message": ["type": "string", "description": "Log message describing the observation"],
                "detail": ["type": "string", "description": "Extended detail: stack trace, variable dump, error context"],
                "category": ["type": "string", "description": "Category: compiler, runtime, test, network, instrumentation, custom"],
                "tags": ["type": "string", "description": "Comma-separated tags for filtering (e.g. 'memory,leak,hypothesis-1')"],
                "stack_trace": ["type": "string", "description": "Full stack trace to attach (kept separate from detail for structured access)"],
                "hypothesis_id": ["type": "string", "description": "Link this log entry to a specific hypothesis"],
                "run_id": ["type": "string", "description": "Group logs by reproduce run"],
                "data": ["type": "string", "description": "JSON object of arbitrary key-value data (variable values, timing, etc.)"],
                "batch": ["type": "string", "description": "JSON array of log entries: [{severity, source, message, detail?, category?, tags?}, ...]. When provided, other fields are ignored."]
            ],
            required: ["severity", "source", "message"]
        ),
        ToolSchemaEntry(
            name: "debug_query",
            description: "Query and analyze debug logs with powerful filtering. Use to review observations, find patterns, and correlate evidence. Supports aggregation, time filtering, hypothesis linking, and export.",
            properties: [
                "severity": ["type": "string", "description": "Filter by severity: error, warning, info, verbose, trace"],
                "category": ["type": "string", "description": "Filter by category: compiler, runtime, test, network, instrumentation"],
                "source": ["type": "string", "description": "Filter by source component or file"],
                "search": ["type": "string", "description": "Full-text search across messages and details"],
                "tags": ["type": "string", "description": "Filter by tags (comma-separated, matches any)"],
                "hypothesis_id": ["type": "string", "description": "Show only logs linked to this hypothesis"],
                "time_range": ["type": "string", "description": "Show logs from last N minutes (e.g. '5' for last 5 minutes)"],
                "group_by": ["type": "string", "description": "Aggregate results: severity, source, category, tags. Returns counts per group."],
                "format": ["type": "string", "description": "'summary' (stats overview), 'full' (all entries), 'json' (structured JSON export), 'markdown' (formatted report)"],
                "limit": ["type": "string", "description": "Maximum entries to return (default: 50, max: 500)"]
            ],
            required: []
        ),
        ToolSchemaEntry(
            name: "debug_session",
            description: "Manage debug sessions with lifecycle control, snapshots, and export. Use 'start' at the beginning, 'snapshot' to save state for comparison, 'stats' for session metrics, 'export' for a full report, and 'stop' to finish after resolve.",
            properties: [
                "action": ["type": "string", "description": "start|end|stop|clear|snapshot|export|stats"],
                "label": ["type": "string", "description": "Label for snapshot (used with action=snapshot). Use descriptive names like 'before-fix', 'after-refactor'."]
            ],
            required: ["action"]
        ),
        ToolSchemaEntry(
            name: "debug_hypothesize",
            description: "Propose, update, or rank debug hypotheses with structured metadata. Each hypothesis tracks a potential root cause with confidence, evidence, related files, and type classification. Use during the Fix phase to systematically narrow down the bug.",
            properties: [
                "action": ["type": "string", "description": "propose (create new) | update (modify existing)"],
                "hypothesis_id": ["type": "string", "description": "Required for update; returned by propose"],
                "title": ["type": "string", "description": "Concise hypothesis title (required for propose)"],
                "description": ["type": "string", "description": "Detailed explanation of the hypothesized root cause"],
                "status": ["type": "string", "description": "proposed|investigating|confirmed|rejected"],
                "evidence": ["type": "string", "description": "Evidence notes supporting or refuting the hypothesis"],
                "confidence": ["type": "string", "description": "Confidence level 0-100 (0=wild guess, 100=certain). Helps rank hypotheses."],
                "root_cause_type": ["type": "string", "description": "Classification: logic, concurrency, config, dependency, state, memory, type, nil_safety, api_misuse"],
                "related_files": ["type": "string", "description": "Comma-separated file paths relevant to this hypothesis"],
                "related_tests": ["type": "string", "description": "Comma-separated test names that would verify/refute this hypothesis"]
            ],
            required: ["action"]
        ),
        ToolSchemaEntry(
            name: "debug_mark",
            description: "Insert a typed debug marker or instrumentation into a file. Supports plain markers, logging statements, assertions, timing measurements, and variable captures. All markers are tracked for automatic cleanup with debug_clean. Use during Reproduce/Fix phases.",
            properties: [
                "path": ["type": "string", "description": "File path to insert the marker"],
                "line": ["type": "string", "description": "Line number (1-based) where the marker is inserted AFTER"],
                "comment": ["type": "string", "description": "Human-readable comment describing what this marker checks"],
                "code": ["type": "string", "description": "Custom code to insert (overrides type-based generation)"],
                "type": ["type": "string", "description": "'marker' (comment only, default), 'log' (print statement), 'assert' (assertion), 'timing' (execution timing), 'variable' (variable state capture)"],
                "expression": ["type": "string", "description": "Expression to log/assert/capture. For 'log': the value to print. For 'assert': the condition. For 'variable': the variable name."],
                "hypothesis_id": ["type": "string", "description": "Link this marker to a hypothesis for correlation"]
            ],
            required: ["path", "line", "comment"]
        ),
        ToolSchemaEntry(
            name: "debug_clean",
            description: "Remove debug markers and instrumentation from files. Supports selective cleanup by type, dry-run preview, and hypothesis-scoped removal. Called automatically during 'Mark Fixed' flow, but can be used manually anytime.",
            properties: [
                "path": ["type": "string", "description": "Clean only this file. If omitted, searches entire workspace."],
                "type": ["type": "string", "description": "'all' (default), 'markers' (comment-only markers), 'logs' (print statements), 'asserts' (assertions), 'timing' (timing code), 'variables' (variable captures)"],
                "dry_run": ["type": "string", "description": "If 'true', shows what would be removed without actually removing. Useful for preview."],
                "hypothesis_id": ["type": "string", "description": "Remove only markers linked to this hypothesis"]
            ],
            required: []
        ),
        ToolSchemaEntry(
            name: "debug_set_phase",
            description: "Set the current debug flow phase in the IDE panel. Controls the progress bar visualization. Phases: describing (gather context) -> reproducing (reproduce the bug) -> fixing (hypothesize and fix) -> instrumenting (add instrumentation) -> verifying (run tests) -> resolved (done).",
            properties: [
                "phase": ["type": "string", "description": "describing|reproducing|fixing|instrumenting|verifying|resolved"],
                "detail": ["type": "string", "description": "Brief explanation of why this phase transition is happening"]
            ],
            required: ["phase"]
        ),
        ToolSchemaEntry(
            name: "debug_request_user",
            description: "Request user input during debugging. Use 'question' for clarifications, 'reproduce' to ask the user to trigger the bug, and 'fix_confirmation' to ask for final verification before cleanup.",
            properties: [
                "kind": ["type": "string", "description": "question|reproduce|fix_confirmation"],
                "prompt": ["type": "string", "description": "The question or step-by-step reproduction instructions"]
            ],
            required: ["kind", "prompt"]
        ),
        ToolSchemaEntry(
            name: "debug_resolve",
            description: "Resolve the debug session with a comprehensive final summary after cleanup. Include: root cause, fix applied, verification results, and any remaining risks.",
            properties: [
                "summary": ["type": "string", "description": "Final summary: root cause, fix applied, tests passed, and any caveats"]
            ],
            required: ["summary"]
        ),

    ]
}
