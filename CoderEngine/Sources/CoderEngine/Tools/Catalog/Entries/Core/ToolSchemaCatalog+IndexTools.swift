import Foundation

extension ToolSchemaCatalog {
    static let indexTools: [ToolSchemaEntry] = [
        ToolSchemaEntry(
            name: "codebase_search",
            description: "Search codebase symbols with the structured index",
            properties: [
                "query": ["type": "string", "description": "Search query"],
                "kind": ["type": "string", "description": "Symbol kind filter"],
                "filePattern": ["type": "string", "description": "Optional file glob filter"],
                "path": ["type": "string", "description": "Alias for filePattern"]
            ],
            required: ["query"]
        ),
        ToolSchemaEntry(
            name: "find_symbol",
            description: "Find exact symbol definitions",
            properties: [
                "query": ["type": "string", "description": "Exact symbol name"],
                "name": ["type": "string", "description": "Alias for query"],
                "kind": ["type": "string", "description": "Optional symbol kind"]
            ],
            required: ["query"]
        ),
        ToolSchemaEntry(
            name: "list_symbols",
            description: "List symbols in a specific file",
            properties: [
                "path": ["type": "string", "description": "File path"]
            ],
            required: ["path"]
        ),
        ToolSchemaEntry(
            name: "find_references",
            description: "Find symbol references",
            properties: [
                "query": ["type": "string", "description": "Symbol name"],
                "name": ["type": "string", "description": "Alias for query"]
            ],
            required: ["query"]
        ),
        ToolSchemaEntry(
            name: "project_structure",
            description: "Show project file structure",
            properties: [
                "maxDepth": ["type": "string", "description": "Optional max depth"]
            ],
            required: []
        ),
        ToolSchemaEntry(
            name: "file_outline",
            description: "Show structured file outline",
            properties: [
                "path": ["type": "string", "description": "File path"]
            ],
            required: ["path"]
        ),
        ToolSchemaEntry(
            name: "find_files",
            description: "Find files by fuzzy name matching with optional scope filters",
            properties: [
                "query": ["type": "string", "description": "File name query"],
                "pattern": ["type": "string", "description": "Alias for query"],
                "path": ["type": "string", "description": "Alias for filePattern (directory scope)"],
                "filePattern": ["type": "string", "description": "Optional path/glob filter"],
                "extension": ["type": "string", "description": "Optional extension filter"]
            ],
            required: []
        ),
        ToolSchemaEntry(
            name: "codebase_stats",
            description: "Return codebase statistics",
            properties: [:],
            required: []
        ),
        ToolSchemaEntry(
            name: "dependency_graph",
            description: "Show dependency graph for a file",
            properties: [
                "path": ["type": "string", "description": "File path"]
            ],
            required: ["path"]
        ),
        ToolSchemaEntry(
            name: "list_types",
            description: "List all types in the codebase",
            properties: [:],
            required: []
        ),
        ToolSchemaEntry(
            name: "list_tests",
            description: "List all tests in the codebase",
            properties: [:],
            required: []
        ),
        ToolSchemaEntry(
            name: "index_status",
            description: "Show index status and health",
            properties: [:],
            required: []
        ),
        ToolSchemaEntry(
            name: "reindex",
            description: "Force codebase reindexing",
            properties: [:],
            required: []
        ),
        ToolSchemaEntry(
            name: "semantic_search",
            description: "Search code by intent and meaning",
            properties: [
                "query": ["type": "string", "description": "Natural language query"],
                "target_directories": ["type": "string", "description": "Optional comma-separated directories"],
                "targetDirectories": ["type": "string", "description": "Alias for target_directories"],
                "pathScope": ["type": "string", "description": "Compatibility alias for target_directories"],
                "path": ["type": "string", "description": "Compatibility alias for target_directories"],
                "num_results": ["type": "string", "description": "Maximum results (1-50)"],
                "limit": ["type": "string", "description": "Alias for num_results"],
                "min_confidence": ["type": "string", "description": "Minimum confidence filter (0.0-1.0, default 0.45)"]
            ],
            required: ["query"]
        ),
        ToolSchemaEntry(
            name: "parallel_apply",
            description: "Apply multiple independent text edits in one call",
            properties: [
                "edits": ["type": "string", "description": "JSON array of edit objects"]
            ],
            required: ["edits"]
        ),
        ToolSchemaEntry(
            name: "regex_replace",
            description: "Run regex find and replace in a file",
            properties: [
                "path": ["type": "string", "description": "Target file path"],
                "pattern": ["type": "string", "description": "Regex pattern"],
                "replacement": ["type": "string", "description": "Replacement string"],
                "flags": ["type": "string", "description": "Optional regex flags"]
            ],
            required: ["path", "pattern", "replacement"]
        ),
        ToolSchemaEntry(
            name: "rename_symbol",
            description: "Rename a symbol across the codebase",
            properties: [
                "query": ["type": "string", "description": "Current symbol name to rename"],
                "new_name": ["type": "string", "description": "New symbol name"],
                "kind": ["type": "string", "description": "Optional symbol kind"]
            ],
            required: ["query", "new_name"]
        ),
        ToolSchemaEntry(
            name: "find_and_replace_all",
            description: "Run workspace-wide find and replace",
            properties: [
                "pattern": ["type": "string", "description": "Search text or regex pattern"],
                "replacement": ["type": "string", "description": "Replacement text"],
                "file_type": ["type": "string", "description": "Optional file type filter"],
                "regex": ["type": "string", "description": "true if pattern is a regex, false otherwise"]
            ],
            required: ["pattern", "replacement"]
        ),
        ToolSchemaEntry(
            name: "undo_edit",
            description: "Revert a file to last committed state",
            properties: [
                "path": ["type": "string", "description": "Target file path"]
            ],
            required: ["path"]
        ),
    ]
}
