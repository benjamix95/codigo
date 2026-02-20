import Foundation
import CoderEngine

struct CLIClassifiedFailure {
    let isQuotaExhaustion: Bool
    let isRateLimited: Bool
    let retryAfterSeconds: Int?
    let normalizedCode: String
}

@MainActor
final class CLIAccountRouter: ObservableObject {
    static let shared = CLIAccountRouter(
        accountsStore: .shared,
        ledger: .shared
    )

    @Published private(set) var roundRobinIndex: [CLIProviderKind: Int] = [:]
    @Published private(set) var currentActiveAccountByProvider: [CLIProviderKind: UUID] = [:]
    @Published private(set) var lastFailoverReasonByProvider: [CLIProviderKind: String] = [:]
    @Published private(set) var lastSwitchAtByProvider: [CLIProviderKind: Date] = [:]

    private let accountsStore: CLIAccountsStore
    private let ledger: CLIAccountUsageLedgerStore

    init(accountsStore: CLIAccountsStore, ledger: CLIAccountUsageLedgerStore) {
        self.accountsStore = accountsStore
        self.ledger = ledger
    }

    func selectAccount(for provider: CLIProviderKind) -> CLIAccount? {
        let candidates = availableAccounts(for: provider)
        guard !candidates.isEmpty else { return nil }
        let idx = (roundRobinIndex[provider] ?? 0) % candidates.count
        roundRobinIndex[provider] = (idx + 1) % max(candidates.count, 1)
        let selected = candidates[idx]
        markAccountSelected(accountId: selected.id, provider: provider, reason: nil)
        return selected
    }

    func nextAvailableAccount(after accountId: UUID, provider: CLIProviderKind) -> CLIAccount? {
        let candidates = availableAccounts(for: provider)
        guard !candidates.isEmpty else { return nil }
        guard let currentIndex = candidates.firstIndex(where: { $0.id == accountId }) else {
            let selected = candidates.first
            if let selected {
                markAccountSelected(accountId: selected.id, provider: provider, reason: lastFailoverReasonByProvider[provider])
            }
            return selected
        }
        let nextIndex = (currentIndex + 1) % candidates.count
        let selected = candidates[nextIndex]
        markAccountSelected(accountId: selected.id, provider: provider, reason: lastFailoverReasonByProvider[provider])
        return selected
    }

    func currentAvailability(provider: CLIProviderKind) -> CLIAvailabilityState {
        availableAccounts(for: provider).isEmpty
        ? .allExhausted(reason: "Nessun account disponibile")
        : .available
    }

    func markUsage(accountId: UUID, provider: CLIProviderKind, inputTokens: Int, outputTokens: Int, estimatedCost: Double) {
        ledger.append(accountId: accountId, provider: provider, inputTokens: inputTokens, outputTokens: outputTokens, estimatedCostUSD: estimatedCost)

        guard var account = accountsStore.accounts.first(where: { $0.id == accountId && $0.provider == provider }) else { return }
        account.health.consecutiveFailures = 0
        account.health.lastErrorCode = nil
        account.health.cooldownUntil = nil
        if exceedsPolicy(account: account) {
            account.health.isExhaustedLocally = true
            account.health.lastErrorCode = "local_limit_reached"
        }
        accountsStore.update(account)
    }

    func markProviderError(accountId: UUID, provider: CLIProviderKind, classifiedError: CLIClassifiedFailure) {
        guard var account = accountsStore.accounts.first(where: { $0.id == accountId && $0.provider == provider }) else { return }
        account.health.consecutiveFailures += 1
        account.health.lastErrorCode = classifiedError.normalizedCode

        if classifiedError.isQuotaExhaustion {
            account.health.isExhaustedLocally = true
        }
        if classifiedError.isRateLimited {
            let seconds = max(30, classifiedError.retryAfterSeconds ?? 120)
            account.health.cooldownUntil = Date().addingTimeInterval(TimeInterval(seconds))
        }
        lastFailoverReasonByProvider[provider] = classifiedError.normalizedCode
        accountsStore.update(account)
    }

    func markAccountSelected(accountId: UUID, provider: CLIProviderKind, reason: String?) {
        currentActiveAccountByProvider[provider] = accountId
        lastSwitchAtByProvider[provider] = Date()
        if let reason, !reason.isEmpty {
            lastFailoverReasonByProvider[provider] = reason
        }
    }

    private func availableAccounts(for provider: CLIProviderKind) -> [CLIAccount] {
        accountsStore.accounts(for: provider)
            .sorted { lhs, rhs in
                if lhs.priority != rhs.priority { return lhs.priority < rhs.priority }
                return lhs.createdAt < rhs.createdAt
            }
            .filter { account in
            guard account.isEnabled else { return false }
            if account.health.isExhaustedLocally { return false }
            if let until = account.health.cooldownUntil, until > Date() { return false }
            let authStatus = CLIAccountAuthDetector.detect(
                account: account,
                providerPath: providerExecutablePath(for: provider)
            )
            guard authStatus.isLoggedIn else { return false }
            return !exceedsPolicy(account: account)
        }
    }

    private func providerExecutablePath(for provider: CLIProviderKind) -> String? {
        let defaults = UserDefaults.standard
        switch provider {
        case .codex:
            let custom = defaults.string(forKey: "codex_path")
            return CLIAccountAuthDetector.resolveExecutable(provider: .codex, providerPath: custom)
        case .claude:
            let custom = defaults.string(forKey: "claude_path")
            return CLIAccountAuthDetector.resolveExecutable(provider: .claude, providerPath: custom)
        case .gemini:
            let custom = defaults.string(forKey: "gemini_cli_path")
            return CLIAccountAuthDetector.resolveExecutable(provider: .gemini, providerPath: custom)
        }
    }

    private func exceedsPolicy(account: CLIAccount) -> Bool {
        let daily = ledger.totals(accountId: account.id, period: .day)
        let weekly = ledger.totals(accountId: account.id, period: .weekOfYear)
        let monthly = ledger.totals(accountId: account.id, period: .month)

        if let limit = account.quota.dailyLimitUSD, daily.cost >= limit { return true }
        if let limit = account.quota.weeklyLimitUSD, weekly.cost >= limit { return true }
        if let limit = account.quota.monthlyLimitUSD, monthly.cost >= limit { return true }

        if let limit = account.quota.dailyTokenLimit, daily.tokens >= limit { return true }
        if let limit = account.quota.weeklyTokenLimit, weekly.tokens >= limit { return true }
        if let limit = account.quota.monthlyTokenLimit, monthly.tokens >= limit { return true }
        return false
    }
}
