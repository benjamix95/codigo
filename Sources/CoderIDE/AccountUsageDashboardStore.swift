import Foundation
import CoderEngine

struct DashboardTotals {
    var accountCount: Int
    var activeCount: Int
    var exhaustedCount: Int
    var totalDayCost: Double
    var totalDayTokens: Int
}

enum DashboardCodexCreditsState: Equatable {
    case available(balance: Double, currency: String, source: String?)
    case notAvailable
}

struct DashboardAccountRow: Identifiable, Equatable {
    let id: UUID
    let provider: CLIProviderKind
    let label: String
    let isEnabled: Bool
    let isActiveNow: Bool
    let authStatus: String
    let healthStatus: String
    let dayCost: Double
    let weekCost: Double
    let monthCost: Double
    let dayTokens: Int
    let weekTokens: Int
    let monthTokens: Int
    let lastError: String?
}

struct DashboardProviderSection: Identifiable, Equatable {
    let id: CLIProviderKind
    let provider: CLIProviderKind
    let activeAccountId: UUID?
    let lastFailoverReason: String?
    let lastSwitchAt: Date?
    let codexCredits: DashboardCodexCreditsState?
    let codexRateFiveHour: Double?
    let codexRateWeekly: Double?
    let codexResetFiveHour: String?
    let codexResetWeekly: String?
    let rows: [DashboardAccountRow]
}

@MainActor
final class AccountUsageDashboardStore: ObservableObject {
    static let shared = AccountUsageDashboardStore()

    @Published private(set) var sections: [DashboardProviderSection] = []
    @Published private(set) var totals = DashboardTotals(accountCount: 0, activeCount: 0, exhaustedCount: 0, totalDayCost: 0, totalDayTokens: 0)
    @Published private(set) var lastUpdatedAt: Date?
    @Published private(set) var isRefreshing = false

    private let accountsStore = CLIAccountsStore.shared
    private let ledger = CLIAccountUsageLedgerStore.shared
    private let router = CLIAccountRouter.shared
    private let providerUsage = ProviderUsageStore.shared

    func refresh() async {
        if isRefreshing { return }
        isRefreshing = true
        defer { isRefreshing = false }

        await refreshProviderUsageSnapshots()

        var newSections: [DashboardProviderSection] = []
        for provider in CLIProviderKind.allCases {
            newSections.append(providerSummary(provider))
        }
        sections = newSections
        totals = totalSummary()
        lastUpdatedAt = Date()
    }

    func providerSummary(_ provider: CLIProviderKind) -> DashboardProviderSection {
        let accounts = accountsStore.accounts(for: provider)
        let path = providerExecutablePath(for: provider)
        let activeId = router.currentActiveAccountByProvider[provider]
        let failover = router.lastFailoverReasonByProvider[provider]
        let switchAt = router.lastSwitchAtByProvider[provider]

        let rows = accounts.map { account in
            let auth = CLIAccountAuthDetector.detect(account: account, providerPath: path)
            let day = ledger.totals(accountId: account.id, period: .day)
            let week = ledger.totals(accountId: account.id, period: .weekOfYear)
            let month = ledger.totals(accountId: account.id, period: .month)

            let healthStatus: String
            if account.health.isExhaustedLocally {
                healthStatus = "Exhausted"
            } else if let until = account.health.cooldownUntil, until > Date() {
                healthStatus = "Cooldown"
            } else {
                healthStatus = "Active"
            }

            return DashboardAccountRow(
                id: account.id,
                provider: provider,
                label: account.label,
                isEnabled: account.isEnabled,
                isActiveNow: activeId == account.id,
                authStatus: authLabel(auth),
                healthStatus: healthStatus,
                dayCost: day.cost,
                weekCost: week.cost,
                monthCost: month.cost,
                dayTokens: day.tokens,
                weekTokens: week.tokens,
                monthTokens: month.tokens,
                lastError: account.lastAuthError ?? account.health.lastErrorCode
            )
        }

        let codexCredits: DashboardCodexCreditsState?
        let codexRateFiveHour: Double?
        let codexRateWeekly: Double?
        let codexResetFiveHour: String?
        let codexResetWeekly: String?
        if provider == .codex {
            if let usage = providerUsage.codexUsage,
               let balance = usage.creditsBalance {
                codexCredits = .available(
                    balance: balance,
                    currency: usage.creditsCurrency ?? "USD",
                    source: usage.creditsSource
                )
            } else {
                codexCredits = .notAvailable
            }
            codexRateFiveHour = providerUsage.codexUsage?.fiveHourPct
            codexRateWeekly = providerUsage.codexUsage?.weeklyPct
            codexResetFiveHour = providerUsage.codexUsage?.resetFiveH
            codexResetWeekly = providerUsage.codexUsage?.resetWeekly
        } else {
            codexCredits = nil
            codexRateFiveHour = nil
            codexRateWeekly = nil
            codexResetFiveHour = nil
            codexResetWeekly = nil
        }

        return DashboardProviderSection(
            id: provider,
            provider: provider,
            activeAccountId: activeId,
            lastFailoverReason: failover,
            lastSwitchAt: switchAt,
            codexCredits: codexCredits,
            codexRateFiveHour: codexRateFiveHour,
            codexRateWeekly: codexRateWeekly,
            codexResetFiveHour: codexResetFiveHour,
            codexResetWeekly: codexResetWeekly,
            rows: rows
        )
    }

