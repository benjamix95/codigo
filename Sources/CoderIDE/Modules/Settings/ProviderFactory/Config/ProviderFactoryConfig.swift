import Foundation

struct ProviderFactoryConfig {
    var openaiApiKey: String
    var openaiModel: String
    var anthropicApiKey: String
    var anthropicModel: String
    var googleApiKey: String
    var googleModel: String
    var minimaxApiKey: String
    var minimaxModel: String
    var openrouterApiKey: String
    var openrouterModel: String
    var grokApiKey: String
    var grokModel: String

    var codexPath: String
    var codexSandbox: String
    var codexSessionFullAccess: Bool
    var codexAskForApproval: String
    var codexModelOverride: String
    var codexReasoningEffort: String
    var codexModelProvider: String
    var codexPreferResponsesWireAPI: Bool
    var planModeBackend: String

    var swarmOrchestrator: String
    var swarmWorkerBackend: String
    var swarmEnabledRoles: String

    var globalYolo: Bool
    var codeReviewPartitions: Int
    var codeReviewAnalysisOnly: Bool
    var codeReviewMaxRounds: Int
    var codeReviewAnalysisBackend: String
    var codeReviewExecutionBackend: String

    var claudePath: String
    var claudeModel: String
    var claudeAllowedTools: [String]
    var geminiCliPath: String
    var geminiModelOverride: String
    var unifiedToolRuntimeEnabled: Bool
    var agentsHardBlockEnabled: Bool
    var mcpEditEnforcementEnabled: Bool

    var usePipelineOrchestrator: Bool

    var webSearchProvider: String
    var braveSearchApiKey: String
    var tavilyApiKey: String
    var serperApiKey: String

    /// Build a `[String: String]` keys map suitable for `UnifiedToolRuntime`.
    var webSearchApiKeys: [String: String] {
        var keys: [String: String] = [:]
        if !braveSearchApiKey.isEmpty { keys["brave"] = braveSearchApiKey }
        if !tavilyApiKey.isEmpty { keys["tavily"] = tavilyApiKey }
        if !serperApiKey.isEmpty { keys["serper"] = serperApiKey }
        return keys
    }
}
