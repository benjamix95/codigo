import CoderEngine
import SwiftUI

@MainActor
final class ProviderUsageStore: ObservableObject {
    static let shared = ProviderUsageStore()
    @Published var codexUsage: CodexUsage?
    @Published var codexUsageMessage: String?
    @Published var claudeUsage: ClaudeUsage?
    @Published var claudeUsageMessage: String?
    @Published var claudeUsageSourceLabel: String?
    @Published var geminiUsage: GeminiCLIUsage?
    @Published var geminiUsageMessage: String?
    @Published var apiTokensIn: Int = 0
    @Published var apiTokensOut: Int = 0
    @Published var apiEstimatedCost: Double = 0
    @Published var lastApiModel: String = ""
    @Published var isRefreshing = false
    private let usageFetchTimeoutNs: UInt64 = 5_000_000_000
    private let minRefreshInterval: TimeInterval = 1.0
    private var lastFetchAtByProvider: [String: Date] = [:]

    // MARK: - Rate Limit Detection

    /// True when Codex 5h or weekly usage is at 100%.
    var isCodexRateLimited: Bool {
        guard let u = codexUsage else { return false }
        return (u.fiveHourPct ?? 0) >= 100.0 || (u.weeklyPct ?? 0) >= 100.0
    }

    /// Human-readable message when Codex is at its limit.
    var codexRateLimitMessage: String? {
        guard let u = codexUsage else { return nil }
        let fiveH = u.fiveHourPct ?? 0
        let weekly = u.weeklyPct ?? 0
        if fiveH >= 100.0 {
            let reset = u.resetFiveH ?? "—"
            return "You've hit your 5-hour rate limit. Resets at \(reset)."
        }
        if weekly >= 100.0 {
            let reset = u.resetWeekly ?? "—"
            return "You've hit your weekly rate limit. Resets at \(reset)."
        }
        return nil
    }

    /// Nearest reset time string for display (e.g. "14:30" or "12 Jul").
    var codexResetTime: String? {
        guard let u = codexUsage else { return nil }
        if (u.fiveHourPct ?? 0) >= 100.0 { return u.resetFiveH }
        if (u.weeklyPct ?? 0) >= 100.0 { return u.resetWeekly }
        return nil
    }

    /// True when Codex usage is high (>=80%) but not yet at limit.
    var isCodexUsageHigh: Bool {
        guard let u = codexUsage else { return false }
        let fiveH = u.fiveHourPct ?? 0
        let weekly = u.weeklyPct ?? 0
        return !isCodexRateLimited && (fiveH >= 80.0 || weekly >= 80.0)
    }

    func fetchCodexUsage(
        codexPath: String,
        workingDirectory: String? = nil,
        environmentOverride: [String: String]? = nil
    ) async {
        let refreshId = scopedProviderRefreshId(
            providerId: "codex-cli",
            scope: environmentOverride?["CODEX_HOME"]
        )
        guard shouldRefresh(providerId: refreshId) else { return }
        await Task.yield()
        guard !codexPath.isEmpty, FileManager.default.fileExists(atPath: codexPath) else {
            codexUsage = nil
            codexUsageMessage = "Codex CLI not found"
            return
        }
        isRefreshing = true
        defer { isRefreshing = false }
        let usage = await withTimeout(timeoutNs: usageFetchTimeoutNs) {
            await Task.detached(priority: .userInitiated) {
                await CodexUsageFetcher.fetch(
                    codexPath: codexPath,
                    workingDirectory: workingDirectory,
                    environmentOverride: environmentOverride
                )
            }.value
        }
        if let usage {
            codexUsage = usage
            codexUsageMessage = nil
        } else {
            codexUsage = nil
            codexUsageMessage = "Rate limits unavailable or timeout"
        }
    }

    /// Check if the currently selected provider is rate limited and return a message for the alert.
    /// Returns nil if not rate-limited or not applicable.
    func rateLimitAlertMessage(for providerId: String?) -> String? {
        guard let pid = providerId else { return nil }
        if pid == "codex-cli" {
            return codexRateLimitMessage
        }
        return nil
    }

