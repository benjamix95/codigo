import CoderEngine
import Foundation

extension ProviderFactory {
    static func openAIAPIProvider(
        config: ProviderFactoryConfig, reasoningEffort: String? = nil,
        executionScope: ExecutionScope = .agent,
        executionController: ExecutionController? = nil,
        codebaseIndex: CodebaseIndex? = nil,
        workspacePaths: [URL] = [],
        toolPolicy: ToolRuntimePolicy? = nil,
        subagentProviderFactory: (@Sendable () -> any LLMProvider)? = nil
    ) -> any LLMProvider {
        let base = OpenAIAPIProvider(
            apiKey: config.openaiApiKey,
            model: config.openaiModel,
            reasoningEffort: reasoningEffort
        )
        let effectivePolicy = toolPolicy ?? toolRuntimePolicy(from: config)
        return ToolEnabledLLMProvider(
            base: base,
            runtime: buildRuntime(
                executionController: executionController,
                executionScope: executionScope,
                codebaseIndex: codebaseIndex,
                workspacePaths: workspacePaths,
                webSearchProvider: config.webSearchProvider,
                webSearchApiKeys: config.webSearchApiKeys
            ),
            policy: effectivePolicy,
            executionScope: executionScope,
            executionController: executionController,
            subagentProviderFactory: subagentProviderFactory
        )
    }

    static func anthropicAPIProvider(
        config: ProviderFactoryConfig, executionScope: ExecutionScope = .agent,
        executionController: ExecutionController? = nil,
        codebaseIndex: CodebaseIndex? = nil,
        workspacePaths: [URL] = [],
        toolPolicy: ToolRuntimePolicy? = nil,
        subagentProviderFactory: (@Sendable () -> any LLMProvider)? = nil
    ) -> any LLMProvider {
        let base = AnthropicAPIProvider(
            apiKey: config.anthropicApiKey,
            model: config.anthropicModel,
            displayName: "Anthropic"
        )
        let effectivePolicy = toolPolicy ?? toolRuntimePolicy(from: config)
        return ToolEnabledLLMProvider(
            base: base,
            runtime: buildRuntime(
                executionController: executionController,
                executionScope: executionScope,
                codebaseIndex: codebaseIndex,
                workspacePaths: workspacePaths,
                webSearchProvider: config.webSearchProvider,
                webSearchApiKeys: config.webSearchApiKeys
            ),
            policy: effectivePolicy,
            executionScope: executionScope,
            executionController: executionController,
            subagentProviderFactory: subagentProviderFactory
        )
    }

    static func googleAPIProvider(
        config: ProviderFactoryConfig, executionScope: ExecutionScope = .agent,
        executionController: ExecutionController? = nil,
        codebaseIndex: CodebaseIndex? = nil,
        workspacePaths: [URL] = [],
        toolPolicy: ToolRuntimePolicy? = nil,
        subagentProviderFactory: (@Sendable () -> any LLMProvider)? = nil
    ) -> any LLMProvider {
        let base = OpenAIAPIProvider(
            apiKey: config.googleApiKey,
            model: config.googleModel,
            id: "google-api",
            displayName: "Google Gemini",
            baseURL: "https://generativelanguage.googleapis.com/v1beta/openai/chat/completions"
        )
        let effectivePolicy = toolPolicy ?? toolRuntimePolicy(from: config)
        return ToolEnabledLLMProvider(
            base: base,
            runtime: buildRuntime(
                executionController: executionController,
                executionScope: executionScope,
                codebaseIndex: codebaseIndex,
                workspacePaths: workspacePaths,
                webSearchProvider: config.webSearchProvider,
                webSearchApiKeys: config.webSearchApiKeys
            ),
            policy: effectivePolicy,
            executionScope: executionScope,
            executionController: executionController,
            subagentProviderFactory: subagentProviderFactory
        )
    }

