import Foundation
import MCP

extension CoderIDETools {
    static let subagentTools: [Tool] = [
        // --- Subagent Tools ---
        Tool(
            name: "coderide_subagent_explorer",
            description: "Spawn a read-only explorer subagent for parallel codebase investigation. The subagent can search, read, and analyze code but cannot edit files. Use for gathering context in parallel.",
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
            description: "Spawn a coding subagent with full tool access (edit, bash, etc.). Each coder works on a different file or module in parallel.",
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
            description: "Spawn a debugger subagent. Investigates and fixes bugs using search, read, edit and bash tools.",
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
            description: "Spawn a code review subagent. Reviews code quality, bugs, style, and potential issues.",
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
            description: "Spawn a bug hunting subagent that focuses on regressions, crash risks, concurrency issues, test gaps, and boundary-condition bugs.",
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
            description: "Spawn a test-writing subagent that writes and runs tests for code changes.",
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
            description: "Spawn a documentation subagent that writes README sections, inline comments, docstrings, and API docs.",
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
            description: "Spawn a security auditor subagent that analyzes code for vulnerabilities, insecure dependencies, and OWASP top 10 issues.",
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