    func fetchClaudeUsage(
        claudePath: String,
        workingDirectory: String? = nil,
        environmentOverride: [String: String]? = nil,
        anthropicAdminApiKey: String? = nil
    ) async {
        let refreshId = scopedProviderRefreshId(
            providerId: "claude-cli",
            scope: environmentOverride?["CLAUDE_HOME"]
        )
        guard shouldRefresh(providerId: refreshId) else { return }
        await Task.yield()
        guard !claudePath.isEmpty, FileManager.default.fileExists(atPath: claudePath) else {
            claudeUsage = nil
            claudeUsageMessage = "Claude CLI not found"
            claudeUsageSourceLabel = nil
            return
        }
        isRefreshing = true
        defer { isRefreshing = false }
        let trimmedAdminKey = anthropicAdminApiKey?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let attemptedOnline = !trimmedAdminKey.isEmpty
        if attemptedOnline {
            let onlineUsage = await withTimeout(timeoutNs: usageFetchTimeoutNs) {
                await Task.detached(priority: .userInitiated) {
                    await ClaudeOnlineUsageFetcher.fetch(adminApiKey: trimmedAdminKey)
                }.value
            }
            if let onlineUsage {
                claudeUsage = onlineUsage
                claudeUsageMessage = nil
                claudeUsageSourceLabel = "Online"
                return
            }
        }

        let localUsage = await withTimeout(timeoutNs: usageFetchTimeoutNs) {
            await Task.detached(priority: .userInitiated) {
                await ClaudeUsageFetcher.fetch(
                    claudePath: claudePath,
                    workingDirectory: workingDirectory,
                    environmentOverride: environmentOverride
                )
            }.value
        }
        if let localUsage {
            claudeUsage = localUsage
            claudeUsageSourceLabel = "Local session"
            if attemptedOnline {
                claudeUsageMessage = "Online usage unavailable, fallback to local session"
            } else {
                claudeUsageMessage = nil
            }
        } else {
            claudeUsage = nil
            claudeUsageSourceLabel = nil
            if attemptedOnline {
                claudeUsageMessage = "Claude usage unavailable (online + local fallback)"
            } else {
                claudeUsageMessage = "Claude usage unavailable or timeout"
            }
        }
    }

    func fetchGeminiUsage(
        geminiPath: String,
        workingDirectory: String? = nil,
        environmentOverride: [String: String]? = nil
    ) async {
        let refreshId = scopedProviderRefreshId(
            providerId: "gemini-cli",
            scope: environmentOverride?["GEMINI_CONFIG_DIR"]
        )
        guard shouldRefresh(providerId: refreshId) else { return }
        await Task.yield()
        guard !geminiPath.isEmpty, FileManager.default.fileExists(atPath: geminiPath) else {
            geminiUsage = nil
            geminiUsageMessage = "Gemini CLI not found"
            return
        }
        isRefreshing = true
        defer { isRefreshing = false }
        let usage = await withTimeout(timeoutNs: usageFetchTimeoutNs) {
            await Task.detached(priority: .userInitiated) {
                await GeminiCLIUsageFetcher.fetch(
                    geminiPath: geminiPath,
                    workingDirectory: workingDirectory,
                    environmentOverride: environmentOverride
                )
            }.value
        }
        if let usage {
            geminiUsage = usage
            geminiUsageMessage = usage.note
        } else {
            geminiUsage = nil
            geminiUsageMessage = "Gemini usage unavailable or timeout"
        }
    }

    func addApiUsage(inputTokens: Int, outputTokens: Int, model: String) {
        apiTokensIn += inputTokens
        apiTokensOut += outputTokens
        lastApiModel = model
        apiEstimatedCost += ModelPricing.estimatedCost(
            inputTokens: inputTokens, outputTokens: outputTokens, model: model)
    }

    func resetApiUsage() {
        apiTokensIn = 0
        apiTokensOut = 0
        apiEstimatedCost = 0
        lastApiModel = ""
    }

    private func withTimeout<T: Sendable>(
        timeoutNs: UInt64,
        operation: @escaping @Sendable () async -> T?
    ) async -> T? {
        await withTaskGroup(of: T?.self) { group in
            group.addTask {
                await operation()
            }
            group.addTask {
                try? await Task.sleep(nanoseconds: timeoutNs)
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
    }

    private func shouldRefresh(providerId: String) -> Bool {
        let now = Date()
        if let last = lastFetchAtByProvider[providerId],
            now.timeIntervalSince(last) < minRefreshInterval
        {
            return false
        }
        lastFetchAtByProvider[providerId] = now
        return true
    }

    private func scopedProviderRefreshId(providerId: String, scope: String?) -> String {
        let trimmed = scope?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if trimmed.isEmpty {
            return providerId
        }
        return "\(providerId)#\(trimmed)"
    }
}
