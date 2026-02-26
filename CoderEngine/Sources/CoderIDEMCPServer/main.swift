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
            description: "Search file contents using regex patterns. Returns matching lines with context.",
            inputSchema: .object([
                "type": "object",
                "properties": .object([
                    "pattern": .object(["type": "string", "description": "Regex pattern to search for"]),
                    "path": .object(["type": "string", "description": "Directory or file to search in"]),
                    "fileType": .object(["type": "string", "description": "File extension filter (e.g. 'swift', 'py')"]),
                    "maxResults": .object(["type": "string", "description": "Maximum number of results"]),
                ]),
                "required": .array([.string("pattern")]),
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
            description: "Find files by name pattern using the codebase index. Faster than glob for indexed repos.",
            inputSchema: .object([
                "type": "object",
                "properties": .object([
                    "pattern": .object(["type": "string", "description": "File name pattern to search"]),
                    "path": .object(["type": "string", "description": "Optional directory scope"]),
                ]),
                "required": .array([.string("pattern")]),
            ]),
            annotations: .init(title: "Find Files", readOnlyHint: true, idempotentHint: true)
        ),
        Tool(
            name: "coderide_codebase_search",
            description: "Semantic search across the codebase. Use natural language queries like 'where is authentication handled?'.",
            inputSchema: .object([
                "type": "object",
                "properties": .object([
                    "query": .object(["type": "string", "description": "Natural language search query"]),
                    "path": .object(["type": "string", "description": "Optional directory scope"]),
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
                Each item must have 'content' (string) and 'status' (pending|in_progress|done). \
                Optional fields: 'activeForm' (present-tense label shown during execution), 'priority' (low|medium|high). \
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
                    "status": .object(["type": "string", "description": "Status: pending, in_progress, done"]),
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

        // Build the runtime
        let runtime = UnifiedToolRuntime(
            executionController: nil,
            executionScope: .agent,
            mcpSessions: MCPSessionManager(),
            index: nil,
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

            // Convert MCP Value args → [String: String] for UnifiedToolRuntime
            var stringArgs: [String: String] = [:]
            if let arguments = params.arguments {
                for (key, value) in arguments {
                    stringArgs[key] = valueToString(value)
                }
            }

            // IDE state tools (todo/plan) are pass-through: accepted by MCP server,
            // actual state management happens on the UI side via stream event pipeline.
            if toolName == "todo_write" || toolName == "todo_read" || toolName == "plan_step_update" {
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
            for event in events {
                if case .raw(let type, let payload) = event {
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

            if !todosRaw.isEmpty {
                // Validate JSON structure
                guard let data = todosRaw.data(using: .utf8),
                      let array = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]],
                      !array.isEmpty else {
                    return CallTool.Result(
                        content: [.text("Error: 'todos' must be a valid JSON array of objects")],
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
               !["pending", "in_progress", "done", "blocked"].contains(status) {
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
                lines.append("\(icon) \(title)\(formSuffix) (\(priority))")
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

        default:
            return CallTool.Result(content: [.text("Unknown IDE state tool: \(name)")], isError: true)
        }
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
