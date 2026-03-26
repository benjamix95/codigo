import Foundation
import MCP

/// Debug panel tools (`coderide_debug_*`, fasi tipizzate in `CoderIDETools+IdeIntegration.swift`): **non** sono nel
/// catalogo Rust `Native/CoderideMCPServerRust/src/tool_names.txt` (116 tool). Restano solo
/// in Swift per allowlist/host; il server MCP Rust espone un sottoinsieme diverso.
extension CoderIDETools {
    static let debugTools: [Tool] = [
        // --- Debug Tools ---
        Tool(
            name: "coderide_debug_context",
            description: """
                Gather full debug context in one call: git status, open files, lint errors, \
                recent commits, debug log summary. Use this FIRST when entering debug mode.
                """,
            inputSchema: .object([
                "type": "object",
                "properties": .object([
                    "scope": .object([
                        "type": "string",
                        "description": "What to collect: full (default), git, build, lints, env, tests, crashes. Comma-separated for multiple."
                    ]),
                    "include_file_content": .object([
                        "type": "string",
                        "description": "If true, include source snippets near lint errors."
                    ]),
                    "max_depth": .object([
                        "type": "string",
                        "description": "Max relative path depth for included source snippets (default: 3)."
                    ]),
                ]),
            ]),
            annotations: .init(title: "Debug Context", readOnlyHint: true)
        ),
        Tool(
            name: "coderide_debug_log",
            description: "Write one or more entries to the debug log. Provide severity/source/message for single-entry mode, or use batch for multi-entry mode.",
            inputSchema: .object([
                "type": "object",
                "properties": .object([
                    "severity": .object(["type": "string", "description": "Log severity: error, warning, info, verbose, trace"]),
                    "source": .object(["type": "string", "description": "Source location (e.g. 'NetworkManager.swift:42')"]),
                    "message": .object(["type": "string", "description": "Log message"]),
                    "detail": .object(["type": "string", "description": "Optional detail (e.g. stack trace)"]),
                    "category": .object(["type": "string", "description": "Optional category: compiler, runtime, test, network, custom, instrumentation"]),
                    "tags": .object(["type": "string", "description": "Optional comma-separated tags for filtering"]),
                    "stack_trace": .object(["type": "string", "description": "Optional stack trace kept as a structured field"]),
                    "data": .object(["type": "string", "description": "Optional key-value data as JSON object (e.g. {\"var\":\"value\"})"]),
                    "run_id": .object(["type": "string", "description": "Optional reproduce run ID to group logs"]),
                    "hypothesis_id": .object(["type": "string", "description": "Optional hypothesis ID this log supports"]),
                    "batch": .object(["type": "string", "description": "Optional JSON array for batch logging: [{severity,source,message,...}]"]),
                ]),
                "required": .array([]),
            ]),
            annotations: .init(title: "Debug Log")
        ),
        Tool(
            name: "coderide_debug_query",
            description: "Query the debug log. Filter by severity, category, source, or text search.",
            inputSchema: .object([
                "type": "object",
                "properties": .object([
                    "severity": .object(["type": "string", "description": "Filter by severity"]),
                    "category": .object(["type": "string", "description": "Filter by category"]),
                    "source": .object(["type": "string", "description": "Filter by source"]),
                    "search": .object(["type": "string", "description": "Text search in log messages"]),
                    "tags": .object(["type": "string", "description": "Comma-separated tags (matches any)"]),
                    "hypothesis_id": .object(["type": "string", "description": "Filter logs linked to one hypothesis"]),
                    "time_range": .object(["type": "string", "description": "Show logs from last N minutes"]),
                    "session_id": .object(["type": "string", "description": "Filter to one debug session ID"]),
                    "group_by": .object(["type": "string", "description": "Aggregate by severity|source|category|tags"]),
                    "format": .object(["type": "string", "description": "Output format: summary or full (default: summary)"]),
                    "limit": .object(["type": "string", "description": "Max results (default: 100)"]),
                    "offset": .object(["type": "string", "description": "Pagination offset"]),
                ]),
            ]),
            annotations: .init(title: "Debug Query", readOnlyHint: true)
        ),
        Tool(
            name: "coderide_debug_session",
            description: "Manage debug sessions and lifecycle snapshots. Supports start, export, stop/end, clear, snapshot, and stats.",
            inputSchema: .object([
                "type": "object",
                "properties": .object([
                    "action": .object(["type": "string", "description": "Session action: start, end, stop, clear, snapshot, export, stats"]),
                    "label": .object(["type": "string", "description": "Optional snapshot label (used with action=snapshot)"]),
                ]),
                "required": .array([.string("action")]),
            ]),
            annotations: .init(title: "Debug Session")
        ),
        Tool(
            name: "coderide_debug_hypothesize",
            description: "Propose or update a debug hypothesis. Track investigation progress with structured hypotheses.",
            inputSchema: .object([
                "type": "object",
                "properties": .object([
                    "action": .object(["type": "string", "description": "Action: propose (new) or update (existing)"]),
                    "hypothesis_id": .object(["type": "string", "description": "Required for update — the hypothesis ID to update"]),
                    "title": .object(["type": "string", "description": "Required for propose — hypothesis title"]),
                    "description": .object(["type": "string", "description": "Detailed description of the hypothesis"]),
                    "status": .object(["type": "string", "description": "Status: proposed, investigating, confirmed, rejected"]),
                    "evidence": .object(["type": "string", "description": "Supporting evidence for the hypothesis"]),
                    "confidence": .object(["type": "string", "description": "Confidence level 0-100"]),
                    "root_cause_type": .object(["type": "string", "description": "Root cause classification"]),
                    "related_files": .object(["type": "string", "description": "Comma-separated related files"]),
                    "related_tests": .object(["type": "string", "description": "Comma-separated related tests"]),
                ]),
                "required": .array([.string("action")]),
            ]),
            annotations: .init(title: "Debug Hypothesize")
        ),
        Tool(
            name: "coderide_debug_mark",
            description: "Insert a debug marker (print/log/assert) into a file. The marker is tagged with 🐛 DEBUG for easy cleanup.",
            inputSchema: .object([
                "type": "object",
                "properties": .object([
                    "path": .object(["type": "string", "description": "File path to insert the marker"]),
                    "line": .object(["type": "string", "description": "Line number to insert at"]),
                    "comment": .object(["type": "string", "description": "Description of what's being debugged"]),
                    "code": .object(["type": "string", "description": "Optional code to insert (e.g. print statement)"]),
                    "type": .object(["type": "string", "description": "marker|log|assert|timing|variable"]),
                    "expression": .object(["type": "string", "description": "Expression for generated marker types"]),
                    "hypothesis_id": .object(["type": "string", "description": "Link marker to a hypothesis"]),
                ]),
                "required": .array([.string("path"), .string("line"), .string("comment")]),
            ]),
            annotations: .init(title: "Debug Mark")
        ),
        Tool(
            name: "coderide_debug_clean",
            description: "Remove ALL debug markers (lines containing 🐛 DEBUG) from a file or entire workspace.",
            inputSchema: .object([
                "type": "object",
                "properties": .object([
                    "path": .object(["type": "string", "description": "Optional file path — cleans all files if omitted"]),
                    "type": .object(["type": "string", "description": "all|markers|logs|asserts|timing|variables"]),
                    "dry_run": .object(["type": "string", "description": "If true, previews removals without changing files"]),
                    "hypothesis_id": .object(["type": "string", "description": "Clean only markers tied to one hypothesis"]),
                ]),
            ]),
            annotations: .init(title: "Debug Clean")
        ),
        Tool(
            name: "coderide_debug_trace_analyze",
            description: "Analyze stack traces, compiler errors, and crash output into actionable findings.",
            inputSchema: .object([
                "type": "object",
                "properties": .object([
                    "error_text": .object(["type": "string", "description": "Raw error or trace text to analyze"]),
                    "error_type": .object(["type": "string", "description": "Optional hint: compile, runtime, crash, test_failure, assertion"]),
                    "context": .object(["type": "string", "description": "Optional extra debugging context"]),
                ]),
                "required": .array([.string("error_text")]),
            ]),
            annotations: .init(title: "Debug Trace Analyze", readOnlyHint: true)
        ),
        Tool(
            name: "coderide_debug_instrument",
            description: "Insert executable instrumentation code at a location in source.",
            inputSchema: .object([
                "type": "object",
                "properties": .object([
                    "path": .object(["type": "string", "description": "File to instrument"]),
                    "line": .object(["type": "string", "description": "Line number (1-based) to insert after"]),
                    "type": .object(["type": "string", "description": "log|assert|timing|variable|conditional_break"]),
                    "expression": .object(["type": "string", "description": "Expression for instrumentation"]),
                    "condition": .object(["type": "string", "description": "Optional condition / assert message"]),
                    "hypothesis_id": .object(["type": "string", "description": "Link instrumentation to hypothesis"]),
                    "label": .object(["type": "string", "description": "Human label shown in debug UI"]),
                ]),
                "required": .array([.string("path"), .string("line"), .string("type"), .string("expression")]),
            ]),
            annotations: .init(title: "Debug Instrument")
        ),
        Tool(
            name: "coderide_debug_timeline",
            description: "Build chronological timeline of debug events.",
            inputSchema: .object([
                "type": "object",
                "properties": .object([
                    "filter": .object(["type": "string", "description": "all|logs|hypotheses|markers|phases (comma-separated)"]),
                    "time_range": .object(["type": "string", "description": "Last N minutes"]),
                    "hypothesis_id": .object(["type": "string", "description": "Filter by hypothesis id"]),
                    "format": .object(["type": "string", "description": "text (default) or mermaid"]),
                ]),
            ]),
            annotations: .init(title: "Debug Timeline", readOnlyHint: true)
        ),
        Tool(
            name: "coderide_debug_snapshot",
            description: "Capture and compare debug session snapshots.",
            inputSchema: .object([
                "type": "object",
                "properties": .object([
                    "action": .object(["type": "string", "description": "capture|compare|list"]),
                    "label": .object(["type": "string", "description": "Snapshot label"]),
                    "compare_with": .object(["type": "string", "description": "Snapshot label to compare against"]),
                ]),
                "required": .array([.string("action")]),
            ]),
            annotations: .init(title: "Debug Snapshot", readOnlyHint: true)
        ),
        Tool(
            name: "coderide_debug_test_check",
            description: "Run targeted Xcode test verification for a debug fix in the Solo Code workspace.",
            inputSchema: .object([
                "type": "object",
                "properties": .object([
                    "scope": .object(["type": "string", "description": "all|related|failing|file|integration"]),
                    "path": .object(["type": "string", "description": "File path used by scope=file/related"]),
                    "filter": .object(["type": "string", "description": "Optional test filter"]),
                    "hypothesis_id": .object(["type": "string", "description": "Use files linked to hypothesis"]),
                    "timeout_ms": .object(["type": "string", "description": "Timeout in milliseconds"]),
                ]),
            ]),
            annotations: .init(title: "Debug Test Check")
        ),
        // --- Debug IDE Control Tools (phase, user interaction, resolution) ---
        Tool(
            name: "coderide_debug_set_phase",
            description: "Set the current debug flow phase. Controls the debug panel progress bar and phase-specific UI.",
            inputSchema: .object([
                "type": "object",
                "properties": .object([
                    "phase": .object(["type": "string", "description": "Phase to set: describing, reproducing, fixing, instrumenting, verifying, resolved"]),
                    "detail": .object(["type": "string", "description": "Optional detail or reason for the phase change"]),
                ]),
                "required": .array([.string("phase")]),
            ]),
            annotations: .init(title: "Debug Set Phase")
        ),
        Tool(
            name: "coderide_debug_request_user",
            description: "Request user input during debugging. The debug panel will show the question and wait for the user to respond. Use kind=reproduce to ask for reproduction steps (shows Proceed button), kind=fix_confirmation to ask before cleanup (shows Mark Fixed button).",
            inputSchema: .object([
                "type": "object",
                "properties": .object([
                    "kind": .object(["type": "string", "description": "Request type: reproduce, question, fix_confirmation"]),
                    "prompt": .object(["type": "string", "description": "The question or instructions to show the user"]),
                ]),
                "required": .array([.string("kind"), .string("prompt")]),
            ]),
            annotations: .init(title: "Debug Request User")
        ),
        Tool(
            name: "coderide_debug_resolve",
            description: "Finalize and resolve the current debug session with a summary. Triggers cleanup of all debug markers and instrumentation if configured.",
            inputSchema: .object([
                "type": "object",
                "properties": .object([
                    "summary": .object(["type": "string", "description": "Summary of the debug session outcome — what was found, what was fixed"]),
                ]),
                "required": .array([.string("summary")]),
            ]),
            annotations: .init(title: "Debug Resolve")
        ),
    ]
}
