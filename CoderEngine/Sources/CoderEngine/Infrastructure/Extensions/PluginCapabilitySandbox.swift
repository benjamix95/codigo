import Foundation

enum PluginCapabilitySandbox {
    private static let toolsByCapability: [PluginCapability: Set<String>] = [
        .read: ["read", "read_range", "list_dir", "find_files", "glob", "grep", "semantic_search", "codebase_search", "find_symbol", "find_references", "file_outline"],
        .edit: ["edit", "str_replace", "multi_edit", "parallel_apply", "apply_diff"],
        .write: ["write", "create_file", "write_json"],
        .bash: ["bash", "run_tests", "build_project", "diagnostics", "read_lints"],
        .web: ["web_search", "web_fetch"],
        .mcp: ["mcp_call", "mcp_batch", "mcp_list_resources", "mcp_read_resource", "mcp_health", "mcp_reconnect", "mcp_restart_server"],
        .git: ["git_diff", "git_status", "git_show", "git_log_search"],
        .debug: ["debug_context", "debug_log", "debug_query", "debug_session", "debug_hypothesize", "debug_mark", "debug_clean", "debug_set_phase", "debug_request_user", "debug_resolve"],
        .subagent: ["subagent_explorer", "subagent_coder", "subagent_reviewer", "subagent_testWriter", "subagent_debugger", "subagent_docWriter", "subagent_securityAuditor"],
    ]

    static func validate(
        _ manifest: IDEPluginManifest,
        currentIDEVersion: String
    ) throws {
        if manifest.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw IDEPluginRuntimeError.invalidManifest("id vuoto")
        }
        if manifest.entryPoint.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw IDEPluginRuntimeError.invalidManifest("entryPoint vuoto")
        }
        if manifest.capabilities.isEmpty {
            throw IDEPluginRuntimeError.invalidManifest("capabilities vuote")
        }

        if let minimum = manifest.minimumIDEVersion?.trimmingCharacters(in: .whitespacesAndNewlines),
           !minimum.isEmpty {
            guard let satisfies = IDEVersionComparator.satisfies(minimum: minimum, current: currentIDEVersion) else {
                throw IDEPluginRuntimeError.invalidManifest("minimumIDEVersion non valido: \(minimum)")
            }
            if !satisfies {
                throw IDEPluginRuntimeError.minimumIDEVersionNotSatisfied(
                    required: minimum,
                    current: currentIDEVersion
                )
            }
        }

        let allowedByCapabilities = toolsAllowed(for: manifest.capabilities)
        for tool in manifest.exposedTools where !allowedByCapabilities.contains(tool) {
            throw IDEPluginRuntimeError.invalidManifest(
                "tool '\(tool)' non consentito dalle capability dichiarate"
            )
        }
    }

    static func toolsAllowed(for capabilities: [PluginCapability]) -> Set<String> {
        capabilities.reduce(into: Set<String>()) { partial, capability in
            partial.formUnion(toolsByCapability[capability] ?? [])
        }
    }

    static func effectiveTools(for manifest: IDEPluginManifest) -> Set<String> {
        let capabilityTools = toolsAllowed(for: manifest.capabilities)
        if manifest.exposedTools.isEmpty {
            return capabilityTools
        }
        return Set(manifest.exposedTools).intersection(capabilityTools)
    }
}
