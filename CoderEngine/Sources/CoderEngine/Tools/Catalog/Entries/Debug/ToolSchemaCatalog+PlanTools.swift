import Foundation

extension ToolSchemaCatalog {
    static let planTools: [ToolSchemaEntry] = [
        ToolSchemaEntry(
            name: "plan_create",
            description: "Create or replace the current plan snapshot in IDE shared state.",
            properties: [
                "goal": ["type": "string", "description": "Plan goal/title"],
                "steps": ["type": "string", "description": "JSON array of steps"],
                "chosen_path": ["type": "string", "description": "Optional selected plan path markdown"],
                "conversation_id": ["type": "string", "description": "Optional conversation UUID"],
                "replace_existing": ["type": "string", "description": "Optional bool flag (default true)"],
            ],
            required: ["goal"]
        ),
        ToolSchemaEntry(
            name: "plan_read",
            description: "Read latest plan snapshot from IDE shared state.",
            properties: [
                "conversation_id": ["type": "string", "description": "Optional conversation UUID"],
                "include_history": ["type": "string", "description": "Optional bool flag"],
                "history_limit": ["type": "string", "description": "Optional history size (1-50)"],
            ],
            required: []
        ),
        ToolSchemaEntry(
            name: "plan_step_upsert",
            description: "Create or update a plan step with metadata.",
            properties: [
                "step_id": ["type": "string", "description": "Plan step id"],
                "status": ["type": "string", "description": "pending|running|done|failed"],
                "title": ["type": "string", "description": "Optional step title"],
                "description": ["type": "string", "description": "Optional step description"],
                "target_file": ["type": "string", "description": "Optional target file path"],
                "linked_files": ["type": "string", "description": "Optional JSON array of file paths"],
                "depends_on": ["type": "string", "description": "Optional JSON array of step ids"],
                "notes": ["type": "string", "description": "Optional notes"],
                "conversation_id": ["type": "string", "description": "Optional conversation UUID"],
            ],
            required: ["step_id", "status"]
        ),
        ToolSchemaEntry(
            name: "plan_step_batch_update",
            description: "Batch update multiple plan steps.",
            properties: [
                "updates": ["type": "string", "description": "JSON array of updates with step_id/status and optional fields"],
                "conversation_id": ["type": "string", "description": "Optional conversation UUID"],
            ],
            required: ["updates"]
        ),
        ToolSchemaEntry(
            name: "plan_step_reorder",
            description: "Reorder plan steps using ordered step ids.",
            properties: [
                "ordered_step_ids": ["type": "string", "description": "JSON array of step ids"],
                "conversation_id": ["type": "string", "description": "Optional conversation UUID"],
            ],
            required: ["ordered_step_ids"]
        ),
        ToolSchemaEntry(
            name: "plan_step_dependency_set",
            description: "Set dependency step ids for a plan step.",
            properties: [
                "step_id": ["type": "string", "description": "Plan step id"],
                "depends_on": ["type": "string", "description": "JSON array of dependency step ids"],
                "conversation_id": ["type": "string", "description": "Optional conversation UUID"],
            ],
            required: ["step_id", "depends_on"]
        ),
        ToolSchemaEntry(
            name: "plan_set_walkthrough",
            description: "Store walkthrough markdown and optional outcome for the current plan.",
            properties: [
                "markdown": ["type": "string", "description": "Walkthrough markdown"],
                "summary": ["type": "string", "description": "Optional summary"],
                "outcome": ["type": "string", "description": "done|failed|cancelled"],
                "conversation_id": ["type": "string", "description": "Optional conversation UUID"],
            ],
            required: ["markdown"]
        ),
        ToolSchemaEntry(
            name: "plan_history_read",
            description: "Read recent plan snapshots history.",
            properties: [
                "conversation_id": ["type": "string", "description": "Optional conversation UUID"],
                "limit": ["type": "string", "description": "Number of snapshots to read (1-50)"],
            ],
            required: []
        ),
        ToolSchemaEntry(
            name: "plan_diff",
            description: "Diff two plan snapshots.",
            properties: [
                "from_snapshot_id": ["type": "string", "description": "Source snapshot id"],
                "to_snapshot_id": ["type": "string", "description": "Optional target snapshot id"],
                "conversation_id": ["type": "string", "description": "Optional conversation UUID"],
            ],
            required: ["from_snapshot_id"]
        ),
    ]
}
