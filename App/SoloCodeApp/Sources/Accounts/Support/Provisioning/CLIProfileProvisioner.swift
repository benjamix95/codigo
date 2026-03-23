import Foundation

enum CLIProfileProvisioner {
    static let mcpServerPathOverrideEnv = "CODERIDE_MCP_SERVER_PATH"

    static func baseProfilesDir() -> URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return appSupport
            .appendingPathComponent("Solo Code", isDirectory: true)
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

    static func defaultCodexProfileURL(baseProfilesRoot: URL? = nil) -> URL {
        let root = (baseProfilesRoot ?? baseProfilesDir())
            .appendingPathComponent(CLIProviderKind.codex.rawValue, isDirectory: true)
        return root.appendingPathComponent("_default", isDirectory: true)
    }

    static func defaultCodexProfilePath(baseProfilesRoot: URL? = nil) -> String {
        let profile = defaultCodexProfileURL(baseProfilesRoot: baseProfilesRoot)
        try? FileManager.default.createDirectory(at: profile, withIntermediateDirectories: true)
        ensureCodexProfileFiles(at: profile, overwrite: false)
        syncDefaultCodexAuthIfNeeded(baseProfilesRoot: baseProfilesRoot)
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

    static func syncDefaultCodexAuthIfNeeded(
        baseProfilesRoot: URL? = nil,
        sourceAuthPath: String? = nil
    ) {
        let profileURL = defaultCodexProfileURL(baseProfilesRoot: baseProfilesRoot)
        let targetAuthURL = profileURL.appendingPathComponent("auth.json")
        let sourceURL = URL(fileURLWithPath: sourceAuthPath ?? "\(NSHomeDirectory())/.codex/auth.json")

        guard FileManager.default.fileExists(atPath: sourceURL.path),
              codexAuthFileLooksValid(at: sourceURL) else {
            return
        }
        if sourceURL.standardizedFileURL == targetAuthURL.standardizedFileURL {
            return
        }

        let shouldCopy: Bool
        if !FileManager.default.fileExists(atPath: targetAuthURL.path) {
            shouldCopy = true
        } else if !codexAuthFileLooksValid(at: targetAuthURL) {
            shouldCopy = true
        } else {
            let sourceDate = (try? sourceURL.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
            let targetDate = (try? targetAuthURL.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
            shouldCopy = (sourceDate ?? .distantPast) > (targetDate ?? .distantPast)
        }

        guard shouldCopy else { return }
        try? FileManager.default.createDirectory(at: profileURL, withIntermediateDirectories: true)
        try? FileManager.default.removeItem(at: targetAuthURL)
        try? FileManager.default.copyItem(at: sourceURL, to: targetAuthURL)
    }

    private static func codexAuthFileLooksValid(at url: URL) -> Bool {
        guard let data = try? Data(contentsOf: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return false
        }
        if let apiKey = (json["OPENAI_API_KEY"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
           !apiKey.isEmpty {
            return true
        }
        if let token = (json["token"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
           !token.isEmpty {
            return true
        }
        if let accessToken = (json["access_token"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
           !accessToken.isEmpty {
            return true
        }
        if let tokens = json["tokens"] as? [String: Any] {
            let nestedAccess = (tokens["access_token"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let nestedId = (tokens["id_token"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let nestedRefresh = (tokens["refresh_token"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return !nestedAccess.isEmpty || !nestedId.isEmpty || !nestedRefresh.isEmpty
        }
        return false
    }
}
