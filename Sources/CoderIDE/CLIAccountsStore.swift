import Foundation

@MainActor
final class CLIAccountsStore: ObservableObject {
    static let shared = CLIAccountsStore()
    @Published private(set) var accounts: [CLIAccount] = []
    @Published var multiAccountEnabled: Bool {
        didSet { UserDefaults.standard.set(multiAccountEnabled, forKey: multiEnabledKey) }
    }

    private let key = "CoderIDE.cliAccounts"
    private let multiEnabledKey = "multi_cli_account_enabled"
    private let secrets = CLIAccountSecretsStore()

    init() {
        self.multiAccountEnabled = UserDefaults.standard.bool(forKey: multiEnabledKey)
        load()
    }

    func accounts(for provider: CLIProviderKind) -> [CLIAccount] {
        accounts
            .filter { $0.provider == provider }
            .sorted { lhs, rhs in
                if lhs.priority != rhs.priority { return lhs.priority < rhs.priority }
                return lhs.createdAt < rhs.createdAt
            }
    }

    func addAccount(provider: CLIProviderKind, label: String, apiKey: String?, quota: CLIAccountQuotaPolicy = .empty) {
        let id = UUID()
        let profile = CLIProfileProvisioner.ensureProfile(provider: provider, accountId: id)
        let nextPriority = (accounts(for: provider).map(\.priority).max() ?? -1) + 1
        let account = CLIAccount(
            id: id,
            provider: provider,
            label: label.isEmpty ? "\(provider.displayName) \(nextPriority + 1)" : label,
            isEnabled: true,
            priority: nextPriority,
            profilePath: profile,
            quota: quota,
            health: .healthy,
            createdAt: .now,
            updatedAt: .now
        )
        accounts.append(account)
        if let apiKey, !apiKey.isEmpty {
            secrets.setSecret(apiKey, for: id)
        }
        save()
    }

    func update(_ account: CLIAccount) {
        guard let idx = accounts.firstIndex(where: { $0.id == account.id }) else { return }
        var updated = account
        updated.updatedAt = .now
        accounts[idx] = updated
        save()
    }

    func updateSecret(accountId: UUID, secret: String) {
        secrets.setSecret(secret, for: accountId)
    }

    func updateAuthStatus(accountId: UUID, status: CLIAccountAuthStatus) {
        guard let idx = accounts.firstIndex(where: { $0.id == accountId }) else { return }
        accounts[idx].lastAuthCheckAt = .now
        switch status {
        case .loggedIn(let method):
            accounts[idx].lastAuthMethod = method
            accounts[idx].lastAuthError = nil
        case .error(let message):
            accounts[idx].lastAuthError = message
        default:
            accounts[idx].lastAuthError = nil
        }
        accounts[idx].updatedAt = .now
        save()
    }

    func secret(for accountId: UUID) -> String? {
        secrets.secret(for: accountId)
    }

    func delete(accountId: UUID) {
        accounts.removeAll { $0.id == accountId }
        secrets.deleteSecret(for: accountId)
        save()
    }

    func resetHealth(provider: CLIProviderKind) {
        for idx in accounts.indices where accounts[idx].provider == provider {
            accounts[idx].health = .healthy
            accounts[idx].updatedAt = .now
        }
        save()
    }

    private func save() {
        if let data = try? JSONEncoder().encode(accounts) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode([CLIAccount].self, from: data) else {
            return
        }
        accounts = decoded
    }
}
