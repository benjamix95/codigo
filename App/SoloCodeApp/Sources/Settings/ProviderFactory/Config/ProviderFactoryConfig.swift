import Foundation
import CoderEngine

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

    var kiloPath: String = ""
    var kiloModel: String = ""

    var codexPath: String
    var codexSandbox: String
    var codexSessionFullAccess: Bool
    var codexAskForApproval: String
    var codexModelOverride: String
    var codexReasoningEffort: String
    var codexFastMode: Bool
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

    // MARK: - Convenience: build from UserDefaults (for sync outside View scope)

    static func fromUserDefaults(_ ud: UserDefaults = .standard) -> ProviderFactoryConfig {
        ProviderFactoryConfig(
            openaiApiKey: ud.string(forKey: "openai_api_key") ?? "",
            openaiModel: ud.string(forKey: "openai_model") ?? "gpt-4o-mini",
            anthropicApiKey: ud.string(forKey: "anthropic_api_key") ?? "",
            anthropicModel: ud.string(forKey: "anthropic_model") ?? "claude-sonnet-4-6",
            googleApiKey: ud.string(forKey: "google_api_key") ?? "",
            googleModel: ud.string(forKey: "google_model") ?? "gemini-2.5-pro",
            minimaxApiKey: ud.string(forKey: "minimax_api_key") ?? "",
            minimaxModel: ud.string(forKey: "minimax_model") ?? "MiniMax-M2.5",
            openrouterApiKey: ud.string(forKey: "openrouter_api_key") ?? "",
            openrouterModel: ud.string(forKey: "openrouter_model") ?? "anthropic/claude-sonnet-4-6",
            grokApiKey: ud.string(forKey: "grok_api_key") ?? "",
            grokModel: ud.string(forKey: "grok_model") ?? "grok-4-1-fast-reasoning",
            kiloPath: ud.string(forKey: "kilo_path") ?? "",
            kiloModel: ud.string(forKey: "kilo_model") ?? "",
            codexPath: ud.string(forKey: "codex_path") ?? "",
            codexSandbox: ud.string(forKey: "codex_sandbox") ?? "workspace-write",
            codexSessionFullAccess: ud.bool(forKey: "codex_session_full_access"),
            codexAskForApproval: ud.string(forKey: "codex_ask_for_approval") ?? "never",
            codexModelOverride: ud.string(forKey: "codex_model_override") ?? "",
            codexReasoningEffort: ud.string(forKey: "codex_reasoning_effort") ?? "low",
            codexFastMode: ud.object(forKey: "codex_fast_mode") == nil ? true : ud.bool(forKey: "codex_fast_mode"),
            codexModelProvider: ud.string(forKey: "codex_model_provider") ?? "",
            codexPreferResponsesWireAPI: ud.bool(forKey: "codex_prefer_responses_wire_api"),
            planModeBackend: ud.string(forKey: "plan_mode_backend") ?? "codex",
            swarmOrchestrator: ud.string(forKey: "swarm_orchestrator") ?? "auto",
            swarmWorkerBackend: ud.string(forKey: "swarm_worker_backend") ?? "auto",
            swarmEnabledRoles: ud.string(forKey: "swarm_enabled_roles") ?? "explorer,coder,debugger,reviewer,testWriter",
            globalYolo: ud.bool(forKey: "global_yolo"),
            codeReviewPartitions: ud.object(forKey: "code_review_partitions") == nil ? 3 : ud.integer(forKey: "code_review_partitions"),
            codeReviewAnalysisOnly: ud.bool(forKey: "code_review_analysis_only"),
            codeReviewMaxRounds: ud.object(forKey: "code_review_max_rounds") == nil ? 3 : ud.integer(forKey: "code_review_max_rounds"),
            codeReviewAnalysisBackend: ud.string(forKey: "code_review_analysis_backend") ?? "auto",
            codeReviewExecutionBackend: ud.string(forKey: "code_review_execution_backend") ?? "auto",
            claudePath: ud.string(forKey: "claude_path") ?? "",
            claudeModel: ud.string(forKey: "claude_model") ?? "claude-sonnet-4-6",
            claudeAllowedTools: ProviderFactory.normalizedToolList(
                from: ud.string(forKey: "claude_allowed_tools") ?? "Read,Edit,Bash,Write,Search,Task"
            ),
            geminiCliPath: ud.string(forKey: "gemini_cli_path") ?? "",
            geminiModelOverride: ud.string(forKey: "gemini_model_override") ?? "",
            unifiedToolRuntimeEnabled: ud.object(forKey: "unified_tool_runtime_enabled") == nil ? true : ud.bool(forKey: "unified_tool_runtime_enabled"),
            agentsHardBlockEnabled: ud.object(forKey: "agents_hard_block_enabled") == nil ? true : ud.bool(forKey: "agents_hard_block_enabled"),
            mcpEditEnforcementEnabled: ud.object(forKey: "mcp_edit_enforcement_enabled") == nil ? true : ud.bool(forKey: "mcp_edit_enforcement_enabled"),
            webSearchProvider: ud.string(forKey: "web_search_provider") ?? "duckduckgo",
            braveSearchApiKey: ud.string(forKey: "brave_search_api_key") ?? "",
            tavilyApiKey: ud.string(forKey: "tavily_api_key") ?? "",
            serperApiKey: ud.string(forKey: "serper_api_key") ?? ""
        )
    }

    func resolvedCodexPath(
        detect: (String?) -> String? = { CodexDetector.findCodexPath(customPath: $0) }
    ) -> String? {
        let trimmed = codexPath.trimmingCharacters(in: .whitespacesAndNewlines)
        return detect(trimmed.isEmpty ? nil : trimmed)
    }

    func resolvedClaudePath(
        detect: (String?) -> String? = { ClaudeDetector.findClaudePath(customPath: $0) }
    ) -> String? {
        let trimmed = claudePath.trimmingCharacters(in: .whitespacesAndNewlines)
        return detect(trimmed.isEmpty ? nil : trimmed)
    }

    func resolvedKiloPath(
        detect: (String?) -> String? = { KiloDetector.findKiloPath(customPath: $0) }
    ) -> String? {
        let trimmed = kiloPath.trimmingCharacters(in: .whitespacesAndNewlines)
        return detect(trimmed.isEmpty ? nil : trimmed)
    }
}
