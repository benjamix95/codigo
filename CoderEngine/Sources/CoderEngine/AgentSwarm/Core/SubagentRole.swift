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
    /// Read-only roles can search/read/analyze but never edit.
    public var canEditFiles: Bool {
        switch self {
        case .explorer, .reviewer, .securityAuditor:
            return false
        default: return true
        }
    }

    /// Maximum tool execution rounds for this subagent.
    /// Read-only analysis roles get lower budgets than write-capable roles.
    public var maxToolRounds: Int {
        switch self {
        case .explorer:
            return 40
        case .reviewer, .securityAuditor:
            return 50
        case .testWriter:
            return 100
        case .coder, .debugger, .docWriter:
            return 80
        }
    }

    /// Resolve a `SubagentRole` from a tool name like `subagent_explorer`.
    public static func fromToolName(_ name: String) -> SubagentRole? {
        let normalized = name
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "-", with: "_")
            .lowercased()
        guard normalized.hasPrefix("subagent_") else { return nil }
        let suffix = String(normalized.dropFirst("subagent_".count))

        // Accept canonical names plus legacy/normalized aliases so tool calls from
        // different providers (camelCase, snake_case, lowercase) all resolve.
        switch suffix {
        case "explorer":
            return .explorer
        case "coder":
            return .coder
        case "debugger":
            return .debugger
        case "reviewer":
            return .reviewer
        case "testwriter", "test_writer", "tester":
            return .testWriter
        case "docwriter", "doc_writer":
            return .docWriter
        case "securityauditor", "security_auditor":
            return .securityAuditor
        default:
            return nil
        }
    }

    /// All tool names for registering in the system prompt.
    public static var allToolNames: [String] {
        allCases.map(\.toolName)
    }
}
