import Foundation

extension UnifiedToolRuntime {
    static let preferredRustAliasFamilies: [String] = [
        "audit_",
        "bughunter_",
        "debug_",
        "plan_",
        "review_",
        "security_",
        "subagent_",
        "todo_",
    ]

    static let preferredRustAliasTools: Set<String> = [
        "activate_debug_mode",
        "activate_plan_mode",
        "codebase_search",
        "create_file",
        "diagnostics",
        "edit",
        "file_outline",
        "find_files",
        "find_references",
        "find_symbol",
        "git_diff",
        "glob",
        "grep",
        "list_dir",
        "mermaid_render",
        "policy_ack",
        "read",
        "read_lints",
        "read_range",
        "regex_replace",
        "semantic_search",
        "show_swarm_panel",
        "show_task_panel",
        "skill",
        "str_replace",
        "web_fetch",
        "web_search",
        "write",
    ]

    static func shouldPreferRustAlias(for toolName: String) -> Bool {
        if preferredRustAliasTools.contains(toolName) {
            return true
        }
        return preferredRustAliasFamilies.contains { toolName.hasPrefix($0) }
    }

    func preferredRustAliasRoute(for toolName: String) -> (serverId: String, toolName: String)? {
        guard Self.shouldPreferRustAlias(for: toolName) else { return nil }
        if let aliasRoute = MCPNativeToolRegistry.shared.aliasRoute(for: toolName) {
            return aliasRoute
        }
        return MCPNativeToolRegistry.shared.routing["coderide_\(toolName)"]
    }
}
