import Foundation

enum CLIProfileProvisioner {
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
        return profile.path
    }

    static func environmentOverrides(provider: CLIProviderKind, profilePath: String, secret: String?) -> [String: String] {
        var env: [String: String] = [:]
        switch provider {
        case .codex:
            env["CODEX_HOME"] = profilePath
            if let secret, !secret.isEmpty { env["OPENAI_API_KEY"] = secret }
        case .claude:
            env["CLAUDE_HOME"] = profilePath
            if let secret, !secret.isEmpty { env["ANTHROPIC_API_KEY"] = secret }
        case .gemini:
            env["GEMINI_CONFIG_DIR"] = profilePath
            if let secret, !secret.isEmpty { env["GOOGLE_API_KEY"] = secret }
        }
        return env
    }
}
