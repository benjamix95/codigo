import Foundation

enum CLIProfileProvisioner {
    static let mcpServerPathOverrideEnv = "CODERIDE_MCP_SERVER_PATH"

    static func baseProfilesDir() -> URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return appSupport
            .appendingPathComponent("Codigo", isDirectory: true)
            .appendingPathComponent("CLIProfiles", isDirectory: true)
    }

    static func ensureProfile(provider: CLIProviderKind, accountId: UUID) -> String {
        let providerDir = baseProfilesDir().appendingPathComponent(provider.rawValue, isDirectory: true)
        let profile = providerDir.appendingPathComponent(accountId.uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: profile, withIntermediateDirectories: true)

        if provider == .codex {
            ensureCodexProfileFiles(at: profile, overwrite: false)
        } else if provider == .claude {
            ensureClaudeProfileFiles(at: profile)
        }

        return profile.path
    }

    static func environmentOverrides(provider: CLIProviderKind, profilePath: String, secret: String?) -> [String: String] {
        var env: [String: String] = [:]
        switch provider {
        case .codex:
            ensureCodexProfileFiles(at: URL(fileURLWithPath: profilePath, isDirectory: true), overwrite: false)
            env["CODEX_HOME"] = profilePath
            if let secret, !secret.isEmpty { env["OPENAI_API_KEY"] = secret }
        case .claude:
            let profileURL = URL(fileURLWithPath: profilePath, isDirectory: true)
            ensureClaudeProfileFiles(at: profileURL)
            env["HOME"] = profilePath
            env["CLAUDE_HOME"] = profileURL
                .appendingPathComponent(".claude", isDirectory: true)
                .path
            if let secret, !secret.isEmpty { env["ANTHROPIC_API_KEY"] = secret }
        case .gemini:
            env["GEMINI_CONFIG_DIR"] = profilePath
            if let secret, !secret.isEmpty { env["GOOGLE_API_KEY"] = secret }
            ensureGeminiMCPConfig(at: URL(fileURLWithPath: profilePath, isDirectory: true))
        }
        return env
    }

    /// Re-seed config files for an existing Codex profile (e.g. after MCP server binary is rebuilt).
    /// Unlike initial seeding, this overwrites existing files to ensure they're up-to-date.
    static func reseedCodexProfile(at profileURL: URL) {
        ensureCodexProfileFiles(at: profileURL, overwrite: true)
    }

    /// Repairs a Codex profile without overwriting user customizations.
    static func selfHealCodexProfile(at profileURL: URL) {
        ensureCodexProfileFiles(at: profileURL, overwrite: false)
    }
}
