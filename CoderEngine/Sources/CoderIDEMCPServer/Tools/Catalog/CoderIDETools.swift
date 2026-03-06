import Foundation
import MCP

/// All tools exposed by CoderIDE MCP Server, with their JSON schemas.
/// Codex CLI will register these as available tools for the model.
struct CoderIDETools {
    static let all: [Tool] = fileTools
        + searchTools
        + executionTools
        + webTools
        + advancedEditingTools
        + ideIntegrationTools
        + planIntegrationTools
        + skillTools
        + debugTools
        + codeReviewTools

    /// Map MCP tool name → UnifiedToolRuntime tool name.
    /// Supports both plain names (`coderide_read`) and namespaced references
    /// (`coderide/coderide_read`) emitted by some MCP clients.
    static func runtimeToolName(from mcpName: String) -> String {
        var normalized = mcpName.trimmingCharacters(in: .whitespacesAndNewlines)
        if let slash = normalized.lastIndex(of: "/") {
            let afterSlash = normalized[normalized.index(after: slash)...]
            normalized = afterSlash.isEmpty ? String(normalized[..<slash]) : String(afterSlash)
        }
        if normalized.hasPrefix("coderide_") {
            return String(normalized.dropFirst("coderide_".count))
        }
        return normalized
    }
}
