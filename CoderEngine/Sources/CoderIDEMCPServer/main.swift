import Foundation
import CoderEngine
import MCP

// MARK: - Tool Definitions

/// All tools exposed by CoderIDE MCP Server, with their JSON schemas.
/// Codex CLI will register these as available tools for the model.
struct CoderIDETools {
    static let all: [Tool] = [
        // --- File Operations ---
        Tool(
            name: "coderide_read",
            description: "Read the contents of a file. Always read before editing.",
            inputSchema: .object([
                "type": "object",
                "properties": .object([
                    "path": .object(["type": "string", "description": "Absolute or relative file path"]),
                    "offset": .object(["type": "string", "description": "Line number to start reading from (1-based)"]),
                    "limit": .object(["type": "string", "description": "Maximum number of lines to read"]),
                ]),
                "required": .array([.string("path")]),
            ]),
            annotations: .init(title: "Read File", readOnlyHint: true, idempotentHint: true)
        ),
        Tool(
            name: "coderide_read_range",
            description: "Read a specific range of lines from a file.",
            inputSchema: .object([
                "type": "object",
                "properties": .object([
                    "path": .object(["type": "string", "description": "File path"]),
                    "start_line": .object(["type": "string", "description": "Starting line number (1-based)"]),
                    "end_line": .object(["type": "string", "description": "Ending line number (inclusive)"]),
                ]),
                "required": .array([.string("path"), .string("start_line"), .string("end_line")]),
            ]),
            annotations: .init(title: "Read Range", readOnlyHint: true, idempotentHint: true)
        ),
        Tool(
            name: "coderide_list_dir",
            description: "List files and directories in a directory path.",
            inputSchema: .object([
                "type": "object",
                "properties": .object([
                    "path": .object(["type": "string", "description": "Directory path to list"]),
                ]),
                "required": .array([.string("path")]),
            ]),
            annotations: .init(title: "List Directory", readOnlyHint: true, idempotentHint: true)
        ),
        Tool(
            name: "coderide_write",
            description: "Write or create a file with the specified content. Use coderide_str_replace for targeted edits.",
            inputSchema: .object([
                "type": "object",
                "properties": .object([
                    "path": .object(["type": "string", "description": "File path to write to"]),
                    "content": .object(["type": "string", "description": "Complete file content"]),
                ]),
                "required": .array([.string("path"), .string("content")]),
            ]),
            annotations: .init(title: "Write File", destructiveHint: true)
        ),
        Tool(
            name: "coderide_str_replace",
            description: "Replace a specific string in a file. The old_string must be unique in the file. Prefer this over write for targeted edits.",
            inputSchema: .object([
                "type": "object",
                "properties": .object([
                    "path": .object(["type": "string", "description": "File path"]),
                    "old_string": .object(["type": "string", "description": "Exact string to find and replace (must be unique in file)"]),
                    "new_string": .object(["type": "string", "description": "Replacement string"]),
                ]),
                "required": .array([.string("path"), .string("old_string"), .string("new_string")]),
            ]),
            annotations: .init(title: "String Replace", destructiveHint: false, idempotentHint: true)
        ),
        Tool(
            name: "coderide_create_file",
            description: "Create a new file with content. Fails if file already exists.",
            inputSchema: .object([
                "type": "object",
                "properties": .object([
                    "path": .object(["type": "string", "description": "Path for the new file"]),
                    "content": .object(["type": "string", "description": "File content"]),
                ]),
                "required": .array([.string("path"), .string("content")]),
            ]),
            annotations: .init(title: "Create File")
        ),

        // --- Search & Navigation ---
        Tool(
            name: "coderide_grep",
            description: "Search file contents using regex patterns. Accepts 'pattern' (or 'query') and returns matching lines with context.",
            inputSchema: .object([
                "type": "object",
                "properties": .object([
                    "query": .object(["type": "string", "description": "Regex/text query to search (alias of pattern)"]),
                    "pattern": .object(["type": "string", "description": "Regex pattern to search for"]),
                    "path": .object(["type": "string", "description": "Directory or file to search in"]),
                    "fileType": .object(["type": "string", "description": "File extension filter (e.g. 'swift', 'py')"]),
                    "maxResults": .object(["type": "string", "description": "Maximum number of results"]),
                ]),
                "required": .array([]),
            ]),
            annotations: .init(title: "Grep Search", readOnlyHint: true)
        ),
        Tool(
            name: "coderide_glob",
            description: "Find files by name pattern using glob syntax (e.g. '**/*.swift').",
            inputSchema: .object([
                "type": "object",
                "properties": .object([
                    "pattern": .object(["type": "string", "description": "Glob pattern (e.g. **/*.ts, src/**/*.swift)"]),
                    "path": .object(["type": "string", "description": "Base directory to search from"]),
                ]),
                "required": .array([.string("pattern")]),
            ]),
            annotations: .init(title: "Glob Files", readOnlyHint: true, idempotentHint: true)
        ),
        Tool(
            name: "coderide_find_files",
            description: "Find files by name pattern using the codebase index. Supports optional scope filters via 'path'/'filePattern'.",
            inputSchema: .object([
                "type": "object",
                "properties": .object([
                    "query": .object(["type": "string", "description": "File name query (alias of pattern)"]),
                    "pattern": .object(["type": "string", "description": "File name pattern to search (alias of query)"]),
                    "path": .object(["type": "string", "description": "Optional directory scope (alias of filePattern)"]),
                    "filePattern": .object(["type": "string", "description": "Optional file path/glob filter (e.g. Sources/**)"]),
                    "extension": .object(["type": "string", "description": "Optional extension filter"]),
                ]),
                "required": .array([]),
            ]),
            annotations: .init(title: "Find Files", readOnlyHint: true, idempotentHint: true)
        ),
        Tool(
            name: "coderide_codebase_search",
            description: "Search symbols/functions with the codebase index. 'path' is a compatibility alias of 'filePattern'.",
            inputSchema: .object([
                "type": "object",
                "properties": .object([
                    "query": .object(["type": "string", "description": "Natural language search query"]),
                    "kind": .object(["type": "string", "description": "Optional symbol kind filter"]),
                    "filePattern": .object(["type": "string", "description": "Optional file path/glob filter"]),
                    "path": .object(["type": "string", "description": "Compatibility alias for filePattern"]),
                ]),
                "required": .array([.string("query")]),
            ]),
            annotations: .init(title: "Codebase Search", readOnlyHint: true)
        ),
        Tool(
            name: "coderide_find_symbol",
            description: "Find symbol definitions (classes, functions, structs) by name.",
            inputSchema: .object([
                "type": "object",
                "properties": .object([
                    "name": .object(["type": "string", "description": "Symbol name to find"]),
                    "kind": .object(["type": "string", "description": "Symbol kind: class, function, struct, enum, etc."]),
                ]),
                "required": .array([.string("name")]),
            ]),
            annotations: .init(title: "Find Symbol", readOnlyHint: true, idempotentHint: true)
        ),
        Tool(
            name: "coderide_find_references",
            description: "Find all references to a symbol. Use before refactoring.",
            inputSchema: .object([
                "type": "object",
                "properties": .object([
                    "name": .object(["type": "string", "description": "Symbol name to find references for"]),
                ]),
                "required": .array([.string("name")]),
            ]),
            annotations: .init(title: "Find References", readOnlyHint: true)
        ),
        Tool(
            name: "coderide_file_outline",
            description: "Get the structure outline of a file (functions, classes, imports).",
            inputSchema: .object([
                "type": "object",
                "properties": .object([
                    "path": .object(["type": "string", "description": "File path"]),
                ]),
                "required": .array([.string("path")]),
            ]),
            annotations: .init(title: "File Outline", readOnlyHint: true, idempotentHint: true)
        ),

        // --- Execution ---
        Tool(
            name: "coderide_git_diff",
            description: "Show git diff for the current workspace.",
            inputSchema: .object([
                "type": "object",
                "properties": .object([
                    "path": .object(["type": "string", "description": "Optional path scope for diff"]),
                    "staged": .object(["type": "string", "description": "'true' to show staged changes only"]),
                ]),
            ]),
            annotations: .init(title: "Git Diff", readOnlyHint: true)
        ),
        Tool(
            name: "coderide_diagnostics",
            description: "Run full build diagnostics and return errors/warnings.",
            inputSchema: .object([
                "type": "object",
                "properties": .object([
                    "path": .object(["type": "string", "description": "Optional path scope"]),
                ]),
            ]),
            annotations: .init(title: "Diagnostics", readOnlyHint: true)
        ),
        Tool(
            name: "coderide_read_lints",
            description: "Read lint warnings/errors without full build. Faster than diagnostics.",
            inputSchema: .object([
                "type": "object",
                "properties": .object([
                    "path": .object(["type": "string", "description": "Optional path scope"]),
                ]),
            ]),
            annotations: .init(title: "Read Lints", readOnlyHint: true)
        ),

        // --- Web ---
        Tool(
            name: "coderide_web_search",
            description: "Search the web for information. Returns search results with titles, URLs and snippets.",
            inputSchema: .object([
                "type": "object",
                "properties": .object([
                    "query": .object(["type": "string", "description": "Search query"]),
                    "maxResults": .object(["type": "string", "description": "Maximum number of results (default: 5)"]),
                ]),
                "required": .array([.string("query")]),
            ]),
            annotations: .init(title: "Web Search", readOnlyHint: true, openWorldHint: true)
        ),
        Tool(
            name: "coderide_web_fetch",
            description: "Fetch a web page and convert it to readable Markdown.",
            inputSchema: .object([
                "type": "object",
                "properties": .object([
                    "url": .object(["type": "string", "description": "URL to fetch"]),
                ]),
                "required": .array([.string("url")]),
            ]),
            annotations: .init(title: "Web Fetch", readOnlyHint: true, openWorldHint: true)
        ),

        // --- Advanced Editing ---
        Tool(
            name: "coderide_regex_replace",
            description: "Replace text matching a regex pattern in a file.",
            inputSchema: .object([
                "type": "object",
                "properties": .object([
                    "path": .object(["type": "string", "description": "File path"]),
                    "pattern": .object(["type": "string", "description": "Regex pattern to match"]),
                    "replacement": .object(["type": "string", "description": "Replacement string"]),
                ]),
                "required": .array([.string("path"), .string("pattern"), .string("replacement")]),
            ]),
            annotations: .init(title: "Regex Replace", destructiveHint: false)
        ),

        // --- IDE Integration (Todo / Plan) ---
        Tool(
            name: "coderide_todo_write",
            description: """
                Update the IDE todo list. Pass a JSON array of todo items via the 'todos' parameter. \
                Each item must have 'content' (string) and 'status' (pending|in_progress|done|blocked). \
                Optional fields: 'activeForm' (present-tense label shown during execution), \
                'priority' (low|medium|high), 'linkedFiles' (array of file paths related to the task). \
                Use this tool to track multi-step task progress in the IDE live card.
                """,
            inputSchema: .object([
                "type": "object",
                "properties": .object([
                    "todos": .object([
                        "type": "string",
                        "description": "JSON array of todo items, e.g. [{\"content\":\"Fix bug\",\"status\":\"pending\",\"activeForm\":\"Fixing bug\"}]",
                    ]),
                    // Single-item shorthand
                    "title": .object(["type": "string", "description": "Single todo title (shorthand — use 'todos' for batch updates)"]),
                    "status": .object(["type": "string", "description": "Status: pending, in_progress, done, blocked"]),
                    "priority": .object(["type": "string", "description": "Priority: low, medium, high"]),
                ]),
            ]),
            annotations: .init(title: "Todo Write", readOnlyHint: false, idempotentHint: true)
        ),
        Tool(
            name: "coderide_todo_read",
            description: "Read the current IDE todo list. Returns the current state of all tracked todo items.",
            inputSchema: .object([
                "type": "object",
                "properties": .object([:]),
            ]),
            annotations: .init(title: "Todo Read", readOnlyHint: true, idempotentHint: true)
        ),
        Tool(
            name: "coderide_plan_step_update",
            description: """
                Update the status of a plan step in the IDE plan panel. \
                Use this during plan execution to track progress of each step.
                """,
            inputSchema: .object([
                "type": "object",
                "properties": .object([
                    "step_id": .object(["type": "string", "description": "The step identifier (e.g. '1', '2')"]),
                    "status": .object(["type": "string", "description": "Step status: pending, running, done, failed"]),
                    "title": .object(["type": "string", "description": "Optional step title"]),
                ]),
                "required": .array([.string("step_id"), .string("status")]),
            ]),
            annotations: .init(title: "Plan Step Update", readOnlyHint: false, idempotentHint: true)
        ),
        Tool(
            name: "coderide_mermaid_render",
            description: """
                Render a mermaid diagram in the IDE chat and plan panel. \
                Pass mermaid syntax (flowchart, sequence, class, state, etc.) and it will \
                be displayed as an interactive rendered diagram. Use this to visualize \
                architecture, flows, dependencies, and relationships. \
                ALWAYS use this tool when analyzing problems or creating plans to provide \
                visual context.
                """,
            inputSchema: .object([
                "type": "object",
                "properties": .object([
                    "code": .object(["type": "string", "description": "Mermaid diagram code (e.g. 'graph TD; A-->B;')"]),
                    "title": .object(["type": "string", "description": "Optional title for the diagram"]),
                ]),
                "required": .array([.string("code")]),
            ]),
            annotations: .init(title: "Render Mermaid Diagram", readOnlyHint: false)
        ),

        // --- IDE Integration (Debug Panel / Mode Activation / Swarm) ---
        Tool(
            name: "coderide_debug_set_phase",
            description: "Set the debug panel phase in a strongly-typed way.",
            inputSchema: .object([
                "type": "object",
                "properties": .object([
                    "phase": .object([
                        "type": "string",
                        "description": "Debug phase: describing, reproducing, fixing, instrumenting, verifying, resolved"
                    ]),
                    "detail": .object(["type": "string", "description": "Optional human-readable context for this phase transition"]),
                ]),
                "required": .array([.string("phase")]),
            ]),
            annotations: .init(title: "Debug Set Phase", readOnlyHint: false)
        ),
        Tool(
            name: "coderide_debug_request_user",
            description: "Request explicit user interaction during debugging.",
            inputSchema: .object([
                "type": "object",
                "properties": .object([
                    "kind": .object([
                        "type": "string",
                        "description": "Request kind: question or reproduce"
                    ]),
                    "prompt": .object([
                        "type": "string",
                        "description": "Prompt shown to the user"
                    ]),
                ]),
                "required": .array([.string("kind"), .string("prompt")]),
            ]),
            annotations: .init(title: "Debug Request User", readOnlyHint: false)
        ),
        Tool(
            name: "coderide_debug_resolve",
            description: "Resolve the active debug session with a summary.",
            inputSchema: .object([
                "type": "object",
                "properties": .object([
                    "summary": .object(["type": "string", "description": "Resolution summary"]),
                ]),
                "required": .array([.string("summary")]),
            ]),
            annotations: .init(title: "Debug Resolve", readOnlyHint: false)
        ),
        Tool(
            name: "coderide_policy_ack",
            description: "Acknowledge a mandatory instruction policy hash before performing tool operations.",
            inputSchema: .object([
                "type": "object",
                "properties": .object([
                    "hash": .object(["type": "string", "description": "The policy hash to acknowledge"]),
                ]),
                "required": .array([.string("hash")]),
            ]),
            annotations: .init(title: "Policy Acknowledge", readOnlyHint: false)
        ),
        Tool(
            name: "coderide_activate_plan_mode",
            description: "Request the IDE to activate the plan mode panel for structured planning.",
            inputSchema: .object([
                "type": "object",
                "properties": .object([
                    "reason": .object(["type": "string", "description": "Optional reason for activating plan mode"]),
                ]),
            ]),
            annotations: .init(title: "Activate Plan Mode", readOnlyHint: false)
        ),
        Tool(
            name: "coderide_activate_debug_mode",
            description: "Request the IDE to activate the debug mode panel for structured debugging.",
            inputSchema: .object([
                "type": "object",
                "properties": .object([
                    "reason": .object(["type": "string", "description": "Optional reason for activating debug mode"]),
                ]),
            ]),
            annotations: .init(title: "Activate Debug Mode", readOnlyHint: false)
        ),
        Tool(
            name: "coderide_show_task_panel",
            description: "Show the IDE task/activity panel to display ongoing task progress.",
            inputSchema: .object([
                "type": "object",
                "properties": .object([:]),
            ]),
            annotations: .init(title: "Show Task Panel", readOnlyHint: false)
        ),
        Tool(
            name: "coderide_show_swarm_panel",
            description: "Request the IDE to open/focus the swarm panel.",
            inputSchema: .object([
                "type": "object",
                "properties": .object([
                    "swarm_id": .object(["type": "string", "description": "Optional swarm id to focus immediately"]),
                ]),
            ]),
            annotations: .init(title: "Show Swarm Panel", readOnlyHint: false)
        ),

        // --- Debug Tools ---
        Tool(
            name: "coderide_debug_context",
            description: """
                Gather full debug context in one call: git status, open files, lint errors, \
                recent commits, debug log summary. Use this FIRST when entering debug mode.
                """,
            inputSchema: .object([
                "type": "object",
                "properties": .object([:]),
            ]),
            annotations: .init(title: "Debug Context", readOnlyHint: true)
        ),
        Tool(
            name: "coderide_debug_log",
            description: "Write an entry to the debug log. Use to track observations, errors, and findings during debugging.",
            inputSchema: .object([
                "type": "object",
                "properties": .object([
                    "severity": .object(["type": "string", "description": "Log severity: error, warning, info, verbose, trace"]),
                    "source": .object(["type": "string", "description": "Source location (e.g. 'NetworkManager.swift:42')"]),
                    "message": .object(["type": "string", "description": "Log message"]),
                    "detail": .object(["type": "string", "description": "Optional detail (e.g. stack trace)"]),
                    "category": .object(["type": "string", "description": "Optional category: compiler, runtime, test, network, custom"]),
                ]),
                "required": .array([.string("severity"), .string("source"), .string("message")]),
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
                    "format": .object(["type": "string", "description": "Output format: summary or full (default: summary)"]),
                    "limit": .object(["type": "string", "description": "Max results (default: 100)"]),
                ]),
            ]),
            annotations: .init(title: "Debug Query", readOnlyHint: true)
        ),
        Tool(
            name: "coderide_debug_session",
            description: "Manage debug sessions. Start a new session, end the current one, or clear all sessions.",
            inputSchema: .object([
                "type": "object",
                "properties": .object([
                    "action": .object(["type": "string", "description": "Session action: start, end, clear"]),
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
                ]),
            ]),
            annotations: .init(title: "Debug Clean")
        ),
    ]

    /// Map MCP tool name → UnifiedToolRuntime tool name by stripping the "coderide_" prefix.
    static func runtimeToolName(from mcpName: String) -> String {
        if mcpName.hasPrefix("coderide_") {
            return String(mcpName.dropFirst("coderide_".count))
        }
        return mcpName
    }
}

