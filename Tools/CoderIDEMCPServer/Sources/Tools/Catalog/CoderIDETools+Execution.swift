import Foundation
import MCP

extension CoderIDETools {
    static let executionTools: [Tool] = [
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

    ]
}
