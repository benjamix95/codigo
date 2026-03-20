import Foundation

extension ChatPanelView {
    internal func cliAccountSnapshots(
        for kind: CLIProviderKind
    ) -> [MainChatCLIAccountSnapshotBridge] {
        let cfg = providerFactoryConfig()
        return cliAccountsStore.accounts(for: kind).map { account in
            let executable = switch kind {
            case .codex:
                CLIAccountAuthDetector.resolveExecutable(
                    provider: .codex,
                    providerPath: cfg.codexPath
                )
            case .claude:
                CLIAccountAuthDetector.resolveExecutable(
                    provider: .claude,
                    providerPath: cfg.claudePath
                )
            case .gemini:
                CLIAccountAuthDetector.resolveExecutable(
                    provider: .gemini,
                    providerPath: cfg.geminiCliPath
                )
            }
            let auth = CLIAccountAuthDetector.detect(
                account: account,
                providerPath: executable
            )
            let secret = cliAccountsStore.secret(for: account.id)
            let env = CLIProfileProvisioner.environmentOverrides(
                provider: kind,
                profilePath: account.profilePath,
                secret: secret
            )
            return MainChatCLIAccountSnapshotBridge(
                id: account.id.uuidString,
                provider: account.provider.rawValue,
                label: account.label,
                isEnabled: account.isEnabled,
                isAuthenticated: auth.isLoggedIn,
                priority: account.priority,
                profilePath: account.profilePath,
                envOverrides: env,
                quota: MainChatCLIQuotaSnapshotBridge(account.quota),
                health: MainChatCLIHealthSnapshotBridge(account.health),
                createdAt: account.createdAt,
                updatedAt: account.updatedAt
            )
        }
    }
}
