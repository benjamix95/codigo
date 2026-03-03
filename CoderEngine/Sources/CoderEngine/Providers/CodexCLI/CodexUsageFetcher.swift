import Foundation

/// Usage Codex: 5h rolling e settimanale
public struct CodexUsage: Sendable {
    public let fiveHourPct: Double?
    public let weeklyPct: Double?
    public let resetFiveH: String?
    public let resetWeekly: String?
    public let creditsBalance: Double?
    public let creditsCurrency: String?
    public let creditsSource: String?

    public init(
        fiveHourPct: Double? = nil,
        weeklyPct: Double? = nil,
        resetFiveH: String? = nil,
        resetWeekly: String? = nil,
        creditsBalance: Double? = nil,
        creditsCurrency: String? = nil,
        creditsSource: String? = nil
    ) {
        self.fiveHourPct = fiveHourPct
        self.weeklyPct = weeklyPct
        self.resetFiveH = resetFiveH
        self.resetWeekly = resetWeekly
        self.creditsBalance = creditsBalance
        self.creditsCurrency = creditsCurrency
        self.creditsSource = creditsSource
    }
}

/// Recupera usage da Codex CLI.
/// Strategia:
/// 1) app-server JSON-RPC account/rateLimits/read (affidabile)
/// 2) fallback best-effort su `/status` (legacy)
public enum CodexUsageFetcher {
    public static func fetch(
        codexPath: String,
        workingDirectory: String? = nil,
        environmentOverride: [String: String]? = nil
    ) async -> CodexUsage? {
        if let usage = await fetchViaAppServer(
            codexPath: codexPath,
            workingDirectory: workingDirectory,
            environmentOverride: environmentOverride
        ) {
            return usage
        }
        let (output, status) = await runCodexStatus(
            codexPath: codexPath,
            workingDirectory: workingDirectory,
            environmentOverride: environmentOverride
        )
        guard status == 0, !output.isEmpty else { return nil }
        return parseStatusOutput(output)
    }
}
