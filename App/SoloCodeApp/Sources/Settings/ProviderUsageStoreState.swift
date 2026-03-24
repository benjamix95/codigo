import CoderEngine
import Foundation

// MARK: - ProviderUsageSnapshot

/// Groups all provider usage data into a single struct.
/// Updating one provider's usage fires ONE notification instead of 2-3.
struct ProviderUsageSnapshot {
    var codexUsage: CodexUsage?
    var codexUsageMessage: String?
    var claudeUsage: ClaudeUsage?
    var claudeUsageMessage: String?
    var claudeUsageSourceLabel: String?
    var geminiUsage: GeminiCLIUsage?
    var geminiUsageMessage: String?
}

// MARK: - ApiUsageSnapshot

/// Groups API token and cost tracking into a single struct.
struct ApiUsageSnapshot {
    var apiTokensIn: Int = 0
    var apiTokensOut: Int = 0
    var apiEstimatedCost: Double = 0
    var lastApiModel: String = ""
}
