enum SettingsSection: String, CaseIterable, Identifiable {
    case custom = "Custom"
    case apiKeys = "API Keys"
    case cliTools = "CLI Tools"
    case mcp = "MCP Servers"
    case skillsPlugins = "Skills & Plugins"
    case rules = "Rules"
    case codebaseIndex = "Codebase Index"
    case behavior = "Behavior"
    case appearance = "Appearance"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .custom: return "slider.horizontal.3"
        case .apiKeys: return "key.fill"
        case .cliTools: return "terminal"
        case .mcp: return "server.rack"
        case .skillsPlugins: return "puzzlepiece.fill"
        case .rules: return "doc.text.fill"
        case .codebaseIndex: return "text.magnifyingglass"
        case .behavior: return "bolt.fill"
        case .appearance: return "paintbrush.fill"
        }
    }

    static var providerAI: [SettingsSection] { [.apiKeys] }
    static var tools: [SettingsSection] { [.cliTools, .mcp, .skillsPlugins] }
    static var general: [SettingsSection] { [.custom, .rules, .codebaseIndex, .behavior, .appearance] }
}
