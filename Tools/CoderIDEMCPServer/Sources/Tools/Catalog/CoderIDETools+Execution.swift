import Foundation
import MCP

extension CoderIDETools {
    static let executionTools: [Tool] = [
        // --- Execution ---
        Tool(
            name: "coderide_git_diff",
            description: RustSyncedToolDescriptions.text(mcpName: "coderide_git_diff", fallback: "Show git diff for the current workspace."),
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
            description: RustSyncedToolDescriptions.text(mcpName: "coderide_diagnostics", fallback: "Run full build diagnostics and return errors/warnings."),
            inputSchema: .object([
                "type": "object",
                "properties": .object([
                    "path": .object(["type": "string", "description": "Optional path scope"]),
                ]),
            ]),
            annotations: .init(title: "Diagnostics", readOnlyHint: true)
        ),
        Tool(
            name: "coderide_benchmark_indexing",
            description: RustSyncedToolDescriptions.text(mcpName: "coderide_benchmark_indexing", fallback: "Run the indexing hardening benchmark script and collect JSON/log artifacts."),
            inputSchema: .object([
                "type": "object",
                "properties": .object([
                    "phase": .object(["type": "string", "description": "Required benchmark phase: pre or post"]),
                    "tag": .object(["type": "string", "description": "Optional artifact tag"]),
                    "runs": .object(["type": "string", "description": "Optional measured run count"]),
                    "warmup": .object(["type": "string", "description": "Optional warmup run count"]),
                    "files": .object(["type": "string", "description": "Optional synthetic file count"]),
                ]),
                "required": .array([.string("phase")]),
            ]),
            annotations: .init(title: "Benchmark Indexing", readOnlyHint: false, idempotentHint: true)
        ),
        Tool(
            name: "coderide_benchmark_review_pipeline",
            description: RustSyncedToolDescriptions.text(mcpName: "coderide_benchmark_review_pipeline", fallback: "Run the review-core benchmark script and collect engine/app JSON artifacts."),
            inputSchema: .object([
                "type": "object",
                "properties": .object([
                    "phase": .object(["type": "string", "description": "Required benchmark phase: pre or post"]),
                    "tag": .object(["type": "string", "description": "Optional artifact tag"]),
                ]),
                "required": .array([.string("phase")]),
            ]),
            annotations: .init(title: "Benchmark Review Pipeline", readOnlyHint: false, idempotentHint: true)
        ),
        Tool(
            name: "coderide_read_lints",
            description: RustSyncedToolDescriptions.text(mcpName: "coderide_read_lints", fallback: "Read lint warnings/errors without full build. Faster than diagnostics."),
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
            description: RustSyncedToolDescriptions.text(mcpName: "coderide_run_tests", fallback: "Run unit tests (cargo test, swift test, or xcodebuild test when a .xcodeproj is present)."),
            inputSchema: .object([
                "type": "object",
                "properties": .object([
                    "filter": .object([
                        "type": "string",
                        "description": "Optional: cargo test name, swift test --filter, or xcodebuild -only-testing",
                    ]),
                    "scheme": .object([
                        "type": "string",
                        "description": "For Xcode only: scheme name if different from xcodebuild -list default",
                    ]),
                ]),
            ]),
            annotations: .init(title: "Run Tests", readOnlyHint: false, idempotentHint: true)
        ),
        Tool(
            name: "coderide_export_debug_bundle",
            description: RustSyncedToolDescriptions.text(mcpName: "coderide_export_debug_bundle", fallback: "Zip SoloCode AgentDebug NDJSON logs into .solocode."),
            inputSchema: .object([
                "type": "object",
                "properties": .object([
                    "workspace_roots": .object([
                        "type": "string",
                        "description": "Comma-separated workspace roots (same order as app optional); required for multi-root fingerprint match",
                    ]),
                ]),
            ]),
            annotations: .init(title: "Export Debug Bundle", readOnlyHint: false, idempotentHint: true)
        ),

    ]
}
