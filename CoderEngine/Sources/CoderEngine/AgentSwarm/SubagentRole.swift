import Foundation

/// Specialized roles for inline subagent execution.
/// Each role maps to a `subagent_<role>` tool the main agent can call during streaming.
public enum SubagentRole: String, CaseIterable, Codable, Sendable {
    case explorer
    case coder
    case debugger
    case reviewer
    case testWriter
    case docWriter
    case securityAuditor

    /// Tool name registered in the system prompt (e.g. `subagent_explorer`).
    public var toolName: String { "subagent_\(rawValue)" }

    /// Human-readable name for UI.
    public var displayName: String {
        switch self {
        case .explorer:        return "Explorer"
        case .coder:           return "Coder"
        case .debugger:        return "Debugger"
        case .reviewer:        return "Reviewer"
        case .testWriter:      return "TestWriter"
        case .docWriter:       return "DocWriter"
        case .securityAuditor: return "SecurityAuditor"
        }
    }

    /// Whether this subagent can use file-editing tools.
    /// Explorer is read-only — it can search, read, and analyze but never edit.
    public var canEditFiles: Bool {
        switch self {
        case .explorer: return false
        default: return true
        }
    }

    /// Maximum tool execution rounds for this subagent.
    /// Explorer has a lower budget since it only reads.
    public var maxToolRounds: Int {
        switch self {
        case .explorer: return 40
        default: return 80
        }
    }

    /// Resolve a `SubagentRole` from a tool name like `subagent_explorer`.
    public static func fromToolName(_ name: String) -> SubagentRole? {
        guard name.hasPrefix("subagent_") else { return nil }
        let suffix = String(name.dropFirst("subagent_".count))
        return SubagentRole(rawValue: suffix)
    }

    /// All tool names for registering in the system prompt.
    public static var allToolNames: [String] {
        allCases.map(\.toolName)
    }
}
