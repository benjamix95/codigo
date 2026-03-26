import Foundation
import MCP

extension CoderIDETools {
    static let planIntegrationTools: [Tool] = [
        Tool(
            name: "coderide_plan_create",
            description: RustSyncedToolDescriptions.text(mcpName: "coderide_plan_create", fallback: "Create or replace the current plan snapshot in the IDE plan panel."),
            inputSchema: .object([
                "type": "object",
                "properties": .object([
                    "goal": .object(["type": "string", "description": "Plan goal/title"]),
                    "steps": .object([
                        "type": "string",
                        "description": "JSON array of plan steps. Each item can include: id, title, description, target_file, status, linked_files, depends_on, notes."
                    ]),
                    "chosen_path": .object(["type": "string", "description": "Optional selected plan path markdown"]),
                    "conversation_id": .object(["type": "string", "description": "Optional conversation UUID"]),
                    "replace_existing": .object(["type": "string", "description": "Optional bool flag (default true)"]),
                ]),
                "required": .array([.string("goal")]),
            ]),
            annotations: .init(title: "Plan Create", readOnlyHint: false, idempotentHint: true)
        ),
        Tool(
            name: "coderide_plan_read",
            description: RustSyncedToolDescriptions.text(mcpName: "coderide_plan_read", fallback: "Read the latest plan snapshot from IDE shared state."),
            inputSchema: .object([
                "type": "object",
                "properties": .object([
                    "conversation_id": .object(["type": "string", "description": "Optional conversation UUID"]),
                    "include_history": .object(["type": "string", "description": "Optional bool flag"]),
                    "history_limit": .object(["type": "string", "description": "Optional history size (1-50)"]),
                ]),
            ]),
            annotations: .init(title: "Plan Read", readOnlyHint: true, idempotentHint: true)
        ),
        Tool(
            name: "coderide_plan_step_upsert",
            description: RustSyncedToolDescriptions.text(mcpName: "coderide_plan_step_upsert", fallback: "Create or update a full plan step with metadata."),
            inputSchema: .object([
                "type": "object",
                "properties": .object([
                    "step_id": .object(["type": "string", "description": "Step identifier"]),
                    "status": .object(["type": "string", "description": "pending, running, done, failed"]),
                    "title": .object(["type": "string", "description": "Optional step title"]),
                    "description": .object(["type": "string", "description": "Optional step description"]),
                    "target_file": .object(["type": "string", "description": "Optional target file path"]),
                    "linked_files": .object(["type": "string", "description": "Optional JSON array of related file paths"]),
                    "depends_on": .object(["type": "string", "description": "Optional JSON array of step ids"]),
                    "notes": .object(["type": "string", "description": "Optional step notes"]),
                    "conversation_id": .object(["type": "string", "description": "Optional conversation UUID"]),
                ]),
                "required": .array([.string("step_id"), .string("status")]),
            ]),
            annotations: .init(title: "Plan Step Upsert", readOnlyHint: false, idempotentHint: true)
        ),
        Tool(
            name: "coderide_plan_step_batch_update",
            description: RustSyncedToolDescriptions.text(mcpName: "coderide_plan_step_batch_update", fallback: "Batch update plan steps using a JSON array payload."),
            inputSchema: .object([
                "type": "object",
                "properties": .object([
                    "updates": .object([
                        "type": "string",
                        "description": "JSON array of objects. Each item requires step_id and status; optional title and notes."
                    ]),
                    "conversation_id": .object(["type": "string", "description": "Optional conversation UUID"]),
                ]),
                "required": .array([.string("updates")]),
            ]),
            annotations: .init(title: "Plan Step Batch Update", readOnlyHint: false, idempotentHint: true)
        ),
        Tool(
            name: "coderide_plan_step_reorder",
            description: RustSyncedToolDescriptions.text(mcpName: "coderide_plan_step_reorder", fallback: "Reorder plan steps using a JSON array of step ids."),
            inputSchema: .object([
                "type": "object",
                "properties": .object([
                    "ordered_step_ids": .object(["type": "string", "description": "JSON array of ordered step ids"]),
                    "conversation_id": .object(["type": "string", "description": "Optional conversation UUID"]),
                ]),
                "required": .array([.string("ordered_step_ids")]),
            ]),
            annotations: .init(title: "Plan Step Reorder", readOnlyHint: false, idempotentHint: true)
        ),
        Tool(
            name: "coderide_plan_step_dependency_set",
            description: RustSyncedToolDescriptions.text(mcpName: "coderide_plan_step_dependency_set", fallback: "Set dependencies for a specific plan step."),
            inputSchema: .object([
                "type": "object",
                "properties": .object([
                    "step_id": .object(["type": "string", "description": "Step identifier"]),
                    "depends_on": .object(["type": "string", "description": "JSON array of step ids"]),
                    "conversation_id": .object(["type": "string", "description": "Optional conversation UUID"]),
                ]),
                "required": .array([.string("step_id"), .string("depends_on")]),
            ]),
            annotations: .init(title: "Plan Step Dependency Set", readOnlyHint: false, idempotentHint: true)
        ),
        Tool(
            name: "coderide_plan_set_walkthrough",
            description: RustSyncedToolDescriptions.text(mcpName: "coderide_plan_set_walkthrough", fallback: "Store final walkthrough markdown and build outcome for the current plan."),
            inputSchema: .object([
                "type": "object",
                "properties": .object([
                    "markdown": .object(["type": "string", "description": "Walkthrough markdown content"]),
                    "summary": .object(["type": "string", "description": "Optional short summary"]),
                    "outcome": .object(["type": "string", "description": "done, failed, cancelled"]),
                    "conversation_id": .object(["type": "string", "description": "Optional conversation UUID"]),
                ]),
                "required": .array([.string("markdown")]),
            ]),
            annotations: .init(title: "Plan Set Walkthrough", readOnlyHint: false, idempotentHint: true)
        ),
        Tool(
            name: "coderide_plan_history_read",
            description: RustSyncedToolDescriptions.text(mcpName: "coderide_plan_history_read", fallback: "Read recent plan snapshots history."),
            inputSchema: .object([
                "type": "object",
                "properties": .object([
                    "conversation_id": .object(["type": "string", "description": "Optional conversation UUID"]),
                    "limit": .object(["type": "string", "description": "Max items to return (1-50)"]),
                ]),
            ]),
            annotations: .init(title: "Plan History Read", readOnlyHint: true, idempotentHint: true)
        ),
        Tool(
            name: "coderide_plan_diff",
            description: RustSyncedToolDescriptions.text(mcpName: "coderide_plan_diff", fallback: "Diff two plan snapshots and return added, removed and changed statuses."),
            inputSchema: .object([
                "type": "object",
                "properties": .object([
                    "from_snapshot_id": .object(["type": "string", "description": "Source snapshot id"]),
                    "to_snapshot_id": .object(["type": "string", "description": "Optional target snapshot id (defaults to latest)"]),
                    "conversation_id": .object(["type": "string", "description": "Optional conversation UUID"]),
                ]),
                "required": .array([.string("from_snapshot_id")]),
            ]),
            annotations: .init(title: "Plan Diff", readOnlyHint: true, idempotentHint: true)
        ),
        Tool(
            name: "coderide_plan_request_user_input",
            description: RustSyncedToolDescriptions.text(mcpName: "coderide_plan_request_user_input", fallback: "Request structured clarification questions in the IDE plan panel."),
            inputSchema: .object([
                "type": "object",
                "properties": .object([
                    "questions": .object([
                        "type": "string",
                        "description": "JSON array of questions. Each item supports: id, prompt/question, multi_select/allow_multiple (bool), options (array of {label/text, description, recommended})."
                    ]),
                    "title": .object(["type": "string", "description": "Optional UI title for this question round"]),
                    "phase": .object(["type": "string", "description": "Optional phase label, e.g. post-analysis"]),
                    "round": .object(["type": "string", "description": "Optional clarification round number"]),
                    "context": .object(["type": "string", "description": "Optional short blocker/context summary"]),
                    "conversation_id": .object(["type": "string", "description": "Optional conversation UUID"]),
                ]),
                "required": .array([.string("questions")]),
            ]),
            annotations: .init(title: "Plan Request User Input", readOnlyHint: false, idempotentHint: true)
        ),
    ]
}
