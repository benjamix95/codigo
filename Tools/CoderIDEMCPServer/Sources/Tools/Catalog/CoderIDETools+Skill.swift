import Foundation
import MCP

extension CoderIDETools {
    static let skillTools: [Tool] = [
        Tool(
            name: "coderide_skill",
            description: """
                Invoke a local skill (SKILL.md) from ~/.codex/skills, ~/.claude/skills, or ~/.agents/skills. \
                Use when the task matches a skill's description (doc, imagegen, transcribe, code-review, playwright, \
                cloudflare-deploy, gh-fix-ci). Prefer skills over manual workflows when a skill exists for the task.
                """,
            inputSchema: .object([
                "type": "object",
                "properties": .object([
                    "skill": .object([
                        "type": "string",
                        "description": "Skill name (e.g. doc, imagegen, transcribe, code-review)",
                    ]),
                    "name": .object([
                        "type": "string",
                        "description": "Alias for skill",
                    ]),
                    "task": .object([
                        "type": "string",
                        "description": "What the skill should do",
                    ]),
                    "args": .object([
                        "type": "string",
                        "description": "Alias for task",
                    ]),
                ]),
            ]),
            annotations: .init(title: "Invoke Skill", readOnlyHint: false)
        ),
    ]
}
