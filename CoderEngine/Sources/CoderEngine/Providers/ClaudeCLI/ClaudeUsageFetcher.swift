import Foundation

/// Usage Claude Code: costo sessione / token
public struct ClaudeUsage: Sendable {
    public let sessionCost: String?
    public let inputTokens: Int?
    public let outputTokens: Int?
    public let cacheReadTokens: Int?
    public let cacheWriteTokens: Int?
    public let totalDuration: String?
    public let source: String?

    public init(
        sessionCost: String? = nil,
        inputTokens: Int? = nil,
        outputTokens: Int? = nil,
        cacheReadTokens: Int? = nil,
        cacheWriteTokens: Int? = nil,
        totalDuration: String? = nil,
        source: String? = nil
    ) {
        self.sessionCost = sessionCost
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.cacheReadTokens = cacheReadTokens
        self.cacheWriteTokens = cacheWriteTokens
        self.totalDuration = totalDuration
        self.source = source
    }
}

struct ClaudeCommandOutput {
    let output: String
    let exitCode: Int32
}

/// Recupera usage da Claude Code CLI tramite stream JSON strutturato.
public enum ClaudeUsageFetcher {
    public static func fetch(claudePath: String, workingDirectory: String? = nil) async
        -> ClaudeUsage?
    {
        await fetch(
            claudePath: claudePath,
            workingDirectory: workingDirectory,
            environmentOverride: nil
        )
    }

    public static func fetch(
        claudePath: String,
        workingDirectory: String? = nil,
        environmentOverride: [String: String]? = nil
    ) async
        -> ClaudeUsage?
    {
        let command = await runClaudeCost(
            claudePath: claudePath,
            workingDirectory: workingDirectory,
            environmentOverride: environmentOverride
        )
        guard command.exitCode == 0, !command.output.isEmpty else { return nil }

        // Strategy:
        // 1. Parse the `user` message that contains <local-command-stdout>...</local-command-stdout>
        //    with the REAL accumulated session cost/usage.
        // 2. Fallback: parse the `result` message JSON fields.
        // 3. Fallback: plain text regex parsing.

        if let usage = parseStreamJSON(command.output) {
            return usage
        }
        return parseCostOutput(command.output)
    }
}
