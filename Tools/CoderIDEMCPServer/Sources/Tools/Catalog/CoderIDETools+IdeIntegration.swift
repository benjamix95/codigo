import Foundation
import MCP

extension CoderIDETools {
    static let ideIntegrationTools: [Tool] = [
        // --- IDE Integration (Todo / Plan) ---
        Tool(
            name: "coderide_todo_write",
            description: RustSyncedToolDescriptions.text(
                mcpName: "coderide_todo_write",
                fallback: "Update the IDE todo list; prefer todos JSON or title/status shorthand."
            ),
            inputSchema: .object([
                "type": "object",
                "properties": .object([
                    "todos": .object([
                        "type": "string",
                        "description": "Batch mode: JSON array string of todo items. If native structured args are available, an array is also accepted.",
                    ]),
                    // Single-item shorthand
                    "title": .object(["type": "string", "description": "Single todo title (shorthand — use 'todos' for batch updates)"]),
                    "status": .object(["type": "string", "description": "Status: pending, in_progress, done, blocked"]),
                    "priority": .object(["type": "string", "description": "Priority: low, medium, high"]),
                ]),
            ]),
            annotations: .init(title: "Todo Write", readOnlyHint: false, idempotentHint: true)
        ),
        Tool(
            name: "coderide_todo_read",
            description: RustSyncedToolDescriptions.text(mcpName: "coderide_todo_read", fallback: "Read the current IDE todo list."),
            inputSchema: .object([
                "type": "object",
                "properties": .object([:]),
            ]),
            annotations: .init(title: "Todo Read", readOnlyHint: true, idempotentHint: true)
        ),
        Tool(
            name: "coderide_plan_step_update",
            description: RustSyncedToolDescriptions.text(
                mcpName: "coderide_plan_step_update",
                fallback: "Update the status of a plan step in the IDE plan panel."
            ),
            inputSchema: .object([
                "type": "object",
                "properties": .object([
                    "step_id": .object(["type": "string", "description": "The step identifier (e.g. '1', '2')"]),
                    "status": .object(["type": "string", "description": "Step status: pending, running, done, failed"]),
                    "title": .object(["type": "string", "description": "Optional step title"]),
                ]),
                "required": .array([.string("step_id"), .string("status")]),
            ]),
            annotations: .init(title: "Plan Step Update", readOnlyHint: false, idempotentHint: true)
        ),
        Tool(
            name: "coderide_mermaid_render",
            description: RustSyncedToolDescriptions.text(
                mcpName: "coderide_mermaid_render",
                fallback: "Render Mermaid diagram in the IDE."
            ),
            inputSchema: .object([
                "type": "object",
                "properties": .object([
                    "code": .object(["type": "string", "description": "Mermaid diagram code (e.g. 'graph TD; A-->B;')"]),
                    "title": .object(["type": "string", "description": "Optional title for the diagram"]),
                ]),
                "required": .array([.string("code")]),
            ]),
            annotations: .init(title: "Render Mermaid Diagram", readOnlyHint: false)
        ),

        // coderide_debug_set_phase / request_user / resolve: definiti in `CoderIDETools+Debug.swift` (evita duplicati in `all`).

        // --- IDE Integration (policy / modes / swarm) ---
        Tool(
            name: "coderide_policy_ack",
            description: RustSyncedToolDescriptions.text(mcpName: "coderide_policy_ack", fallback: "Acknowledge a mandatory instruction policy hash before performing tool operations."),
            inputSchema: .object([
                "type": "object",
                "properties": .object([
                    "hash": .object(["type": "string", "description": "The policy hash to acknowledge"]),
                ]),
                "required": .array([.string("hash")]),
            ]),
            annotations: .init(title: "Policy Acknowledge", readOnlyHint: false)
        ),
        Tool(
            name: "coderide_activate_plan_mode",
            description: RustSyncedToolDescriptions.text(mcpName: "coderide_activate_plan_mode", fallback: "Request the IDE to activate the plan mode panel for structured planning."),
            inputSchema: .object([
                "type": "object",
                "properties": .object([
                    "reason": .object(["type": "string", "description": "Optional reason for activating plan mode"]),
                ]),
            ]),
            annotations: .init(title: "Activate Plan Mode", readOnlyHint: false)
        ),
        Tool(
            name: "coderide_activate_debug_mode",
            description: RustSyncedToolDescriptions.text(
                mcpName: "coderide_activate_debug_mode",
                fallback: "Request the IDE to activate the debug mode panel for structured debugging."
            ),
            inputSchema: .object([
                "type": "object",
                "properties": .object([
                    "reason": .object(["type": "string", "description": "Optional reason for activating debug mode"]),
                ]),
            ]),
            annotations: .init(title: "Activate Debug Mode", readOnlyHint: false)
        ),
        Tool(
            name: "coderide_show_task_panel",
            description: RustSyncedToolDescriptions.text(mcpName: "coderide_show_task_panel", fallback: "Show the IDE task/activity panel to display ongoing task progress."),
            inputSchema: .object([
                "type": "object",
                "properties": .object([:]),
            ]),
            annotations: .init(title: "Show Task Panel", readOnlyHint: false)
        ),
        Tool(
            name: "coderide_show_swarm_panel",
            description: RustSyncedToolDescriptions.text(mcpName: "coderide_show_swarm_panel", fallback: "Request the IDE to open/focus the swarm panel."),
            inputSchema: .object([
                "type": "object",
                "properties": .object([
                    "swarm_id": .object(["type": "string", "description": "Optional swarm id to focus immediately"]),
                ]),
            ]),
            annotations: .init(title: "Show Swarm Panel", readOnlyHint: false)
        ),

    ]
}
