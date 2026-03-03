import Foundation
import MCP

extension CoderIDETools {
    static let searchTools: [Tool] = [
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
    ]
}
