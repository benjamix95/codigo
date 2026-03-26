import Foundation
import MCP

/// All tools exposed by CoderIDE MCP Server, with their JSON schemas.
/// Codex CLI will register these as available tools for the model.
///
/// **Parità con Rust:** i nomi devono coincidere con `Native/CoderideMCPServerRust/src/tool_names.txt`.
/// Le descrizioni mostrate dal server MCP Rust in `tools/list` sono il testo unione di
/// `tool_descriptions.json` + blurbs audit in `tool_descriptions.rs` (ogni voce include la clausola **Usage:**).
///
/// Ordine di aggiornamento per un nuovo tool: (1) riga in `tool_names.txt`, (2) voce in
/// `tool_descriptions.json` (non-audit) o blurbs in `tool_descriptions.rs` (audit), (3) schema in
/// `tool_schema*.rs` / `tool_schema_workflow_*`, (4) `Tool` qui in Swift, (5) `CATALOG_TOOL_COUNT` in `catalog.rs`.
struct CoderIDETools {
    static let all: [Tool] = fileTools
        + searchTools
        + executionTools
        + auditTools
        + webTools
        + advancedEditingTools
        + ideIntegrationTools
        + planIntegrationTools
        + skillTools
        + debugTools
        + subagentTools
        + bugHunterTools
        + securityWorkflowTools
        + codeReviewTools

    private static let allowedRuntimeToolNames: Set<String> = Set(
        all.map { runtimeToolName(from: $0.name) }
    )

    static func isAllowedRuntimeToolName(_ runtimeToolName: String) -> Bool {
        allowedRuntimeToolNames.contains(runtimeToolName)
    }

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
