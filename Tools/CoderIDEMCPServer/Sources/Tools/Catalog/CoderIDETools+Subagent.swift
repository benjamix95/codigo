import Foundation
import MCP

extension CoderIDETools {
    static let subagentTools: [Tool] = [
        // --- Subagent Tools ---
        Tool(
            name: "coderide_subagent_explorer",
            description: RustSyncedToolDescriptions.text(
                mcpName: "coderide_subagent_explorer",
                fallback: "Spawn a read-only explorer subagent for parallel codebase investigation."
            ),
            inputSchema: .object([
                "type": "object",
                "properties": .object([
                    "task": .object(["type": "string", "description": "What the explorer should investigate"]),
                ]),
                "required": .array([.string("task")]),
            ]),
            annotations: .init(title: "Subagent: Explorer", readOnlyHint: true)
        ),
        Tool(
            name: "coderide_subagent_coder",
            description: RustSyncedToolDescriptions.text(
                mcpName: "coderide_subagent_coder",
                fallback: "Spawn a coding subagent with full tool access."
            ),
            inputSchema: .object([
                "type": "object",
                "properties": .object([
                    "task": .object(["type": "string", "description": "Implementation task for the coder"]),
                ]),
                "required": .array([.string("task")]),
            ]),
            annotations: .init(title: "Subagent: Coder", readOnlyHint: false)
        ),
        Tool(
            name: "coderide_subagent_debugger",
            description: RustSyncedToolDescriptions.text(
                mcpName: "coderide_subagent_debugger",
                fallback: "Spawn a debugger subagent. Investigates and fixes bugs using search, read, edit and bash tools."
            ),
            inputSchema: .object([
                "type": "object",
                "properties": .object([
                    "task": .object(["type": "string", "description": "Bug or issue to investigate and fix"]),
                ]),
                "required": .array([.string("task")]),
            ]),
            annotations: .init(title: "Subagent: Debugger", readOnlyHint: false)
        ),
        Tool(
            name: "coderide_subagent_reviewer",
            description: RustSyncedToolDescriptions.text(
                mcpName: "coderide_subagent_reviewer",
                fallback: "Spawn a code review subagent."
            ),
            inputSchema: .object([
                "type": "object",
                "properties": .object([
                    "task": .object(["type": "string", "description": "What code changes to review"]),
                ]),
                "required": .array([.string("task")]),
            ]),
            annotations: .init(title: "Subagent: Reviewer", readOnlyHint: true)
        ),
        Tool(
            name: "coderide_subagent_bugHunter",
            description: RustSyncedToolDescriptions.text(
                mcpName: "coderide_subagent_bugHunter",
                fallback: "Spawn a bug hunting subagent."
            ),
            inputSchema: .object([
                "type": "object",
                "properties": .object([
                    "task": .object(["type": "string", "description": "Bug hunting scope and focus areas"]),
                ]),
                "required": .array([.string("task")]),
            ]),
            annotations: .init(title: "Subagent: BugHunter", readOnlyHint: true)
        ),
        Tool(
            name: "coderide_subagent_testWriter",
            description: RustSyncedToolDescriptions.text(
                mcpName: "coderide_subagent_testWriter",
                fallback: "Spawn a test-writing subagent that writes and runs tests for code changes."
            ),
            inputSchema: .object([
                "type": "object",
                "properties": .object([
                    "task": .object(["type": "string", "description": "What to test and what tests to write"]),
                ]),
                "required": .array([.string("task")]),
            ]),
            annotations: .init(title: "Subagent: TestWriter", readOnlyHint: false)
        ),
        Tool(
            name: "coderide_subagent_docWriter",
            description: RustSyncedToolDescriptions.text(
                mcpName: "coderide_subagent_docWriter",
                fallback: "Spawn a documentation subagent."
            ),
            inputSchema: .object([
                "type": "object",
                "properties": .object([
                    "task": .object(["type": "string", "description": "Documentation task to complete"]),
                ]),
                "required": .array([.string("task")]),
            ]),
            annotations: .init(title: "Subagent: DocWriter", readOnlyHint: false)
        ),
        Tool(
            name: "coderide_subagent_securityAuditor",
            description: RustSyncedToolDescriptions.text(
                mcpName: "coderide_subagent_securityAuditor",
                fallback: "Spawn a security auditor subagent."
            ),
            inputSchema: .object([
                "type": "object",
                "properties": .object([
                    "task": .object(["type": "string", "description": "Security audit scope and focus areas"]),
                ]),
                "required": .array([.string("task")]),
            ]),
            annotations: .init(title: "Subagent: SecurityAuditor", readOnlyHint: true)
        ),
    ]
}
