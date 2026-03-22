import Foundation
import CoderEngine

struct CLIAccountRoutingQuotaBridge: Codable, Equatable {
    let dailyLimitUsd: Double?
    let weeklyLimitUsd: Double?
    let monthlyLimitUsd: Double?
    let dailyTokenLimit: Int?
    let weeklyTokenLimit: Int?
    let monthlyTokenLimit: Int?
}

struct CLIAccountRoutingHealthBridge: Codable, Equatable {
    let cooldownUntil: Date?
    let lastErrorCode: String?
    let consecutiveFailures: Int
    let isExhaustedLocally: Bool
}

struct CLIAccountRoutingAccountBridge: Codable, Equatable {
    let id: String
    let provider: String
    let label: String
    let isEnabled: Bool
    let isAuthenticated: Bool
    let priority: Int
    let profilePath: String
    let quota: CLIAccountRoutingQuotaBridge
    let health: CLIAccountRoutingHealthBridge
    let createdAt: Date?
    let updatedAt: Date?
}

struct CLIAccountUsageTotalsBridge: Codable, Equatable {
    let accountId: String
    let dayCost: Double
    let weekCost: Double
    let monthCost: Double
    let dayTokens: Int
    let weekTokens: Int
    let monthTokens: Int
}

struct CLIAccountRoutingStateBridge: Codable, Equatable {
    var roundRobinIndex: [String: Int]
    var currentActiveAccountByProvider: [String: String]
    var lastFailoverReasonByProvider: [String: String]
    var lastSwitchAtByProvider: [String: Date]
}

struct CLIAccountRoutingFailureBridge: Codable, Equatable {
    let isQuotaExhaustion: Bool
    let isRateLimited: Bool
    let retryAfterSeconds: Int?
    let normalizedCode: String
}

struct CLIAccountRoutingRequestBridge: Encodable {
    var schemaVersion: Int
    var action: String
    var state: CLIAccountRoutingStateBridge
    var accounts: [CLIAccountRoutingAccountBridge]
    var usageTotals: [CLIAccountUsageTotalsBridge]
    var provider: String?
    var accountId: String?
    var preferredActiveAccountId: String?
    var timestamp: Date?
    var failure: CLIAccountRoutingFailureBridge?
}

struct CLIAccountRoutingResponseBridge: Decodable {
    let schemaVersion: Int
    let error: CLIAccountRoutingErrorBridge?
    let state: CLIAccountRoutingStateBridge?
    let selectedAccountId: String?
    let activeAccountId: String?
    let availabilityStatus: String?
    let availabilityReason: String?
    let updatedAccount: CLIAccountRoutingAccountBridge?
}

struct CLIAccountRoutingErrorBridge: Decodable, Equatable {
    let code: String
    let message: String
}

enum CLIAccountRouterRustBridge {
    static func handle(_ request: CLIAccountRoutingRequestBridge) -> CLIAccountRoutingResponseBridge? {
        ReviewCoreBridge.call(functionName: "cli_accounts_handle_action", request: request)
    }

    static func providerExecutablePath(for provider: CLIProviderKind, userDefaults: UserDefaults = .standard) -> String? {
        let customPath: String?
        switch provider {
        case .codex: customPath = userDefaults.string(forKey: "codex_path")
        case .claude: customPath = userDefaults.string(forKey: "claude_path")
        case .gemini: customPath = userDefaults.string(forKey: "gemini_cli_path")
        }
        return CLIAccountAuthDetector.resolveExecutable(provider: provider, providerPath: customPath)
    }

    static func accountSnapshots(accounts: [CLIAccount], executablePaths: [CLIProviderKind: String?]) -> [CLIAccountRoutingAccountBridge] {
        accounts.map { account in
            let auth = CLIAccountAuthDetector.detect(account: account, providerPath: executablePaths[account.provider] ?? nil)
            return CLIAccountRoutingAccountBridge(
                id: account.id.uuidString,
                provider: account.provider.rawValue,
                label: account.label,
                isEnabled: account.isEnabled,
                isAuthenticated: auth.isLoggedIn,
                priority: account.priority,
                profilePath: account.profilePath,
                quota: CLIAccountRoutingQuotaBridge(
                    dailyLimitUsd: account.quota.dailyLimitUSD,
                    weeklyLimitUsd: account.quota.weeklyLimitUSD,
                    monthlyLimitUsd: account.quota.monthlyLimitUSD,
                    dailyTokenLimit: account.quota.dailyTokenLimit,
                    weeklyTokenLimit: account.quota.weeklyTokenLimit,
                    monthlyTokenLimit: account.quota.monthlyTokenLimit
                ),
                health: CLIAccountRoutingHealthBridge(
                    cooldownUntil: account.health.cooldownUntil,
                    lastErrorCode: account.health.lastErrorCode,
                    consecutiveFailures: account.health.consecutiveFailures,
                    isExhaustedLocally: account.health.isExhaustedLocally
                ),
                createdAt: account.createdAt,
                updatedAt: account.updatedAt
            )
        }
    }

    @MainActor
    static func usageSnapshots(accounts: [CLIAccount], ledger: CLIAccountUsageLedgerStore) -> [CLIAccountUsageTotalsBridge] {
        accounts.map { account in
            let day = ledger.totals(accountId: account.id, period: .day)
            let week = ledger.totals(accountId: account.id, period: .weekOfYear)
            let month = ledger.totals(accountId: account.id, period: .month)
            return CLIAccountUsageTotalsBridge(
                accountId: account.id.uuidString,
                dayCost: day.cost,
                weekCost: week.cost,
                monthCost: month.cost,
                dayTokens: day.tokens,
                weekTokens: week.tokens,
                monthTokens: month.tokens
            )
        }
    }
}