    func totalSummary() -> DashboardTotals {
        let all = CLIProviderKind.allCases.flatMap { accountsStore.accounts(for: $0) }
        var active = 0
        var exhausted = 0
        var totalCost = 0.0
        var totalTokens = 0
        for account in all {
            if account.health.isExhaustedLocally {
                exhausted += 1
            }
            if router.currentActiveAccountByProvider[account.provider] == account.id {
                active += 1
            }
            let day = ledger.totals(accountId: account.id, period: .day)
            totalCost += day.cost
            totalTokens += day.tokens
        }
        return DashboardTotals(
            accountCount: all.count,
            activeCount: active,
            exhaustedCount: exhausted,
            totalDayCost: totalCost,
            totalDayTokens: totalTokens
        )
    }

    private func providerExecutablePath(for provider: CLIProviderKind) -> String? {
        let defaults = UserDefaults.standard
        switch provider {
        case .codex: return defaults.string(forKey: "codex_path")
        case .claude: return defaults.string(forKey: "claude_path")
        case .gemini: return defaults.string(forKey: "gemini_cli_path")
        }
    }

    private func authLabel(_ status: CLIAccountAuthStatus) -> String {
        switch status {
        case .notInstalled: return "Not installed"
        case .notLoggedIn: return "Not logged"
        case .loggedIn(let method): return "Logged (\(method.rawValue))"
        case .error: return "Error"
        }
    }

    private func refreshProviderUsageSnapshots() async {
        let defaults = UserDefaults.standard
        let codexPath = defaults.string(forKey: "codex_path")
        let claudePath = defaults.string(forKey: "claude_path")
        let geminiPath = defaults.string(forKey: "gemini_cli_path")

        let effectiveCodexPath = (codexPath?.isEmpty == false) ? codexPath! : (PathFinder.find(executable: "codex") ?? "")
        let effectiveClaudePath = (claudePath?.isEmpty == false) ? claudePath! : (PathFinder.find(executable: "claude") ?? "")
        let effectiveGeminiPath = (geminiPath?.isEmpty == false) ? geminiPath! : (GeminiDetector.findGeminiPath(customPath: nil) ?? "")

        await providerUsage.fetchCodexUsage(codexPath: effectiveCodexPath, workingDirectory: nil)
        await providerUsage.fetchClaudeUsage(claudePath: effectiveClaudePath, workingDirectory: nil)
        await providerUsage.fetchGeminiUsage(geminiPath: effectiveGeminiPath, workingDirectory: nil)
    }
}
