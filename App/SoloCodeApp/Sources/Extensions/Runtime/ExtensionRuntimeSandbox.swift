import Foundation
import CoderEngine

enum ExtensionRuntimeError: Error, LocalizedError, Equatable {
    case runtimeDisabled
    case invalidManifest(String)
    case pluginAlreadyLoaded(String)
    case pluginNotLoaded(String)
    case toolNotExposed(pluginId: String, tool: String)
    case capabilityDenied(ExtensionCapability)
    case minimumIDEVersionNotSatisfied(required: String, current: String)

    var errorDescription: String? {
        switch self {
        case .runtimeDisabled:
            return "Extension runtime disabilitato da feature flag."
        case .invalidManifest(let reason):
            return "Manifest non valido: \(reason)"
        case .pluginAlreadyLoaded(let id):
            return "Plugin già caricato: \(id)"
        case .pluginNotLoaded(let id):
            return "Plugin non caricato: \(id)"
        case .toolNotExposed(let pluginId, let tool):
            return "Tool non esposto dal plugin \(pluginId): \(tool)"
        case .capabilityDenied(let capability):
            return "Capability negata dal sandbox: \(capability.rawValue)"
        case .minimumIDEVersionNotSatisfied(let required, let current):
            return "Plugin richiede IDE >= \(required), versione corrente: \(current)"
        }
    }
}

struct ExtensionRuntimeSandbox: Sendable {
    let allowedCapabilities: Set<ExtensionCapability>
    private static let toolsByCapability: [ExtensionCapability: Set<String>] = [
        .readWorkspace: [
            "read",
            "read_range",
            "list_dir",
            "find_files",
            "glob",
            "grep",
            "semantic_search",
            "codebase_search",
            "find_symbol",
            "find_references",
            "file_outline",
        ],
        .readOnlyTools: [
            "read",
            "read_range",
            "list_dir",
            "find_files",
            "glob",
            "grep",
            "semantic_search",
            "codebase_search",
            "find_symbol",
            "find_references",
            "file_outline",
            "web_search",
            "web_fetch",
            "mcp_call",
            "mcp_batch",
            "mcp_list_resources",
            "mcp_read_resource",
            "mcp_health",
            "mcp_reconnect",
            "mcp_restart_server",
            "git_diff",
            "git_status",
            "git_show",
            "git_log_search",
            "debug_context",
            "debug_log",
            "debug_query",
            "debug_session",
            "debug_hypothesize",
            "debug_trace_analyze",
            "debug_snapshot",
            "debug_timeline",
            "debug_test_check",
            "debug_set_phase",
            "debug_request_user",
            "debug_resolve",
        ],
        .writeWorkspace: [
            "edit",
            "str_replace",
            "multi_edit",
            "parallel_apply",
            "apply_diff",
            "write",
            "create_file",
            "write_json",
            "debug_mark",
            "debug_instrument",
            "debug_clean",
        ],
        .executeCommands: [
            "bash",
            "run_tests",
            "build_project",
            "diagnostics",
            "read_lints",
            "subagent_explorer",
            "subagent_coder",
            "subagent_reviewer",
            "subagent_bugHunter",
            "subagent_testWriter",
            "subagent_debugger",
            "subagent_docWriter",
            "subagent_securityAuditor",
        ],
        .networkAccess: [
            "web_search",
            "web_fetch",
        ],
    ]

    func validate(
        manifest: ExtensionManifest,
        currentIDEVersion: String
    ) throws -> Set<ExtensionCapability> {
        guard !manifest.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ExtensionRuntimeError.invalidManifest("id mancante")
        }
        guard !manifest.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ExtensionRuntimeError.invalidManifest("name mancante")
        }
        let granted = Set(manifest.capabilities)
        for capability in granted where !allowedCapabilities.contains(capability) {
            throw ExtensionRuntimeError.capabilityDenied(capability)
        }

        if let minimum = manifest.minimumIDEVersion?.trimmingCharacters(in: .whitespacesAndNewlines),
           !minimum.isEmpty {
            guard let satisfies = IDEVersionComparator.satisfies(minimum: minimum, current: currentIDEVersion) else {
                throw ExtensionRuntimeError.invalidManifest("minimumIDEVersion non valido: \(minimum)")
            }
            if !satisfies {
                throw ExtensionRuntimeError.minimumIDEVersionNotSatisfied(
                    required: minimum,
                    current: currentIDEVersion
                )
            }
        }
        return granted
    }

    func effectiveTools(
        for manifest: ExtensionManifest,
        grantedCapabilities: Set<ExtensionCapability>
    ) -> Set<String> {
        if !manifest.exposedTools.isEmpty {
            return Set(manifest.exposedTools)
        }
        return Self.toolsAllowed(for: grantedCapabilities)
    }

    private static func toolsAllowed(for capabilities: Set<ExtensionCapability>) -> Set<String> {
        capabilities.reduce(into: Set<String>()) { partialResult, capability in
            partialResult.formUnion(toolsByCapability[capability] ?? [])
        }
    }
}
