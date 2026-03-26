import Foundation
import MCP

extension CoderIDETools {
    static let skillTools: [Tool] = [
        Tool(
            name: "coderide_skill",
            description: RustSyncedToolDescriptions.text(
                mcpName: "coderide_skill",
                fallback: "Invoke a local SKILL.md workflow when the task matches a skill."
            ),
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
