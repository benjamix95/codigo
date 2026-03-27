import CoderEngine
import Foundation

extension ProviderFactory {
    private static let legacyClaudeDefaultToolsLowercased: Set<String> = [
        "read",
        "edit",
        "bash",
        "write",
        "search",
    ]
    private static let claudeCoderideOverlapToolsLowercased: Set<String> = [
        "read",
        "edit",
        "write",
        "search",
        "glob",
        "grep",
        "websearch",
        "web_fetch",
        "webfetch",
        "notebookedit",
        "todo_write",
        "todowrite",
    ]

    static func codexEnvironmentOverride(
        _ environmentOverride: [String: String]?
    ) -> [String: String]? {
        var merged = environmentOverride ?? [:]
        let currentCodexHome = merged["CODEX_HOME"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if currentCodexHome.isEmpty {
            merged["CODEX_HOME"] = CLIProfileProvisioner.defaultCodexProfilePath()
        }
        let current = merged["RUST_LOG"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if current.isEmpty {
            merged["RUST_LOG"] = "error"
        }
        return merged.isEmpty ? nil : merged
    }

    static func sandbox(from config: ProviderFactoryConfig) -> CodexSandboxMode {
        if config.codexSessionFullAccess { return .dangerFullAccess }
        return CodexSandboxMode(rawValue: config.codexSandbox).map { $0 } ?? .workspaceWrite
    }

    static func askForApproval(from config: ProviderFactoryConfig) -> String {
        config.globalYolo
            ? "never" : CodexCLIProvider.normalizeAskForApproval(config.codexAskForApproval)
    }

    static func toolRuntimePolicy(from config: ProviderFactoryConfig) -> ToolRuntimePolicy {
        ToolRuntimePolicy(
            sandboxMode: sandbox(from: config).rawValue,
            askForApproval: askForApproval(from: config),
            enforceMCPEditOnly: config.mcpEditEnforcementEnabled
        )
    }

    static func toolRuntimeReadOnlyPolicy(from config: ProviderFactoryConfig) -> ToolRuntimePolicy {
        let base = toolRuntimePolicy(from: config)
        return ToolRuntimePolicy(
            sandboxMode: "workspace-read",
            askForApproval: base.askForApproval,
            timeoutMs: base.timeoutMs,
            maxToolCallsPerRound: base.maxToolCallsPerRound,
            maxRepeatedSameToolPerRound: base.maxRepeatedSameToolPerRound,
            maxBashOutputBytes: base.maxBashOutputBytes,
            maxReadBytesPerFile: base.maxReadBytesPerFile,
            allowDangerousShellPatterns: false,
            allowMutatingTools: false,
            enableMCP: base.enableMCP,
            enforceMCPEditOnly: base.enforceMCPEditOnly,
            mcpPerCallTimeoutMs: base.mcpPerCallTimeoutMs,
            mcpSessionIdleTTLSeconds: base.mcpSessionIdleTTLSeconds
        )
    }

    static func normalizedToolList(from raw: String) -> [String] {
        var seen = Set<String>()
        var tools: [String] = []
        for token in raw.components(separatedBy: ",") {
            let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            if seen.insert(trimmed).inserted {
                tools.append(trimmed)
            }
        }
        // Backward-compat migration: older builds defaulted Claude allowed tools
        // without `Task`, which prevents subagent tool invocation.
        // Add `Task` only for that exact legacy preset to avoid overriding explicit user choices.
        let normalizedSet = Set(tools.map { $0.lowercased() })
        if normalizedSet == legacyClaudeDefaultToolsLowercased,
           !normalizedSet.contains("task")
        {
            tools.append("Task")
        }
        return tools
    }

    static func claudeTools(
        from configuredTools: [String],
        toolPolicy: ToolRuntimePolicy?,
        preferCoderideMCP: Bool = false
    ) -> [String] {
        let effectiveTools = preferCoderideMCP
            ? configuredTools.filter { !claudeCoderideOverlapToolsLowercased.contains($0.lowercased()) }
            : configuredTools

        guard let policy = toolPolicy, !policy.allowMutatingTools else {
            return effectiveTools
        }

        let readOnlyToolSet: Set<String> = ["read", "search", "glob", "grep"]
        let filtered = effectiveTools.filter { readOnlyToolSet.contains($0.lowercased()) }

        return filtered.isEmpty ? ["Read"] : filtered
    }

    static func parseRoles(_ raw: String) -> Set<AgentRole> {
        var roles = Set<AgentRole>()
        for token in raw.components(separatedBy: ",") {
            let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
            if let role = AgentRole(rawValue: trimmed) {
                roles.insert(role)
            }
        }
        return roles
    }

    static func normalizedBackendId(_ backendId: String) -> String {
        backendId
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }
}
