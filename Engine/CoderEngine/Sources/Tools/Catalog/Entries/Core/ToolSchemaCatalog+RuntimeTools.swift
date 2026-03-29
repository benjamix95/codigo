import Foundation

extension ToolSchemaCatalog {
    static let runtimeTools: [ToolSchemaEntry] = [
        ToolSchemaEntry(
            name: "build_project",
            description: "Build the project",
            properties: [
                "configuration": ["type": "string", "description": "debug or release"],
                "target": ["type": "string", "description": "Optional build target"],
                "timeout_ms": ["type": "string", "description": "Timeout in milliseconds"]
            ],
            required: []
        ),
        ToolSchemaEntry(
            name: "diagnostics",
            description: "Get structured build diagnostics",
            properties: [
                "manager": ["type": "string", "description": "Optional build manager override"]
            ],
            required: []
        ),
        ToolSchemaEntry(
            name: "benchmark_indexing",
            description: "Run the indexing hardening benchmark script and collect JSON/log artifacts",
            properties: [
                "phase": ["type": "string", "description": "Required benchmark phase: pre or post"],
                "tag": ["type": "string", "description": "Optional artifact tag; defaults to UTC timestamp"],
                "runs": ["type": "string", "description": "Optional measured run count"],
                "warmup": ["type": "string", "description": "Optional warmup run count"],
                "files": ["type": "string", "description": "Optional synthetic file count"]
            ],
            required: ["phase"]
        ),
        ToolSchemaEntry(
            name: "benchmark_review_pipeline",
            description: "Run the review-core benchmark script and collect engine/app JSON artifacts",
            properties: [
                "phase": ["type": "string", "description": "Required benchmark phase: pre or post"],
                "tag": ["type": "string", "description": "Optional artifact tag; defaults to review-core-smoke"]
            ],
            required: ["phase"]
        ),
        ToolSchemaEntry(
            name: "benchmark_semantic_search",
            description: "Run the semantic search benchmark test and collect JSON/log artifacts",
            properties: [
                "mode": ["type": "string", "description": "Optional benchmark mode: smoke or full"],
                "tag": ["type": "string", "description": "Optional artifact tag; defaults to UTC timestamp"]
            ],
            required: []
        ),
        ToolSchemaEntry(
            name: "read_lints",
            description: "Read lints and diagnostics without full build",
            properties: [
                "path": ["type": "string", "description": "Optional file scope"],
                "severity": ["type": "string", "description": "all|error|warning"],
                "limit": ["type": "string", "description": "Maximum number of diagnostics"]
            ],
            required: []
        ),
        ToolSchemaEntry(
            name: "attempt_completion",
            description: "Signal task completion with optional verification",
            properties: [
                "result": ["type": "string", "description": "Completion summary"],
                "command": ["type": "string", "description": "Optional verification command"]
            ],
            required: ["result"]
        ),
        ToolSchemaEntry(
            name: "list_processes",
            description: "List running processes",
            properties: [
                "filter": ["type": "string", "description": "Optional process filter"]
            ],
            required: []
        ),
        ToolSchemaEntry(
            name: "read_json",
            description: "Read and pretty-print JSON file",
            properties: [
                "path": ["type": "string", "description": "JSON file path"]
            ],
            required: ["path"]
        ),
        ToolSchemaEntry(
            name: "write_json",
            description: "Merge JSON patch into JSON file",
            properties: [
                "path": ["type": "string", "description": "JSON file path"],
                "patch": ["type": "string", "description": "JSON object patch string"]
            ],
            required: ["path", "patch"]
        ),
        ToolSchemaEntry(
            name: "workspace_stats",
            description: "Collect workspace statistics",
            properties: [
                "path": ["type": "string", "description": "Optional relative scope"]
            ],
            required: []
        ),
        ToolSchemaEntry(
            name: "dependency_audit",
            description: "Run dependency audit",
            properties: [
                "manager": ["type": "string", "description": "swift|npm|pnpm|yarn"]
            ],
            required: []
        ),
        ToolSchemaEntry(
            name: "tail_log",
            description: "Tail a log file",
            properties: [
                "path": ["type": "string", "description": "Log file path"],
                "lines": ["type": "string", "description": "Number of lines"]
            ],
            required: ["path"]
        ),
    ]
}
