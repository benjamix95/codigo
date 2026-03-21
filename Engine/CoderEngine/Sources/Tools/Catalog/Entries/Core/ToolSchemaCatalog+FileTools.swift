import Foundation

extension ToolSchemaCatalog {
    static let fileTools: [ToolSchemaEntry] = [
        ToolSchemaEntry(
            name: "read",
            description: "Read file content from the workspace",
            properties: [
                "path": ["type": "string", "description": "File path (absolute or workspace-relative)"]
            ],
            required: ["path"]
        ),
        ToolSchemaEntry(
            name: "glob",
            description: "Find files by glob-like pattern",
            properties: [
                "pattern": ["type": "string", "description": "Pattern to match, for example *.swift"],
                "path": ["type": "string", "description": "Optional base path scope"]
            ],
            required: ["pattern"]
        ),
        ToolSchemaEntry(
            name: "grep",
            description: "Search text/regex in files using ripgrep. Supports output modes: 'content' (default, shows matching lines with context), 'files_only' (just file paths), 'count' (match counts per file). Supports glob filtering.",
            properties: [
                "query": ["type": "string", "description": "Text or regex pattern to search for"],
                "pattern": ["type": "string", "description": "Alias for query"],
                "pathScope": ["type": "string", "description": "Directory or file path to scope the search (comma-separated for multiple)"],
                "path": ["type": "string", "description": "Alias for pathScope"],
                "fileType": ["type": "string", "description": "File type filter (e.g. 'swift', 'ts', 'py')"],
                "glob": ["type": "string", "description": "Glob pattern to filter files (e.g. '*.swift', '*.{ts,tsx}')"],
                "maxResults": ["type": "string", "description": "Legacy alias for max matches per scope (default: 200, max: 2000)"],
                "output_mode": ["type": "string", "description": "'content' (default), 'files_only' (just paths), or 'count' (match counts)"],
                "context_lines": ["type": "string", "description": "Context lines around matches (default: 2, max: 10). Only for 'content' mode"],
                "case_sensitive": ["type": "string", "description": "'true' or 'false' (default: false)"],
                "multiline": ["type": "string", "description": "'true' for multiline regex matching (default: false)"]
            ],
            required: []
        ),
        ToolSchemaEntry(
            name: "edit",
            description: "Overwrite file with new content",
            properties: [
                "path": ["type": "string", "description": "Target file path"],
                "content": ["type": "string", "description": "Full file content to write"]
            ],
            required: ["path", "content"]
        ),
        ToolSchemaEntry(
            name: "write",
            description: "Alias of edit",
            properties: [
                "path": ["type": "string", "description": "Target file path"],
                "content": ["type": "string", "description": "Full file content to write"]
            ],
            required: ["path", "content"]
        ),
        ToolSchemaEntry(
            name: "str_replace",
            description: "Replace exact text in a file",
            properties: [
                "path": ["type": "string", "description": "Target file path"],
                "old_string": ["type": "string", "description": "Exact string to replace"],
                "new_string": ["type": "string", "description": "Replacement string"]
            ],
            required: ["path", "old_string", "new_string"]
        ),
        ToolSchemaEntry(
            name: "create_file",
            description: "Create a new file",
            properties: [
                "path": ["type": "string", "description": "Target file path"],
                "content": ["type": "string", "description": "Initial file content"]
            ],
            required: ["path", "content"]
        ),
        ToolSchemaEntry(
            name: "delete_file",
            description: "Delete an existing file",
            properties: [
                "path": ["type": "string", "description": "Target file path"]
            ],
            required: ["path"]
        ),
        ToolSchemaEntry(
            name: "bash",
            description: "Run shell command. The working directory defaults to the workspace root (the project folder paths listed in the context). Always operate within the workspace — never search the full filesystem unless explicitly asked.",
            properties: [
                "command": ["type": "string", "description": "Shell command to execute. Paths should be relative to the workspace root."],
                "cwd": ["type": "string", "description": "Optional working directory override. Defaults to the workspace root."]
            ],
            required: ["command"]
        ),
        ToolSchemaEntry(
            name: "read_terminal",
            description: "Read the output from the IDE terminal. Can read the active session or all sessions. Use this to see what the user ran in their terminal.",
            properties: [
                "session_id": ["type": "string", "description": "Optional session ID to read from. If omitted, reads the active terminal session."],
                "last_n": ["type": "string", "description": "Number of characters to read from the end of the terminal buffer. Default 8000."],
                "all_sessions": ["type": "string", "description": "Set to 'true' to read a summary of all terminal sessions."]
            ],
            required: []
        ),
        ToolSchemaEntry(
            name: "read_range",
            description: "Read a line range from a file",
            properties: [
                "path": ["type": "string", "description": "Target file path"],
                "start": ["type": "string", "description": "Start line (1-based)"],
                "end": ["type": "string", "description": "End line (inclusive)"],
                "start_line": ["type": "string", "description": "Alias for start"],
                "end_line": ["type": "string", "description": "Alias for end"]
            ],
            required: ["path"]
        ),
        ToolSchemaEntry(
            name: "list_dir",
            description: "List directory contents with optional tree view. Supports recursive listing with depth control and file sizes.",
            properties: [
                "path": ["type": "string", "description": "Directory path"],
                "recursive": ["type": "string", "description": "Set to 'true' to list recursively as a tree (default: false)"],
                "depth": ["type": "string", "description": "Max depth for recursive listing (default: 3, max: 5)"],
                "sizes": ["type": "string", "description": "Set to 'true' to show file sizes (default: false)"],
                "maxEntries": ["type": "string", "description": "Max entries to return (default: 200, max: 2000)"]
            ],
            required: ["path"]
        ),
        ToolSchemaEntry(
            name: "git_diff",
            description: "Show git diff",
            properties: [
                "path": ["type": "string", "description": "Optional path scope"]
            ],
            required: []
        ),
        ToolSchemaEntry(
            name: "search_symbols",
            description: "Search code symbols",
            properties: [
                "query": ["type": "string", "description": "Symbol query"],
                "kind": ["type": "string", "description": "class|struct|enum|protocol|function|all"]
            ],
            required: ["query"]
        ),
        ToolSchemaEntry(
            name: "run_tests",
            description: "Run project tests",
            properties: [
                "target": ["type": "string", "description": "Optional test target or filter"],
                "filter": ["type": "string", "description": "Optional test filter"],
                "timeout_ms": ["type": "string", "description": "Timeout in milliseconds"]
            ],
            required: []
        ),
        ToolSchemaEntry(
            name: "run_single_test",
            description: "Run a single test by name",
            properties: [
                "test": ["type": "string", "description": "Test name or filter"],
                "target": ["type": "string", "description": "Optional test target"]
            ],
            required: ["test"]
        ),
    ]
}