    static func miniMaxAPIProvider(
        config: ProviderFactoryConfig,
        executionScope: ExecutionScope = .agent,
        executionController: ExecutionController? = nil,
        codebaseIndex: CodebaseIndex? = nil,
        workspacePaths: [URL] = [],
        toolPolicy: ToolRuntimePolicy? = nil,
        subagentProviderFactory: (@Sendable () -> any LLMProvider)? = nil
    ) -> any LLMProvider {
        let base = OpenAIAPIProvider(
            apiKey: config.minimaxApiKey,
            model: config.minimaxModel,
            id: "minimax-api",
            displayName: "MiniMax",
            baseURL: "https://api.minimax.io/v1/chat/completions"
        )
        let effectivePolicy = toolPolicy ?? toolRuntimePolicy(from: config)
        return ToolEnabledLLMProvider(
            base: base,
            runtime: buildRuntime(
                executionController: executionController,
                executionScope: executionScope,
                codebaseIndex: codebaseIndex,
                workspacePaths: workspacePaths,
                webSearchProvider: config.webSearchProvider,
                webSearchApiKeys: config.webSearchApiKeys
            ),
            policy: effectivePolicy,
            executionScope: executionScope,
            executionController: executionController,
            subagentProviderFactory: subagentProviderFactory
        )
    }

    static func openRouterAPIProvider(
        config: ProviderFactoryConfig, executionScope: ExecutionScope = .agent,
        executionController: ExecutionController? = nil,
        codebaseIndex: CodebaseIndex? = nil,
        workspacePaths: [URL] = [],
        toolPolicy: ToolRuntimePolicy? = nil,
        subagentProviderFactory: (@Sendable () -> any LLMProvider)? = nil
    ) -> any LLMProvider {
        let base = OpenAIAPIProvider(
            apiKey: config.openrouterApiKey,
            model: normalizeOpenRouterModelId(config.openrouterModel),
            id: "openrouter-api",
            displayName: "OpenRouter",
            baseURL: "https://openrouter.ai/api/v1/chat/completions",
            extraHeaders: ["HTTP-Referer": "https://solocode.app", "X-Title": "Solo Code"]
        )
        let effectivePolicy = toolPolicy ?? toolRuntimePolicy(from: config)
        return ToolEnabledLLMProvider(
            base: base,
            runtime: buildRuntime(
                executionController: executionController,
                executionScope: executionScope,
                codebaseIndex: codebaseIndex,
                workspacePaths: workspacePaths,
                webSearchProvider: config.webSearchProvider,
                webSearchApiKeys: config.webSearchApiKeys
            ),
            policy: effectivePolicy,
            executionScope: executionScope,
            executionController: executionController,
            subagentProviderFactory: subagentProviderFactory
        )
    }

    static func grokAPIProvider(
        config: ProviderFactoryConfig, executionScope: ExecutionScope = .agent,
        executionController: ExecutionController? = nil,
        codebaseIndex: CodebaseIndex? = nil,
        workspacePaths: [URL] = [],
        toolPolicy: ToolRuntimePolicy? = nil,
        subagentProviderFactory: (@Sendable () -> any LLMProvider)? = nil
    ) -> any LLMProvider {
        let base = OpenAIAPIProvider(
            apiKey: config.grokApiKey,
            model: config.grokModel,
            id: "grok-api",
            displayName: "Grok (xAI)",
            baseURL: "https://api.x.ai/v1/chat/completions"
        )
        let effectivePolicy = toolPolicy ?? toolRuntimePolicy(from: config)
        return ToolEnabledLLMProvider(
            base: base,
            runtime: buildRuntime(
                executionController: executionController,
                executionScope: executionScope,
                codebaseIndex: codebaseIndex,
                workspacePaths: workspacePaths,
                webSearchProvider: config.webSearchProvider,
                webSearchApiKeys: config.webSearchApiKeys
            ),
            policy: effectivePolicy,
            executionScope: executionScope,
            executionController: executionController,
            subagentProviderFactory: subagentProviderFactory
        )
    }
}