final class CLIMultiAccountProviderAdapter: LLMProvider, @unchecked Sendable {
    private static let accountsStorageKey = "CoderIDE.cliAccounts"

    let id: String
    let displayName: String

    private let providerKind: CLIProviderKind
    private let router: CLIAccountRouter
    private let accountsStore: CLIAccountsStore
    private let makeProvider: (CLIAccount, [String: String]) -> any LLMProvider

    init(
        providerKind: CLIProviderKind,
        id: String,
        displayName: String,
        router: CLIAccountRouter,
        accountsStore: CLIAccountsStore,
        makeProvider: @escaping (CLIAccount, [String: String]) -> any LLMProvider
    ) {
        self.providerKind = providerKind
        self.id = id
        self.displayName = displayName
        self.router = router
        self.accountsStore = accountsStore
        self.makeProvider = makeProvider
    }

    func isAuthenticated() -> Bool {
        Self.hasAuthenticatedAvailableAccount(
            providerKind: providerKind,
            userDefaults: .standard
        )
    }

    func send(prompt: String, context: WorkspaceContext, imageURLs: [URL]?) async throws -> AsyncThrowingStream<StreamEvent, Error> {
        AsyncThrowingStream { continuation in
            let driver = Task {
                var attempted = Set<UUID>()
                var account = await MainActor.run {
                    router.selectedOrNextAvailableAccount(for: providerKind)
                }
                var lastErrorMessage = ""

                while let selected = account, !attempted.contains(selected.id), !Task.isCancelled {
                    attempted.insert(selected.id)
                    let secret = await MainActor.run { accountsStore.secret(for: selected.id) }
                    let env = CLIProfileProvisioner.environmentOverrides(provider: providerKind, profilePath: selected.profilePath, secret: secret)
                    let provider = makeProvider(selected, env)

                    do {
                        let stream = try await provider.send(prompt: prompt, context: context, imageURLs: imageURLs)
                        for try await event in stream {
                            guard !Task.isCancelled else { return }
                            if case .raw(let type, let payload) = event, type == "usage" {
                                let input = Int(payload["input_tokens"] ?? "0") ?? 0
                                let output = Int(payload["output_tokens"] ?? "0") ?? 0
                                let cost = ModelPricing.estimatedCost(inputTokens: input, outputTokens: output, model: payload["model"] ?? id)
                                await MainActor.run {
                                    router.markUsage(accountId: selected.id, provider: providerKind, inputTokens: input, outputTokens: output, estimatedCost: cost)
                                    Task { await AccountUsageDashboardStore.shared.refresh() }
                                }
                            }
                            if case .error(let message) = event {
                                lastErrorMessage = message
                            }
                            continuation.yield(event)
                        }
                        continuation.finish()
                        return
                    } catch {
                        guard !Task.isCancelled else { return }
                        let message = lastErrorMessage.isEmpty ? error.localizedDescription : lastErrorMessage
                        let classified = CLIErrorClassifier.classify(providerId: id, message: message)
                        await MainActor.run {
                            router.markProviderError(
                                accountId: selected.id,
                                provider: providerKind,
                                classifiedError: CLIClassifiedFailure(
                                    isQuotaExhaustion: classified.isQuotaExhaustion,
                                    isRateLimited: classified.isRateLimited,
                                    retryAfterSeconds: classified.retryAfterSeconds,
                                    normalizedCode: classified.normalizedCode
                                )
                            )
                            Task { await AccountUsageDashboardStore.shared.refresh() }
                        }

                        if classified.isQuotaExhaustion || classified.isRateLimited {
                            account = await MainActor.run {
                                router.nextAvailableAccount(after: selected.id, provider: providerKind)
                            }
                            continue
                        }
                        continuation.yield(.error(error.localizedDescription))
                        continuation.finish(throwing: error)
                        return
                    }
                }

                if !Task.isCancelled {
                    continuation.yield(.error("All \(providerKind.displayName) accounts are exhausted or unavailable."))
                    continuation.finish(throwing: CoderEngineError.notAuthenticated)
                }
            }

            continuation.onTermination = { _ in
                driver.cancel()
            }
        }
    }

    static func hasAuthenticatedAvailableAccount(
        providerKind: CLIProviderKind,
        userDefaults: UserDefaults
    ) -> Bool {
        guard let data = userDefaults.data(forKey: accountsStorageKey),
              let decoded = try? JSONDecoder().decode([CLIAccount].self, from: data) else {
            return false
        }

        let executablePaths = Dictionary(
            uniqueKeysWithValues: CLIProviderKind.allCases.map { kind in
                (kind, CLIAccountRouterRustBridge.providerExecutablePath(for: kind, userDefaults: userDefaults))
            }
        )
        let request = CLIAccountRoutingRequestBridge(
            schemaVersion: 1,
            action: "current_availability",
            state: CLIAccountRoutingStateBridge(
                roundRobinIndex: [:],
                currentActiveAccountByProvider: [:],
                lastFailoverReasonByProvider: [:],
                lastSwitchAtByProvider: [:]
            ),
            accounts: CLIAccountRouterRustBridge.accountSnapshots(accounts: decoded, executablePaths: executablePaths),
            usageTotals: [],
            provider: providerKind.rawValue,
            accountId: nil,
            preferredActiveAccountId: nil,
            timestamp: nil,
            failure: nil
        )
        let response = CLIAccountRouterRustBridge.handle(request)
        return response?.availabilityStatus == "available"
    }
}