// MARK: - Server Bootstrap

@main
struct CoderIDEMCPServerApp {
    static func main() async throws {
        // Parse arguments: --workspace <path>
        let args = CommandLine.arguments
        let workspacePath: String
        if let idx = args.firstIndex(of: "--workspace"), idx + 1 < args.count {
            workspacePath = args[idx + 1]
        } else {
            workspacePath = FileManager.default.currentDirectoryPath
        }

        let workspaceURL = URL(fileURLWithPath: workspacePath)

        // Build the runtime with a live codebase index so codebase_search/find_symbol/find_files work.
        let codebaseIndex = CodebaseIndex()
        let runtime = UnifiedToolRuntime(
            executionController: nil,
            executionScope: .agent,
            mcpSessions: MCPSessionManager(),
            index: codebaseIndex,
            workspacePaths: [workspaceURL],
            excludedPaths: [],
            webSearchProvider: nil,
            webSearchApiKeys: nil
        )

        let context = ToolExecutionContext(
            workspaceContext: WorkspaceContext(
                workspacePath: workspaceURL,
                excludedPaths: []
            ),
            policy: ToolRuntimePolicy(
                sandboxMode: "workspace-write",
                askForApproval: "never",
                timeoutMs: 120_000,
                maxBashOutputBytes: 256_000,
                maxReadBytesPerFile: 512_000,
                enableMCP: false  // Don't recurse into MCP from this server
            ),
            executionScope: .agent
        )

        // Create MCP server
        let server = Server(
            name: "coderide-tools",
            version: "1.0.0",
            instructions: """
                CoderIDE Tool Server — provides file operations, search, editing, \
                web search, and diagnostics tools for the current workspace. \
                Prefer these tools over shell commands for file operations and code search.
                """,
            capabilities: .init(
                tools: .init(listChanged: false)
            )
        )

        // Register tools/list handler
        await server.withMethodHandler(ListTools.self) { _ in
            ListTools.Result(tools: CoderIDETools.all)
        }

        // Register tools/call handler
        await server.withMethodHandler(CallTool.self) { params in
            let toolName = CoderIDETools.runtimeToolName(from: params.name)
            let isEditRuntimeTool = Self.mcpEditRuntimeTools.contains(toolName)

            // Convert MCP Value args → [String: String] for UnifiedToolRuntime
            var stringArgs: [String: String] = [:]
            if let arguments = params.arguments {
                for (key, value) in arguments {
                    stringArgs[key] = valueToString(value)
                }
            }

            // IDE state tools are pass-through: accepted by MCP server,
            // actual state management happens on the UI side via stream event pipeline.
            let ideStateTools: Set<String> = [
                "todo_write", "todo_read", "plan_step_update", "mermaid_render",
                "debug_set_phase", "debug_request_user", "debug_resolve",
                "policy_ack", "activate_plan_mode", "activate_debug_mode",
                "show_task_panel", "show_swarm_panel",
            ]
            if toolName == "debug_panel" {
                return CallTool.Result(
                    content: [.text("tool_validation_error: legacy tool 'debug_panel' is not supported. Use debug_set_phase/debug_request_user/debug_resolve.")],
                    isError: true
                )
            }
            if ideStateTools.contains(toolName) {
                return handleIDEStateTool(name: toolName, args: stringArgs)
            }

            let call = ToolCall(
                id: UUID().uuidString,
                name: toolName,
                args: stringArgs,
                sourceProvider: "coderide-mcp",
                swarmId: nil,
                scope: .agent
            )

            let events = await runtime.execute(call, context: context)

            // Extract result from stream events
            var output = ""
            var isError = false
            var bestPayload: [String: String] = [:]
            var bestPayloadScore = Int.min
            for event in events {
                if case .raw(let type, let payload) = event {
                    let score = Self.payloadScore(payload: payload)
                    if score >= bestPayloadScore {
                        bestPayload = payload
                        bestPayloadScore = score
                    }
                    if let payloadOutput = payload["output"], !payloadOutput.isEmpty {
                        output = payloadOutput
                    }
                    if let detail = payload["detail"], output.isEmpty {
                        output = detail
                    }
                    if let stderr = payload["stderr"], !stderr.isEmpty {
                        if !output.isEmpty { output += "\n" }
                        output += stderr
                    }
                    if payload["status"] == "failed" || type.contains("error") {
                        isError = true
                    }
                }
            }

            if isEditRuntimeTool {
                let structuredPayload = Self.structuredMCPEditPayload(
                    toolName: toolName,
                    toolCallID: call.id,
                    payload: bestPayload,
                    isError: isError
                )
                if let json = Self.encodeJSONObjectString(structuredPayload) {
                    return CallTool.Result(
                        content: [.text(json)],
                        isError: isError ? true : nil
                    )
                }
            }

            if output.isEmpty {
                output = isError ? "Tool execution failed" : "OK"
            }

            return CallTool.Result(
                content: [.text(output)],
                isError: isError ? true : nil
            )
        }

        // Start stdio transport
        let transport = StdioTransport()
        try await server.start(transport: transport)
        await server.waitUntilCompleted()
    }

