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
        handleSelectionAction("select_account", provider: provider)
    }

    func nextAvailableAccount(after accountId: UUID, provider: CLIProviderKind) -> CLIAccount? {
        handleSelectionAction("next_available_account_after", provider: provider, accountId: accountId)
    }

    func selectedOrNextAvailableAccount(for provider: CLIProviderKind) -> CLIAccount? {
        handleSelectionAction("selected_or_next_available", provider: provider)
    }

    func currentAvailability(provider: CLIProviderKind) -> CLIAvailabilityState {
        guard let response = handleRoutingAction(action: "current_availability", provider: provider) else {
            return .allExhausted(reason: "Rust account router unavailable")
        }
        apply(response.state)
        if response.availabilityStatus == "available" {
            return .available
        }
        return .allExhausted(reason: response.availabilityReason ?? "No available account")
    }

    func activeAccount(for provider: CLIProviderKind) -> CLIAccount? {
        guard let activeId = currentActiveAccountByProvider[provider] else { return nil }
        return accountsStore.accounts(for: provider).first(where: { $0.id == activeId })
    }

    func markUsage(accountId: UUID, provider: CLIProviderKind, inputTokens: Int, outputTokens: Int, estimatedCost: Double) {
        ledger.append(accountId: accountId, provider: provider, inputTokens: inputTokens, outputTokens: outputTokens, estimatedCostUSD: estimatedCost)
        guard let response = handleRoutingAction(action: "mark_usage", provider: provider, accountId: accountId) else { return }
        apply(response.state)
        applyUpdatedAccount(response.updatedAccount)
    }

    func markProviderError(accountId: UUID, provider: CLIProviderKind, classifiedError: CLIClassifiedFailure) {
        guard let response = handleRoutingAction(
            action: "mark_provider_error",
            provider: provider,
            accountId: accountId,
            failure: classifiedError
        ) else { return }
        apply(response.state)
        applyUpdatedAccount(response.updatedAccount)
    }

    func markAccountSelected(accountId: UUID, provider: CLIProviderKind, reason: String?) {
        guard let response = handleRoutingAction(
            action: "mark_account_selected",
            provider: provider,
            accountId: accountId,
            failure: reason.map { CLIClassifiedFailure(isQuotaExhaustion: false, isRateLimited: false, retryAfterSeconds: nil, normalizedCode: $0) }
        ) else { return }
        apply(response.state)
    }

    func bootstrapActiveSelectionsIfNeeded() {
        scheduleBootstrapActiveSelectionsIfNeeded()
    }

    private func handleSelectionAction(
        _ action: String,
        provider: CLIProviderKind,
        accountId: UUID? = nil
    ) -> CLIAccount? {
        guard let response = handleRoutingAction(action: action, provider: provider, accountId: accountId) else {
            return nil
        }
        apply(response.state)
        let selectedId = response.selectedAccountId.flatMap(UUID.init(uuidString:))
        return selectedId.flatMap { id in
            accountsStore.accounts(for: provider).first(where: { $0.id == id })
        }
    }

    private func handleRoutingAction(
        action: String,
        provider: CLIProviderKind? = nil,
        accountId: UUID? = nil,
        failure: CLIClassifiedFailure? = nil
    ) -> CLIAccountRoutingResponseBridge? {
        let accounts = accountsStore.accounts
        let executablePaths = Dictionary(
            uniqueKeysWithValues: CLIProviderKind.allCases.map { kind in
                (kind, CLIAccountRouterRustBridge.providerExecutablePath(for: kind))
            }
        )
        let request = CLIAccountRoutingRequestBridge(
            schemaVersion: 1,
            action: action,
            state: stateSnapshot(),
            accounts: CLIAccountRouterRustBridge.accountSnapshots(accounts: accounts, executablePaths: executablePaths),
            usageTotals: CLIAccountRouterRustBridge.usageSnapshots(accounts: accounts, ledger: ledger),
            provider: provider?.rawValue,
            accountId: accountId?.uuidString,
            preferredActiveAccountId: nil,
            timestamp: .now,
            failure: failure.map {
                CLIAccountRoutingFailureBridge(
                    isQuotaExhaustion: $0.isQuotaExhaustion,
                    isRateLimited: $0.isRateLimited,
                    retryAfterSeconds: $0.retryAfterSeconds,
                    normalizedCode: $0.normalizedCode
                )
            }
        )
        return CLIAccountRouterRustBridge.handle(request)
    }

    private func stateSnapshot() -> CLIAccountRoutingStateBridge {
        CLIAccountRoutingStateBridge(
            roundRobinIndex: Dictionary(uniqueKeysWithValues: roundRobinIndex.map { ($0.key.rawValue, $0.value) }),
            currentActiveAccountByProvider: Dictionary(uniqueKeysWithValues: currentActiveAccountByProvider.map { ($0.key.rawValue, $0.value.uuidString) }),
            lastFailoverReasonByProvider: Dictionary(uniqueKeysWithValues: lastFailoverReasonByProvider.map { ($0.key.rawValue, $0.value) }),
            lastSwitchAtByProvider: Dictionary(uniqueKeysWithValues: lastSwitchAtByProvider.map { ($0.key.rawValue, $0.value) })
        )
    }

    private func apply(_ state: CLIAccountRoutingStateBridge?) {
        guard let state else { return }
        roundRobinIndex = Dictionary(uniqueKeysWithValues: state.roundRobinIndex.compactMap { key, value in
            CLIProviderKind(rawValue: key).map { ($0, value) }
        })
        currentActiveAccountByProvider = Dictionary(uniqueKeysWithValues: state.currentActiveAccountByProvider.compactMap { key, value in
            guard let provider = CLIProviderKind(rawValue: key), let accountId = UUID(uuidString: value) else { return nil }
            return (provider, accountId)
        })
        lastFailoverReasonByProvider = Dictionary(uniqueKeysWithValues: state.lastFailoverReasonByProvider.compactMap { key, value in
            CLIProviderKind(rawValue: key).map { ($0, value) }
        })
        lastSwitchAtByProvider = Dictionary(uniqueKeysWithValues: state.lastSwitchAtByProvider.compactMap { key, value in
            CLIProviderKind(rawValue: key).map { ($0, value) }
        })
    }

    private func applyUpdatedAccount(_ bridge: CLIAccountRoutingAccountBridge?) {
        guard let bridge,
              let accountId = UUID(uuidString: bridge.id),
              let provider = CLIProviderKind(rawValue: bridge.provider),
              let existing = accountsStore.accounts.first(where: { $0.id == accountId }) else { return }
        let updated = CLIAccount(
            id: accountId,
            provider: provider,
            label: bridge.label,
            isEnabled: bridge.isEnabled,
            priority: bridge.priority,
            profilePath: bridge.profilePath,
            quota: CLIAccountQuotaPolicy(
                dailyLimitUSD: bridge.quota.dailyLimitUsd,
                weeklyLimitUSD: bridge.quota.weeklyLimitUsd,
                monthlyLimitUSD: bridge.quota.monthlyLimitUsd,
                dailyTokenLimit: bridge.quota.dailyTokenLimit,
                weeklyTokenLimit: bridge.quota.weeklyTokenLimit,
                monthlyTokenLimit: bridge.quota.monthlyTokenLimit
            ),
            health: CLIAccountHealth(
                cooldownUntil: bridge.health.cooldownUntil,
                lastErrorCode: bridge.health.lastErrorCode,
                consecutiveFailures: bridge.health.consecutiveFailures,
                isExhaustedLocally: bridge.health.isExhaustedLocally
            ),
            lastAuthMethod: existing.lastAuthMethod,
            lastAuthCheckAt: existing.lastAuthCheckAt,
            lastAuthError: existing.lastAuthError,
            createdAt: bridge.createdAt ?? existing.createdAt,
            updatedAt: bridge.updatedAt ?? .now
        )
        accountsStore.update(updated)
    }

    private func scheduleBootstrapActiveSelectionsIfNeeded() {
        bootstrapGeneration += 1
        let generation = bootstrapGeneration
        let accounts = accountsStore.accounts
        let currentState = stateSnapshot()
        let executablePaths = Dictionary(
            uniqueKeysWithValues: CLIProviderKind.allCases.map { kind in
                (kind, CLIAccountRouterRustBridge.providerExecutablePath(for: kind))
            }
        )

        bootstrapWorkItem?.cancel()
        let workItem = DispatchWorkItem {
            let snapshots = CLIAccountRouterRustBridge.accountSnapshots(accounts: accounts, executablePaths: executablePaths)
            let request = CLIAccountRoutingRequestBridge(
                schemaVersion: 1,
                action: "bootstrap_selections",
                state: currentState,
                accounts: snapshots,
                usageTotals: [],
                provider: nil,
                accountId: nil,
                preferredActiveAccountId: nil,
                timestamp: nil,
                failure: nil
            )
            let response = CLIAccountRouterRustBridge.handle(request)
            Task { @MainActor [weak self] in
                guard let self, self.bootstrapGeneration == generation else { return }
                self.apply(response?.state)
            }
        }
        bootstrapWorkItem = workItem
        DispatchQueue.global(qos: .utility).async(execute: workItem)
    }
}
