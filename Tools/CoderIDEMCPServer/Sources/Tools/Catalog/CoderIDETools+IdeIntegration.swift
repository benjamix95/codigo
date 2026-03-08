import Foundation
import MCP

extension CoderIDETools {
    static let ideIntegrationTools: [Tool] = [
        // --- IDE Integration (Todo / Plan) ---
        Tool(
            name: "coderide_todo_write",
            description: """
                Update the IDE todo list. Prefer single-item shorthand via 'title' + 'status'. \
                For batch initialization, pass 'todos' as a JSON array string or structured array. \
                Each item must have 'content' (string) and 'status' (pending|in_progress|done|blocked). \
                Optional fields: 'activeForm' (present-tense label shown during execution), \
                'priority' (low|medium|high), 'linkedFiles' (array of file paths related to the task). \
                Use this tool to track multi-step task progress in the IDE live card.
                """,
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
            description: "Read the current IDE todo list. Returns the current state of all tracked todo items.",
            inputSchema: .object([
                "type": "object",
                "properties": .object([:]),
            ]),
            annotations: .init(title: "Todo Read", readOnlyHint: true, idempotentHint: true)
        ),
        Tool(
            name: "coderide_plan_step_update",
            description: """
                Update the status of a plan step in the IDE plan panel. \
                Use this during plan execution to track progress of each step.
                """,
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
            description: """
                Render a mermaid diagram in the IDE chat and plan panel. \
                Pass mermaid syntax (flowchart, sequence, class, state, etc.) and it will \
                be displayed as an interactive rendered diagram. Use this to visualize \
                architecture, flows, dependencies, and relationships. \
                ALWAYS use this tool when analyzing problems or creating plans to provide \
                visual context.
                """,
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

        // --- IDE Integration (Debug Panel / Mode Activation / Swarm) ---
        Tool(
            name: "coderide_debug_set_phase",
            description: "Set the debug panel phase in a strongly-typed way.",
            inputSchema: .object([
                "type": "object",
                "properties": .object([
                    "phase": .object([
                        "type": "string",
                        "description": "Debug phase: describing, reproducing, fixing, instrumenting, verifying, resolved"
                    ]),
                    "detail": .object(["type": "string", "description": "Optional human-readable context for this phase transition"]),
                ]),
                "required": .array([.string("phase")]),
            ]),
            annotations: .init(title: "Debug Set Phase", readOnlyHint: false)
        ),
        Tool(
            name: "coderide_debug_request_user",
            description: "Request explicit user interaction during debugging.",
            inputSchema: .object([
                "type": "object",
                "properties": .object([
                    "kind": .object([
                        "type": "string",
                        "description": "Request kind: question or reproduce"
                    ]),
                    "prompt": .object([
                        "type": "string",
                        "description": "Prompt shown to the user"
                    ]),
                ]),
                "required": .array([.string("kind"), .string("prompt")]),
            ]),
            annotations: .init(title: "Debug Request User", readOnlyHint: false)
        ),
        Tool(
            name: "coderide_debug_resolve",
            description: "Resolve the active debug session with a summary.",
            inputSchema: .object([
                "type": "object",
                "properties": .object([
                    "summary": .object(["type": "string", "description": "Resolution summary"]),
                ]),
                "required": .array([.string("summary")]),
            ]),
            annotations: .init(title: "Debug Resolve", readOnlyHint: false)
        ),
        Tool(
            name: "coderide_policy_ack",
            description: "Acknowledge a mandatory instruction policy hash before performing tool operations.",
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
            description: "Request the IDE to activate the plan mode panel for structured planning.",
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
            description: "Request the IDE to activate the debug mode panel for structured debugging.",
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
            description: "Show the IDE task/activity panel to display ongoing task progress.",
            inputSchema: .object([
                "type": "object",
                "properties": .object([:]),
            ]),
            annotations: .init(title: "Show Task Panel", readOnlyHint: false)
        ),
        Tool(
            name: "coderide_show_swarm_panel",
            description: "Request the IDE to open/focus the swarm panel.",
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
