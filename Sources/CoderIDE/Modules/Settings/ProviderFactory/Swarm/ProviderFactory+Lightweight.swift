import CoderEngine
import Foundation

extension ProviderFactory {
    static func lightweightProvider(
        providerId: String,
        config: ProviderFactoryConfig,
        executionController: ExecutionController? = nil
    ) -> (any LLMProvider)? {
        switch normalizedBackendId(providerId) {
        case "codex", "codex-cli":
            return CodexCLIProvider(
                codexPath: config.codexPath.isEmpty ? nil : config.codexPath,
                sandboxMode: sandbox(from: config),
                modelOverride: config.codexModelOverride.isEmpty ? nil : config.codexModelOverride,
                modelReasoningEffort: config.codexReasoningEffort.isEmpty
                    ? nil : config.codexReasoningEffort,
                modelProviderOverride: config.codexModelProvider.isEmpty ? nil : config.codexModelProvider,
                preferOpenAIResponsesWireAPI: config.codexPreferResponsesWireAPI,
                yoloMode: config.globalYolo,
                askForApproval: askForApproval(from: config),
                executionController: executionController,
                executionScope: .agent,
                environmentOverride: codexEnvironmentOverride(nil)
            )
        case "claude", "claude-cli":
            return ClaudeCLIProvider(
                claudePath: config.claudePath.isEmpty ? nil : config.claudePath,
                model: config.claudeModel,
                allowedTools: [],  // No tools for lightweight
                executionController: executionController,
                executionScope: .agent,
                environmentOverride: nil
            )
        case "gemini", "gemini-cli":
            return GeminiCLIProvider(
                geminiPath: config.geminiCliPath.isEmpty ? nil : config.geminiCliPath,
                modelOverride: config.geminiModelOverride.isEmpty ? nil : config.geminiModelOverride,
                executionController: executionController,
                executionScope: .agent,
                environmentOverride: nil
            )
        case "openai-api", "openai":
            guard !config.openaiApiKey.isEmpty else { return nil }
            return OpenAIAPIProvider(
                apiKey: config.openaiApiKey,
                model: config.openaiModel,
                reasoningEffort: nil
            )
        case "anthropic-api":
            guard !config.anthropicApiKey.isEmpty else { return nil }
            return AnthropicAPIProvider(
                apiKey: config.anthropicApiKey,
                model: config.anthropicModel,
                displayName: "Anthropic"
            )
        case "google-api":
            guard !config.googleApiKey.isEmpty else { return nil }
            return OpenAIAPIProvider(
                apiKey: config.googleApiKey,
                model: config.googleModel,
                id: "google-api",
                displayName: "Google Gemini",
                baseURL: "https://generativelanguage.googleapis.com/v1beta/openai/chat/completions"
            )
        case "openrouter-api", "openrouter":
            guard !config.openrouterApiKey.isEmpty else { return nil }
            return OpenAIAPIProvider(
                apiKey: config.openrouterApiKey,
                model: normalizeOpenRouterModelId(config.openrouterModel),
                id: "openrouter-api",
                displayName: "OpenRouter",
                baseURL: "https://openrouter.ai/api/v1/chat/completions",
                extraHeaders: ["HTTP-Referer": "https://codigo.app", "X-Title": "Codigo"]
            )
        case "minimax-api":
            guard !config.minimaxApiKey.isEmpty else { return nil }
            return OpenAIAPIProvider(
                apiKey: config.minimaxApiKey,
                model: config.minimaxModel,
                id: "minimax-api",
                displayName: "MiniMax",
                baseURL: "https://api.minimax.io/v1/chat/completions"
            )
        case "grok-api":
            guard !config.grokApiKey.isEmpty else { return nil }
            return OpenAIAPIProvider(
                apiKey: config.grokApiKey,
                model: config.grokModel,
                id: "grok-api",
                displayName: "Grok (xAI)",
                baseURL: "https://api.x.ai/v1/chat/completions"
            )
        default:
            return nil
        }
    }
}
