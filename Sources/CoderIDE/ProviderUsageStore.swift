import SwiftUI
import CoderEngine

@MainActor
final class ProviderUsageStore: ObservableObject {
    @Published var codexUsage: CodexUsage?
    @Published var codexUsageMessage: String?
    @Published var claudeUsage: ClaudeUsage?
    @Published var claudeUsageMessage: String?
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

    func fetchCodexUsage(codexPath: String, workingDirectory: String? = nil) async {
        guard shouldRefresh(providerId: "codex-cli") else { return }
        guard !codexPath.isEmpty, FileManager.default.fileExists(atPath: codexPath) else {
            codexUsage = nil
            codexUsageMessage = "Codex CLI non trovato"
            return
        }
        isRefreshing = true
        defer { isRefreshing = false }
        let usage = await withTimeout(timeoutNs: usageFetchTimeoutNs) {
            await Task.detached(priority: .userInitiated) {
                await CodexUsageFetcher.fetch(codexPath: codexPath, workingDirectory: workingDirectory)
            }.value
        }
        if let usage {
            codexUsage = usage
            codexUsageMessage = nil
        } else {
            codexUsageMessage = "Rate limits non disponibili o timeout"
        }
    }

    func fetchClaudeUsage(claudePath: String, workingDirectory: String? = nil) async {
        guard shouldRefresh(providerId: "claude-cli") else { return }
        guard !claudePath.isEmpty, FileManager.default.fileExists(atPath: claudePath) else {
            claudeUsage = nil
            claudeUsageMessage = "Claude CLI non trovato"
            return
        }
        isRefreshing = true
        defer { isRefreshing = false }
        let usage = await withTimeout(timeoutNs: usageFetchTimeoutNs) {
            await Task.detached(priority: .userInitiated) {
                await ClaudeUsageFetcher.fetch(claudePath: claudePath, workingDirectory: workingDirectory)
            }.value
        }
        if let usage {
            claudeUsage = usage
            claudeUsageMessage = nil
        } else {
            claudeUsageMessage = "Usage Claude non disponibile o timeout"
        }
    }

    func fetchGeminiUsage(geminiPath: String, workingDirectory: String? = nil) async {
        guard shouldRefresh(providerId: "gemini-cli") else { return }
        guard !geminiPath.isEmpty, FileManager.default.fileExists(atPath: geminiPath) else {
            geminiUsage = nil
            geminiUsageMessage = "Gemini CLI non trovato"
            return
        }
        isRefreshing = true
        defer { isRefreshing = false }
        let usage = await withTimeout(timeoutNs: usageFetchTimeoutNs) {
            await Task.detached(priority: .userInitiated) {
                await GeminiCLIUsageFetcher.fetch(geminiPath: geminiPath, workingDirectory: workingDirectory)
            }.value
        }
        if let usage {
            geminiUsage = usage
            geminiUsageMessage = usage.note
        } else {
            geminiUsageMessage = "Usage Gemini non disponibile o timeout"
        }
    }

    func addApiUsage(inputTokens: Int, outputTokens: Int, model: String) {
        apiTokensIn += inputTokens
        apiTokensOut += outputTokens
        lastApiModel = model
        apiEstimatedCost += ModelPricing.estimatedCost(inputTokens: inputTokens, outputTokens: outputTokens, model: model)
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
        if let last = lastFetchAtByProvider[providerId], now.timeIntervalSince(last) < minRefreshInterval {
            return false
        }
        lastFetchAtByProvider[providerId] = now
        return true
    }
}
