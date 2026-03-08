import Foundation
import MCP

extension CoderIDETools {
    static let searchTools: [Tool] = [
        // --- Search & Navigation ---
        Tool(
            name: "coderide_grep",
            description: "Search file contents using regex patterns. Supports aliases 'pattern'/'query' and 'path'/'pathScope'.",
            inputSchema: .object([
                "type": "object",
                "properties": .object([
                    "query": .object(["type": "string", "description": "Text or regex query to search (alias of pattern)"]),
                    "pattern": .object(["type": "string", "description": "Regex pattern to search for (alias of query)"]),
                    "pathScope": .object(["type": "string", "description": "Directory/file scope (comma-separated for multiple scopes)"]),
                    "path": .object(["type": "string", "description": "Alias for pathScope"]),
                    "fileType": .object(["type": "string", "description": "File extension filter (e.g. 'swift', 'py')"]),
                    "glob": .object(["type": "string", "description": "Glob pattern filter (e.g. '*.swift')"]),
                    "output_mode": .object(["type": "string", "description": "content (default), files_only, or count"]),
                    "context_lines": .object(["type": "string", "description": "Context lines around matches (default: 2, max: 10)"]),
                    "case_sensitive": .object(["type": "string", "description": "'true' to enable case-sensitive matching"]),
                    "multiline": .object(["type": "string", "description": "'true' to enable multiline regex mode"]),
                    "maxResults": .object(["type": "string", "description": "Legacy alias for max matches per scope"]),
                ]),
                "required": .array([]),
            ]),
            annotations: .init(title: "Grep Search", readOnlyHint: true)
        ),
        Tool(
            name: "coderide_semantic_search",
            description: "Search code by intent and meaning using semantic index (with fallback text search).",
            inputSchema: .object([
                "type": "object",
                "properties": .object([
                    "query": .object(["type": "string", "description": "Natural language search query"]),
                    "target_directories": .object(["type": "string", "description": "Optional comma-separated directories"]),
                    "targetDirectories": .object(["type": "string", "description": "Alias for target_directories"]),
                    "pathScope": .object(["type": "string", "description": "Compatibility alias for target_directories"]),
                    "path": .object(["type": "string", "description": "Compatibility alias for target_directories"]),
                    "num_results": .object(["type": "string", "description": "Max results (1-50)"]),
                    "limit": .object(["type": "string", "description": "Alias for num_results"]),
                ]),
                "required": .array([.string("query")]),
            ]),
            annotations: .init(title: "Semantic Search", readOnlyHint: true, idempotentHint: true)
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
    ]
}
