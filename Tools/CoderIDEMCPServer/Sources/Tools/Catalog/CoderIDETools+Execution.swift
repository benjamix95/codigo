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
        Tool(
            name: "coderide_run_tests",
            description: "Run unit tests (cargo test or swift test) in the workspace root.",
            inputSchema: .object([
                "type": "object",
                "properties": .object([
                    "filter": .object([
                        "type": "string",
                        "description": "Optional test name filter (cargo) or swift test --filter pattern",
                    ]),
                ]),
            ]),
            annotations: .init(title: "Run Tests", readOnlyHint: false, idempotentHint: true)
        ),
        Tool(
            name: "coderide_export_debug_bundle",
            description: "Zip SoloCode AgentDebug NDJSON logs for this workspace into .solocode for support.",
            inputSchema: .object([
                "type": "object",
                "properties": .object([:]),
            ]),
            annotations: .init(title: "Export Debug Bundle", readOnlyHint: false, idempotentHint: true)
        ),

    ]
}
