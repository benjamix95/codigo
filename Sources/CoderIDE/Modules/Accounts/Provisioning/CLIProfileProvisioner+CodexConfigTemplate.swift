import Foundation

extension CLIProfileProvisioner {
    static let codexProfileConfigHeader = "# Modello GPT-5.4 con contesto 1M token (OpenAI)"

    static let codexProfileRootAssignments: [(key: String, value: String)] = [
        ("model", "\"gpt-5.4\""),
        ("model_provider", "\"openai\""),
        ("model_context_window", "1000000"),
        ("model_auto_compact_token_limit", "900000"),
        ("model_reasoning_effort", "\"low\""),
        ("personality", "\"pragmatic\""),
        ("sandbox_mode", "\"danger-full-access\""),
        ("fast_mode", "true"),
    ]

    static func preferredCodexProfileMCPBinaryPath() -> String {
        mcpServerBinaryPath() ?? bundledMCPServerSiblingPath() ?? "coderide-mcp-server"
    }

    static func codexProfileConfigContent(binaryPath: String) -> String {
        codexProfileConfigLines(binaryPath: binaryPath).joined(separator: "\n") + "\n"
    }

    static func codexProfileConfigLines(binaryPath: String) -> [String] {
        var lines = [codexProfileConfigHeader]
        lines.append(contentsOf: codexProfileRootAssignments.map { "\($0.key) = \($0.value)" })
        lines.append("")
        lines.append("[sandbox_workspace_write]")
        lines.append("network_access = true")
        lines.append("")
        lines.append(contentsOf: coderideMCPSectionLines(binaryPath: binaryPath, includeEnabled: true))
        lines.append("")
        lines.append(contentsOf: codexExperimentalFeaturesLines())
        return lines
    }

    static func isLegacyManagedCodexProfileConfig(_ content: String) -> Bool {
        content
            .components(separatedBy: .newlines)
            .contains { $0.trimmingCharacters(in: .whitespaces).hasPrefix("# CoderIDE Codex Profile") }
    }
}
