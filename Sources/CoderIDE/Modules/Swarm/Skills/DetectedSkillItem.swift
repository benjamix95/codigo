import Foundation

struct DetectedSkillItem: Identifiable {
    let id: String
    let name: String
    let source: SkillSource
    let kind: SkillKind
    let path: String

    enum SkillSource: String {
        case claude = "Claude"
        case codex = "Codex"
        case gemini = "Gemini"
        case mcp = "MCP"
    }

    enum SkillKind: String {
        case skill = "Skill"
        case plugin = "Plugin"
        case prompt = "Prompt"
        case command = "Command"
    }
}
