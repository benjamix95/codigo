import CoderEngine
import Foundation

extension ProviderFactory {
    static func codexEnvironmentOverride(
        _ environmentOverride: [String: String]?
    ) -> [String: String]? {
        var merged = environmentOverride ?? [:]
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
        return tools
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
