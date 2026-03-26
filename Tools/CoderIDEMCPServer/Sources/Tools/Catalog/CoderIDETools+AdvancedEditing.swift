import Foundation
import MCP

extension CoderIDETools {
    static let advancedEditingTools: [Tool] = [
        // --- Advanced Editing ---
        Tool(
            name: "coderide_regex_replace",
            description: RustSyncedToolDescriptions.text(mcpName: "coderide_regex_replace", fallback: "Replace text matching a regex pattern in a file."),
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
    ]
}
