import Foundation
import CoderEngine
import Combine

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
    private var cancellables: Set<AnyCancellable> = []
    private var bootstrapWorkItem: DispatchWorkItem?
    private var bootstrapGeneration = 0

    init(accountsStore: CLIAccountsStore, ledger: CLIAccountUsageLedgerStore) {
        self.accountsStore = accountsStore
        self.ledger = ledger
        accountsStore.$accounts
            .sink { [weak self] _ in
                self?.scheduleBootstrapActiveSelectionsIfNeeded()
            }
            .store(in: &cancellables)
        scheduleBootstrapActiveSelectionsIfNeeded()
    }

    deinit {
        bootstrapWorkItem?.cancel()
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

    func selectedOrNextAvailableAccount(for provider: CLIProviderKind) -> CLIAccount? {
        let candidates = availableAccounts(for: provider)
        guard !candidates.isEmpty else { return nil }

        if let selectedId = currentActiveAccountByProvider[provider],
           let selected = candidates.first(where: { $0.id == selectedId }) {
            return selected
        }
        return selectAccount(for: provider)
    }

    func currentAvailability(provider: CLIProviderKind) -> CLIAvailabilityState {
        if availableAccounts(for: provider).isEmpty {
            return .allExhausted(reason: "No available account")
        }
        return .available
    }

    func activeAccount(for provider: CLIProviderKind) -> CLIAccount? {
        guard let activeId = currentActiveAccountByProvider[provider] else { return nil }
        return accountsStore.accounts(for: provider).first(where: { $0.id == activeId })
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

    func bootstrapActiveSelectionsIfNeeded() {
        scheduleBootstrapActiveSelectionsIfNeeded()
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

    private func scheduleBootstrapActiveSelectionsIfNeeded() {
        bootstrapGeneration += 1
        let generation = bootstrapGeneration
        let currentSelections = currentActiveAccountByProvider
        let accountsByProvider = Dictionary(
            uniqueKeysWithValues: CLIProviderKind.allCases.map { provider in
                (provider, accountsStore.accounts(for: provider))
            }
        )
        let executablePaths = Dictionary(
            uniqueKeysWithValues: CLIProviderKind.allCases.map { provider in
                (provider, providerExecutablePath(for: provider))
            }
        )

        bootstrapWorkItem?.cancel()
        let workItem = DispatchWorkItem { [accountsByProvider, currentSelections, executablePaths] in
            let selections = Self.resolveBootstrapSelections(
                accountsByProvider: accountsByProvider,
                currentSelections: currentSelections,
                executablePaths: executablePaths
            )
            Task { @MainActor [weak self] in
                guard let self, self.bootstrapGeneration == generation else { return }
                self.currentActiveAccountByProvider = selections
            }
        }
        bootstrapWorkItem = workItem
        DispatchQueue.global(qos: .utility).async(execute: workItem)
    }

    private static func resolveBootstrapSelections(
        accountsByProvider: [CLIProviderKind: [CLIAccount]],
        currentSelections: [CLIProviderKind: UUID],
        executablePaths: [CLIProviderKind: String?]
    ) -> [CLIProviderKind: UUID] {
        var selections: [CLIProviderKind: UUID] = [:]

        for provider in CLIProviderKind.allCases {
            let enabled = (accountsByProvider[provider] ?? []).filter(\.isEnabled)
            guard !enabled.isEmpty else { continue }

            if let selectedId = currentSelections[provider],
               enabled.contains(where: { $0.id == selectedId }) {
                selections[provider] = selectedId
                continue
            }

            let path: String? = executablePaths[provider] ?? nil
            if let connected = enabled.first(where: {
                CLIAccountAuthDetector.detect(account: $0, providerPath: path).isLoggedIn
            }) {
                selections[provider] = connected.id
            } else {
                selections[provider] = enabled[0].id
            }
        }

        return selections
    }
}