    /// IDE state tools are pass-through. The MCP server acknowledges the call
    /// and returns a confirmation. The actual state update happens when the host
    /// process (CoderIDE) sees the MCP tool call event in the Codex CLI stream
    /// and routes it through EventNormalizer → TodoStore / ChatStore.
    static func handleIDEStateTool(name: String, args: [String: String]) -> CallTool.Result {
        switch name {
        case "todo_write":
            let todosRaw = (args["todos"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let titleRaw = (args["title"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let validStatuses: Set<String> = [
                "pending", "in_progress", "done", "blocked",
                // Common LLM aliases
                "completed", "complete", "finished",
                "running", "active", "doing", "started",
                "todo", "open", "queued", "waiting",
                "failed", "error", "stuck",
            ]

            if !todosRaw.isEmpty {
                // Validate JSON structure
                guard let data = todosRaw.data(using: .utf8),
                      let parsed = try? JSONSerialization.jsonObject(with: data) else {
                    return CallTool.Result(
                        content: [.text("Error: 'todos' is not valid JSON. Expected a JSON array of objects, e.g. [{\"content\":\"Task\",\"status\":\"pending\"}]")],
                        isError: true
                    )
                }
                guard let array = parsed as? [[String: Any]], !array.isEmpty else {
                    if parsed is [Any] {
                        // Empty array — acknowledge but nothing to do
                        return CallTool.Result(content: [.text("OK — empty todo list received, no changes")], isError: nil)
                    }
                    return CallTool.Result(
                        content: [.text("Error: 'todos' must be a JSON array of objects, not \(type(of: parsed))")],
                        isError: true
                    )
                }
                for (i, item) in array.enumerated() {
                    let content = (item["content"] as? String ?? item["title"] as? String)?
                        .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    if content.isEmpty {
                        return CallTool.Result(
                            content: [.text("Error: item \(i) missing 'content' or 'title'")],
                            isError: true
                        )
                    }
                    if let itemStatus = (item["status"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
                       !itemStatus.isEmpty,
                       !validStatuses.contains(itemStatus) {
                        return CallTool.Result(
                            content: [.text("Error: item \(i) has invalid status '\(itemStatus)'. Use: pending, in_progress, done, blocked")],
                            isError: true
                        )
                    }
                }
            } else if titleRaw.isEmpty {
                return CallTool.Result(
                    content: [.text("Error: provide either 'todos' (JSON array) or 'title' parameter")],
                    isError: true
                )
            }

            // Validate status value if provided (single-item shorthand)
            if let status = args["status"]?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
               !status.isEmpty,
               !validStatuses.contains(status) {
                return CallTool.Result(
                    content: [.text("Error: invalid status '\(status)'. Use: pending, in_progress, done, blocked")],
                    isError: true
                )
            }
            return CallTool.Result(content: [.text("OK — todo list updated")], isError: nil)

        case "todo_read":
            // Read from the shared state file written by the main IDE app.
            let todos = MCPSharedState.readTodos()
            if todos.isEmpty {
                return CallTool.Result(content: [.text("No todos found.")], isError: nil)
            }
            var lines: [String] = []
            var doneCount = 0
            for todo in todos {
                let title = (todo["title"] as? String) ?? "(untitled)"
                let status = (todo["status"] as? String) ?? "pending"
                let priority = (todo["priority"] as? String) ?? "medium"
                let activeForm = (todo["activeForm"] as? String) ?? ""
                let icon: String
                switch status {
                case "done":
                    icon = "[x]"
                    doneCount += 1
                case "in_progress": icon = "[~]"
                case "blocked": icon = "[!]"
                default: icon = "[ ]"
                }
                let formSuffix = status == "in_progress" && !activeForm.isEmpty ? " — \(activeForm)" : ""
                let linkedFiles = (todo["linkedFiles"] as? [String]) ?? []
                let filesSuffix = linkedFiles.isEmpty ? "" : " [files: \(linkedFiles.joined(separator: ", "))]"
                lines.append("\(icon) \(title)\(formSuffix) (\(priority))\(filesSuffix)")
            }
            lines.append("--- \(todos.count) total, \(doneCount) done ---")
            return CallTool.Result(content: [.text(lines.joined(separator: "\n"))], isError: nil)

        case "plan_step_update":
            let stepId = (args["step_id"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let status = (args["status"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if stepId.isEmpty || status.isEmpty {
                return CallTool.Result(
                    content: [.text("Error: 'step_id' and 'status' are required")],
                    isError: true
                )
            }
            if !["pending", "running", "done", "failed"].contains(status.lowercased()) {
                return CallTool.Result(
                    content: [.text("Error: invalid status '\(status)'. Use: pending, running, done, failed")],
                    isError: true
                )
            }
            return CallTool.Result(content: [.text("OK — plan step \(stepId) updated to \(status)")], isError: nil)

        case "mermaid_render":
            let code = (args["code"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if code.isEmpty {
                return CallTool.Result(
                    content: [.text("Error: 'code' parameter is required and must contain valid mermaid syntax")],
                    isError: true
                )
            }
            let title = args["title"]?.trimmingCharacters(in: .whitespacesAndNewlines)
            let titleInfo = title.map { " (\($0))" } ?? ""
            return CallTool.Result(content: [.text("OK — mermaid diagram rendered in IDE\(titleInfo)")], isError: nil)

        case "debug_set_phase":
            let phase = (args["phase"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let validPhases: Set<String> = [
                "describing", "reproducing", "fixing", "instrumenting", "verifying", "resolved"
            ]
            if phase.isEmpty {
                return CallTool.Result(
                    content: [.text("Error: 'phase' parameter is required")],
                    isError: true
                )
            }
            if !validPhases.contains(phase) {
                return CallTool.Result(
                    content: [.text("Error: invalid phase '\(phase)'. Use: describing, reproducing, fixing, instrumenting, verifying, resolved")],
                    isError: true
                )
            }
            return CallTool.Result(content: [.text("OK — debug phase set to \(phase)")], isError: nil)

        case "debug_request_user":
            let kind = (args["kind"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let prompt = (args["prompt"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let validKinds: Set<String> = ["question", "reproduce"]
            if kind.isEmpty || prompt.isEmpty {
                return CallTool.Result(
                    content: [.text("Error: 'kind' and 'prompt' parameters are required")],
                    isError: true
                )
            }
            if !validKinds.contains(kind) {
                return CallTool.Result(
                    content: [.text("Error: invalid kind '\(kind)'. Use: question, reproduce")],
                    isError: true
                )
            }
            return CallTool.Result(content: [.text("OK — debug user request '\(kind)' queued")], isError: nil)

        case "debug_resolve":
            let summary = (args["summary"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if summary.isEmpty {
                return CallTool.Result(
                    content: [.text("Error: 'summary' parameter is required")],
                    isError: true
                )
            }
            return CallTool.Result(content: [.text("OK — debug session resolved")], isError: nil)

        case "policy_ack":
            let hash = (args["hash"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if hash.isEmpty {
                return CallTool.Result(
                    content: [.text("Error: 'hash' parameter is required")],
                    isError: true
                )
            }
            return CallTool.Result(content: [.text("OK — policy acknowledged")], isError: nil)

        case "activate_plan_mode":
            return CallTool.Result(content: [.text("OK — plan mode activated")], isError: nil)

        case "activate_debug_mode":
            return CallTool.Result(content: [.text("OK — debug mode activated")], isError: nil)

        case "show_task_panel":
            return CallTool.Result(content: [.text("OK — task panel shown")], isError: nil)

        case "show_swarm_panel":
            return CallTool.Result(content: [.text("OK — swarm panel opened")], isError: nil)

        default:
            return CallTool.Result(content: [.text("Unknown IDE state tool: \(name)")], isError: true)
        }
    }

    private static let mcpEditRuntimeTools: Set<String> = [
        "edit", "write", "str_replace", "regex_replace", "create_file",
    ]

    static func structuredMCPEditPayload(
        toolName: String,
        toolCallID: String,
        payload: [String: String],
        isError: Bool
    ) -> [String: String] {
        var structured: [String: String] = [:]
        structured["source"] = "mcp"
        structured["tool"] = toolName
        structured["tool_call_id"] = firstNonEmpty(payload: payload, keys: ["tool_call_id", "call_id", "id"])
            ?? toolCallID
        structured["status"] = firstNonEmpty(payload: payload, keys: ["status"]) ?? (isError ? "failed" : "completed")
        structured["change_type"] = firstNonEmpty(payload: payload, keys: ["change_type", "operation", "action", "edit_type"])
            ?? toolName
        if let path = firstNonEmpty(payload: payload, keys: ["path", "file", "file_path", "target_path", "relative_path"]) {
            structured["path"] = path
        }
        if let added = firstNonEmpty(payload: payload, keys: ["linesAdded", "additions", "insertions", "added"]) {
            structured["linesAdded"] = added
        }
        if let removed = firstNonEmpty(payload: payload, keys: ["linesRemoved", "deletions", "removed", "deletions_count"]) {
            structured["linesRemoved"] = removed
        }
        if let diff = firstNonEmpty(
            payload: payload,
            keys: ["diffPreview", "diff", "patch", "unified_diff", "changes_preview"]
        ) {
            structured["diffPreview"] = String(diff.prefix(12_000))
        }
        if let detail = firstNonEmpty(payload: payload, keys: ["detail"]) {
            structured["detail"] = detail
        }
        if let title = firstNonEmpty(payload: payload, keys: ["title"]) {
            structured["title"] = title
        }
        return structured
    }

    static func payloadScore(payload: [String: String]) -> Int {
        var score = payload.count
        if let status = payload["status"]?.lowercased(), status == "completed" {
            score += 100
        }
        if payload["linesAdded"] != nil || payload["linesRemoved"] != nil {
            score += 60
        }
        if payload["diffPreview"] != nil || payload["patch"] != nil || payload["diff"] != nil {
            score += 60
        }
        if payload["path"] != nil || payload["file"] != nil {
            score += 20
        }
        return score
    }

    static func firstNonEmpty(payload: [String: String], keys: [String]) -> String? {
        for key in keys {
            let value = (payload[key] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if !value.isEmpty {
                return payload[key]
            }
        }
        return nil
    }

    static func encodeJSONObjectString(_ object: [String: String]) -> String? {
        guard JSONSerialization.isValidJSONObject(object),
              let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]) else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    static func valueToString(_ value: Value) -> String {
        switch value {
        case .string(let s):
            return s
        case .int(let i):
            return "\(i)"
        case .double(let d):
            return "\(d)"
        case .bool(let b):
            return b ? "true" : "false"
        case .null:
            return ""
        default:
            // For arrays/objects, encode as JSON string
            let encoder = JSONEncoder()
            encoder.outputFormatting = .withoutEscapingSlashes
            if let data = try? encoder.encode(value),
               let str = String(data: data, encoding: .utf8) {
                return str
            }
            return "\(value)"
        }
    }
}
