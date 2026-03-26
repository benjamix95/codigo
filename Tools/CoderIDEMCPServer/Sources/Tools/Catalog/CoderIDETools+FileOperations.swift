import Foundation
import MCP

extension CoderIDETools {
    static let fileTools: [Tool] = [
        // --- File Operations ---
        Tool(
            name: "coderide_read",
            description: RustSyncedToolDescriptions.text(mcpName: "coderide_read", fallback: "Read the contents of a file. Always read before editing."),
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
            description: RustSyncedToolDescriptions.text(mcpName: "coderide_read_range", fallback: "Read a specific range of lines from a file."),
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
            description: RustSyncedToolDescriptions.text(mcpName: "coderide_list_dir", fallback: "List files and directories in a directory path."),
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
            description: RustSyncedToolDescriptions.text(mcpName: "coderide_write", fallback: "Write or create a file with the specified content. Use coderide_str_replace for targeted edits."),
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
            description: RustSyncedToolDescriptions.text(mcpName: "coderide_str_replace", fallback: "Replace a specific string in a file. The old_string must be unique in the file. Prefer this over write for targeted edits."),
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
            description: RustSyncedToolDescriptions.text(mcpName: "coderide_create_file", fallback: "Create a new file with content. Fails if file already exists."),
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
    ]
}
