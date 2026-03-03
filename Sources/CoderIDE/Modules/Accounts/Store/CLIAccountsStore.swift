import Foundation
import CoderEngine

@MainActor
final class CLIAccountsStore: ObservableObject {
    static let shared = CLIAccountsStore()
    @Published var accounts: [CLIAccount] = []
    @Published var multiAccountEnabled: Bool {
        didSet { UserDefaults.standard.set(multiAccountEnabled, forKey: multiEnabledKey) }
    }

    let key = "CoderIDE.cliAccounts"
    private let multiEnabledKey = "multi_cli_account_enabled"
    private let secrets = CLIAccountSecretsStore()

    init() {
        self.multiAccountEnabled = UserDefaults.standard.bool(forKey: multiEnabledKey)
        load()
        bootstrapAccountsIfNeeded()
    }

    /// Ensures account bootstrap invariants.
    func bootstrapAccountsIfNeeded() {
        ensureGlobalAccountsIfNeeded()
        ensureDefaultAccountsIfNeeded()
        _ = deduplicateAccounts(provider: .claude, preferredActiveAccountId: nil)
    }

    /// Ensure each CLI provider has at least one profile/account entry.
    /// This keeps Sidebar + Settings consistent across Codex/Claude/Gemini.
    func ensureDefaultAccountsIfNeeded() {
        for provider in CLIProviderKind.allCases {
            if accounts(for: provider).isEmpty {
                let label = "\(provider.displayName) 1"
                addAccount(provider: provider, label: label, apiKey: nil)
            }
        }
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

    /// Quick-add an account with auto-generated label. Returns the created account.
    @discardableResult
    func addAccountQuick(provider: CLIProviderKind) -> CLIAccount {
        let nextNum = accounts(for: provider).count + 1
        let label = "Account \(nextNum)"
        addAccount(provider: provider, label: label, apiKey: nil)
        // addAccount appends to `accounts` immediately above, so last is guaranteed non-nil.
        guard let account = accounts.last else {
            fatalError("addAccount did not append — accounts array is empty after addAccount call")
        }
        return account
    }

    /// Finalize a just-authenticated account and returns the primary account id.
    @discardableResult
    func finalizePostLogin(accountId: UUID, preferredActiveAccountId: UUID?) -> UUID? {
        guard let account = accounts.first(where: { $0.id == accountId }) else { return nil }
        let mergedInto = deduplicateAccounts(
            provider: account.provider,
            preferredActiveAccountId: preferredActiveAccountId ?? accountId
        )
        return mergedInto[accountId] ?? accountId
    }

    /// Finds duplicate account ids for a provider without mutating state.
    func findDuplicates(provider: CLIProviderKind) -> [UUID] {
        let providerAccounts = accounts(for: provider)
        var grouped: [String: [CLIAccount]] = [:]
        for account in providerAccounts {
            guard let key = canonicalIdentityKey(for: account) else { continue }
            grouped[key, default: []].append(account)
        }
        var duplicates: [UUID] = []
        for group in grouped.values where group.count > 1 {
            let sorted = group.sorted { lhs, rhs in
                if lhs.createdAt != rhs.createdAt { return lhs.createdAt < rhs.createdAt }
                return lhs.id.uuidString < rhs.id.uuidString
            }
            duplicates.append(contentsOf: sorted.dropFirst().map(\.id))
        }
        return duplicates
    }

    /// Auto-merge safe duplicates:
    /// keep one primary account enabled and mark duplicates disabled.
    /// Returns map: duplicateAccountId -> primaryAccountId.
    @discardableResult
    func deduplicateAccounts(
        provider: CLIProviderKind,
        preferredActiveAccountId: UUID?
    ) -> [UUID: UUID] {
        let providerAccounts = accounts(for: provider)
        var grouped: [String: [CLIAccount]] = [:]
        for account in providerAccounts {
            guard let key = canonicalIdentityKey(for: account) else { continue }
            grouped[key, default: []].append(account)
        }

        var mergeMap: [UUID: UUID] = [:]
        var changed = false
        for group in grouped.values where group.count > 1 {
            let sorted = group.sorted { lhs, rhs in
                if lhs.createdAt != rhs.createdAt { return lhs.createdAt < rhs.createdAt }
                return lhs.id.uuidString < rhs.id.uuidString
            }
            let primaryId: UUID
            if let preferredActiveAccountId,
               sorted.contains(where: { $0.id == preferredActiveAccountId }) {
                primaryId = preferredActiveAccountId
            } else {
                primaryId = sorted[0].id
            }
            for account in sorted where account.id != primaryId {
                guard let idx = accounts.firstIndex(where: { $0.id == account.id }) else { continue }
                var updated = accounts[idx]
                updated.isEnabled = false
                if !updated.label.lowercased().contains("(duplicate)") {
                    updated.label = "\(updated.label) (duplicate)"
                }
                updated.updatedAt = .now
                accounts[idx] = updated
                mergeMap[updated.id] = primaryId
                changed = true
            }
        }

        if changed {
            save()
        }
        return mergeMap
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

    func isManagedProfilePath(_ path: String) -> Bool {
        let managedRoot = normalizedPath(CLIProfileProvisioner.baseProfilesDir().path)
        let candidate = normalizedPath(path)
        return candidate == managedRoot || candidate.hasPrefix(managedRoot + "/")
    }
}
