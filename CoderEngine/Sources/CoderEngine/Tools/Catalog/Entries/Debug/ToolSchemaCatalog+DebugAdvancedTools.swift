import Foundation

extension ToolSchemaCatalog {
    static let advancedTools: [ToolSchemaEntry] = [
        // MARK: Debug Advanced Tools (New)
        ToolSchemaEntry(
            name: "debug_trace_analyze",
            description: "Analyze an error message, stack trace, crash log, or test failure output. Parses the text structurally, extracts file paths and line numbers, identifies the error type, and suggests files to investigate. Use in the Describe phase right after debug_context.",
            properties: [
                "error_text": ["type": "string", "description": "The error output, stack trace, crash log, or test failure to analyze"],
                "error_type": ["type": "string", "description": "'compile' (build errors), 'runtime' (crashes/exceptions), 'crash' (crash reports), 'test_failure' (test assertions), 'assertion' (precondition/assert). Auto-detected if omitted."],
                "context": ["type": "string", "description": "Additional context about when/where the error occurs"]
            ],
            required: ["error_text"]
        ),
        ToolSchemaEntry(
            name: "debug_instrument",
            description: "Insert intelligent, executable instrumentation code into a source file. More powerful than debug_mark: generates real Swift code for logging, assertions, timing measurements, variable captures, and conditional breakpoints. All instrumentation is tracked and auto-cleaned on session resolve.",
            properties: [
                "path": ["type": "string", "description": "File to instrument"],
                "line": ["type": "string", "description": "Line number (1-based) — code is inserted AFTER this line"],
                "type": ["type": "string", "description": "'log' (print expression value), 'assert' (assert condition), 'timing' (measure execution time of the enclosing scope), 'variable' (capture and print variable state), 'conditional_break' (log only when condition is true)"],
                "expression": ["type": "string", "description": "The expression to log/assert/capture. For 'log': value to print. For 'assert': boolean condition. For 'variable': variable name. For 'conditional_break': guard condition."],
                "condition": ["type": "string", "description": "For 'conditional_break': only log when this condition is true. For 'assert': custom failure message."],
                "hypothesis_id": ["type": "string", "description": "Link this instrumentation to a hypothesis"],
                "label": ["type": "string", "description": "Human-readable label for this instrumentation point (shown in debug panel)"]
            ],
            required: ["path", "line", "type", "expression"]
        ),
        ToolSchemaEntry(
            name: "debug_timeline",
            description: "Generate a chronological timeline of all debug events in the current session: logs, phase changes, hypotheses, markers, instrumentation. Helps understand the sequence of observations and decisions. Use for analysis and final reporting.",
            properties: [
                "filter": ["type": "string", "description": "'all' (default), 'logs', 'hypotheses', 'markers', 'phases'. Comma-separated for multiple."],
                "time_range": ["type": "string", "description": "Show events from last N minutes"],
                "hypothesis_id": ["type": "string", "description": "Show only events linked to this hypothesis"],
                "format": ["type": "string", "description": "'text' (default, chronological list), 'mermaid' (Mermaid sequence diagram)"]
            ],
            required: []
        ),
        ToolSchemaEntry(
            name: "debug_snapshot",
            description: "Capture, compare, or list debug session snapshots. Snapshots save the full debug state (phase, hypotheses, markers, log counts, file changes) at a point in time. Use before and after each fix attempt to track progress and detect regressions.",
            properties: [
                "action": ["type": "string", "description": "'capture' (save current state), 'compare' (diff two snapshots), 'list' (show all snapshots)"],
                "label": ["type": "string", "description": "Descriptive label for the snapshot (e.g. 'before-fix', 'after-refactor'). Required for capture."],
                "compare_with": ["type": "string", "description": "Label of the snapshot to compare against (used with action=compare)"]
            ],
            required: ["action"]
        ),
        ToolSchemaEntry(
            name: "debug_test_check",
            description: "Run a targeted Swift Package test check to verify a fix or detect regressions. More focused than run_tests: identifies tests related to specific files, runs only those, and compares results with previous runs. Use in the Verify phase after applying a fix.",
            properties: [
                "scope": ["type": "string", "description": "'all' (run all tests), 'related' (tests related to modified files), 'failing' (only previously failing tests), 'file' (tests in/for a specific file)"],
                "path": ["type": "string", "description": "File path to find related tests for (used with scope=file or scope=related)"],
                "filter": ["type": "string", "description": "Test name filter pattern"],
                "hypothesis_id": ["type": "string", "description": "Run tests related to the files in this hypothesis"],
                "timeout_ms": ["type": "string", "description": "Timeout in milliseconds (default: 60000)"]
            ],
            required: []
        ),
        ToolSchemaEntry(
            name: "todo_write",
            description: "Create or update todo items in the LiveCard/task panel",
            properties: [
                "title": ["type": "string", "description": "Todo title (single-item mode)"],
                "status": ["type": "string", "description": "pending|in_progress|done|blocked"],
                "priority": ["type": "string", "description": "low|medium|high"],
                "notes": ["type": "string", "description": "Optional note"],
                "activeForm": ["type": "string", "description": "Optional present-tense activity label"],
                "linkedFiles": ["type": "string", "description": "Optional JSON array of related file paths"],
                "todos": ["type": "string", "description": "Optional batch todo collection. Accepts a JSON array string; richer runtimes may also pass a structured array or checklist text."]
            ],
            required: []
        ),
        ToolSchemaEntry(
            name: "todo_read",
            description: "Read the current todo list from the LiveCard/task panel",
            properties: [:],
            required: []
        ),
        ToolSchemaEntry(
            name: "plan_step_update",
            description: "Update a plan step status in the plan panel",
            properties: [
                "step_id": ["type": "string", "description": "Plan step identifier"],
                "status": ["type": "string", "description": "pending|running|done|failed"],
                "title": ["type": "string", "description": "Optional step title"]
            ],
            required: ["step_id", "status"]
        ),
        ToolSchemaEntry(
            name: "mermaid_render",
            description: "Render a Mermaid diagram in the IDE plan/chat panels",
            properties: [
                "code": ["type": "string", "description": "Mermaid diagram source code"],
                "title": ["type": "string", "description": "Optional diagram title"]
            ],
            required: ["code"]
        ),
        ToolSchemaEntry(
            name: "policy_ack",
            description: "Acknowledge the required policy hash before operational tool calls",
            properties: [
                "hash": ["type": "string", "description": "Policy hash from context"]
            ],
            required: ["hash"]
        ),
        ToolSchemaEntry(
            name: "activate_plan_mode",
            description: "Activate the plan panel in the IDE",
            properties: [
                "reason": ["type": "string", "description": "Optional reason for activation"]
            ],
            required: []
        ),
        ToolSchemaEntry(
            name: "activate_debug_mode",
            description: "Activate the debug panel in the IDE",
            properties: [
                "reason": ["type": "string", "description": "Optional reason for activation"]
            ],
            required: []
        ),
        ToolSchemaEntry(
            name: "show_task_panel",
            description: "Open/focus the task panel in the IDE",
            properties: [:],
            required: []
        ),
        ToolSchemaEntry(
            name: "show_swarm_panel",
            description: "Open/focus the swarm panel in the IDE",
            properties: [
                "swarm_id": ["type": "string", "description": "Optional swarm id to focus"]
            ],
            required: []
        ),
        ToolSchemaEntry(
            name: "subagent_explorer",
            description: "Spawn a read-only explorer subagent for parallel codebase investigation",
            properties: [
                "task": ["type": "string", "description": "Task to investigate"]
            ],
            required: ["task"]
        ),
        ToolSchemaEntry(
            name: "subagent_coder",
            description: "Spawn a coding subagent for implementation work",
            properties: [
                "task": ["type": "string", "description": "Implementation task"]
            ],
            required: ["task"]
        ),
        ToolSchemaEntry(
            name: "subagent_debugger",
            description: "Spawn a debugger subagent for bug investigation/fixes",
            properties: [
                "task": ["type": "string", "description": "Debug task"]
            ],
            required: ["task"]
        ),
        ToolSchemaEntry(
            name: "subagent_reviewer",
            description: "Spawn a reviewer subagent for quality/code-review checks",
            properties: [
                "task": ["type": "string", "description": "Review task"]
            ],
            required: ["task"]
        ),
        ToolSchemaEntry(
            name: "subagent_testWriter",
            description: "Spawn a test-writer subagent for test creation and verification",
            properties: [
                "task": ["type": "string", "description": "Testing task"]
            ],
            required: ["task"]
        ),
        ToolSchemaEntry(
            name: "subagent_tester",
            description: "Legacy alias of subagent_testWriter",
            properties: [
                "task": ["type": "string", "description": "Testing task"]
            ],
            required: ["task"]
        ),
        ToolSchemaEntry(
            name: "subagent_docWriter",
            description: "Spawn a documentation subagent for docs/changelog updates",
            properties: [
                "task": ["type": "string", "description": "Documentation task"]
            ],
            required: ["task"]
        ),
        ToolSchemaEntry(
            name: "subagent_securityAuditor",
            description: "Spawn a security-auditor subagent for security analysis",
            properties: [
                "task": ["type": "string", "description": "Security audit task"]
            ],
            required: ["task"]
        ),
    ]
}
