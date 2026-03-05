import CoderEngine
import Foundation

extension ProviderFactory {
    static func codexProvider(
        config: ProviderFactoryConfig, executionController: ExecutionController?,
        executionScope: ExecutionScope = .agent,
        codebaseIndex: CodebaseIndex? = nil,
        workspacePaths: [URL] = [],
        toolPolicy: ToolRuntimePolicy? = nil,
        environmentOverride: [String: String]? = nil,
        subagentProviderFactory: (@Sendable () -> any LLMProvider)? = nil
    ) -> any LLMProvider {
        let base = CodexCLIProvider(
            codexPath: config.codexPath.isEmpty ? nil : config.codexPath,
            sandboxMode: sandbox(from: config),
            modelOverride: config.codexModelOverride.isEmpty ? nil : config.codexModelOverride,
            modelReasoningEffort: config.codexReasoningEffort.isEmpty
                ? nil : config.codexReasoningEffort,
            modelProviderOverride: config.codexModelProvider.isEmpty ? nil : config.codexModelProvider,
            fastMode: config.codexFastMode,
            preferOpenAIResponsesWireAPI: config.codexPreferResponsesWireAPI,
            yoloMode: config.globalYolo,
            askForApproval: askForApproval(from: config),
            executionController: executionController,
            executionScope: executionScope,
            environmentOverride: codexEnvironmentOverride(environmentOverride)
        )
        guard config.unifiedToolRuntimeEnabled else { return base }
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

    static func claudeProvider(
        config: ProviderFactoryConfig, executionController: ExecutionController?,
        executionScope: ExecutionScope = .agent,
        codebaseIndex: CodebaseIndex? = nil,
        workspacePaths: [URL] = [],
        toolPolicy: ToolRuntimePolicy? = nil,
        environmentOverride: [String: String]? = nil,
        subagentProviderFactory: (@Sendable () -> any LLMProvider)? = nil
    ) -> any LLMProvider {
        let base = ClaudeCLIProvider(
            claudePath: config.claudePath.isEmpty ? nil : config.claudePath,
            model: config.claudeModel,
            allowedTools: config.claudeAllowedTools,
            executionController: executionController,
            executionScope: executionScope,
            environmentOverride: environmentOverride
        )
        guard config.unifiedToolRuntimeEnabled else { return base }
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

    static func geminiProvider(
        config: ProviderFactoryConfig, executionController: ExecutionController?,
        executionScope: ExecutionScope = .agent,
        codebaseIndex: CodebaseIndex? = nil,
        workspacePaths: [URL] = [],
        toolPolicy: ToolRuntimePolicy? = nil,
        environmentOverride: [String: String]? = nil,
        subagentProviderFactory: (@Sendable () -> any LLMProvider)? = nil
    ) -> any LLMProvider {
        let base = GeminiCLIProvider(
            geminiPath: config.geminiCliPath.isEmpty ? nil : config.geminiCliPath,
            modelOverride: config.geminiModelOverride.isEmpty ? nil : config.geminiModelOverride,
            executionController: executionController,
            executionScope: executionScope,
            environmentOverride: environmentOverride
        )
        guard config.unifiedToolRuntimeEnabled else { return base }
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
