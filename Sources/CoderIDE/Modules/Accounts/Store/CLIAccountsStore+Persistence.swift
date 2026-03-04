import Foundation
import CoderEngine

extension CLIAccountsStore {
    func save() {
        if let data = try? JSONEncoder().encode(accounts) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    func load() {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode([CLIAccount].self, from: data) else {
            return
        }
        accounts = decoded
    }

    func ensureGlobalAccountsIfNeeded() {
        var didChange = false
        for provider in CLIProviderKind.allCases {
            guard let globalPath = globalProfilePath(for: provider) else { continue }
            guard shouldAddGlobalAccount(provider: provider, profilePath: globalPath) else { continue }
            if hasAccount(provider: provider, profilePath: globalPath) {
                continue
            }

            let firstPriority = (accounts(for: provider).map(\.priority).min() ?? 0) - 1
            let account = CLIAccount(
                id: UUID(),
                provider: provider,
                label: "Global (OS)",
                isEnabled: true,
                priority: firstPriority,
                profilePath: globalPath,
                quota: .empty,
                health: .healthy,
                createdAt: .now,
                updatedAt: .now
            )
            accounts.append(account)
            didChange = true
        }
        if didChange {
            save()
        }
    }

    func shouldAddGlobalAccount(provider: CLIProviderKind, profilePath: String) -> Bool {
        guard CLIAccountAuthDetector.resolveExecutable(provider: provider, providerPath: nil) != nil else {
            return false
        }

        switch provider {
        case .codex:
            if CodexDetector.hasAuthFile() { return true }
            if let key = CodexDetector.shellEnvironment()["OPENAI_API_KEY"]?
                .trimmingCharacters(in: .whitespacesAndNewlines),
               !key.isEmpty {
                return true
            }
        case .claude:
            if ClaudeDetector.hasAuthFile() { return true }
            if let key = ClaudeDetector.shellEnvironment()["ANTHROPIC_API_KEY"]?
                .trimmingCharacters(in: .whitespacesAndNewlines),
               !key.isEmpty {
                return true
            }
        case .gemini:
            let env = GeminiDetector.shellEnvironment()
            let key = (env["GEMINI_API_KEY"] ?? env["GOOGLE_API_KEY"])?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !key.isEmpty {
                return true
            }
        }

        let probe = CLIAccount(
            id: UUID(),
            provider: provider,
            label: "probe",
            isEnabled: true,
            priority: 0,
            profilePath: profilePath,
            quota: .empty,
            health: .healthy,
            createdAt: .now,
            updatedAt: .now
        )
        if CLIAccountAuthDetector.identity(account: probe) != nil {
            return true
        }
        return CLIAccountAuthDetector.detect(account: probe, providerPath: nil).isLoggedIn
    }

    func hasAccount(provider: CLIProviderKind, profilePath: String) -> Bool {
        let normalized = normalizedPath(profilePath)
        return accounts.contains {
            $0.provider == provider && normalizedPath($0.profilePath) == normalized
        }
    }

    func globalProfilePath(for provider: CLIProviderKind) -> String? {
        switch provider {
        case .codex:
            let path = ProcessInfo.processInfo.environment["CODEX_HOME"] ?? "\(NSHomeDirectory())/.codex"
            return normalizedPath(path)
        case .claude:
            let claudeHome = ProcessInfo.processInfo.environment["CLAUDE_HOME"] ?? "\(NSHomeDirectory())/.claude"
            let normalizedClaudeHome = normalizedPath(claudeHome)
            let claudeDirName = URL(fileURLWithPath: normalizedClaudeHome).lastPathComponent
            if claudeDirName == ".claude" {
                return URL(fileURLWithPath: normalizedClaudeHome).deletingLastPathComponent().path
            }
            return normalizedClaudeHome
        case .gemini:
            let path = ProcessInfo.processInfo.environment["GEMINI_CONFIG_DIR"] ?? "\(NSHomeDirectory())/.gemini"
            return normalizedPath(path)
        }
    }

    func normalizedPath(_ rawPath: String) -> String {
        let expanded = (rawPath as NSString).expandingTildeInPath
        return URL(fileURLWithPath: expanded)
            .standardizedFileURL
            .resolvingSymlinksInPath()
            .path
    }

    func canonicalIdentityKey(for account: CLIAccount) -> String? {
        guard let identity = CLIAccountAuthDetector.identity(account: account) else {
            return nil
        }
        if let email = identity.email?.trimmingCharacters(in: .whitespacesAndNewlines),
           !email.isEmpty {
            return "email:\(email.lowercased())"
        }
        if let accountId = identity.accountId?.trimmingCharacters(in: .whitespacesAndNewlines),
           !accountId.isEmpty {
            return "account:\(accountId.lowercased())"
        }
        return nil
    }
}
