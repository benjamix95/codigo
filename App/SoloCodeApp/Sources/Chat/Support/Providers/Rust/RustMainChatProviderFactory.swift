import CoderEngine
import Foundation

struct MainChatRustResolvedProviderConfig {
    let providerId: String
    let backend: MainChatProviderBackendBridge
    let model: String?
    let apiKey: String?
    let baseURL: String?
    let extraHeaders: [String: String]
    let codexSandbox: String?
    let codexSessionFullAccess: Bool
    let claudeAllowedTools: [String]
}

enum MainChatRustTransportSupport {
    static func resolveProviderId(
        selectedProviderId: String?,
        selectedProvider: any LLMProvider,
        coderMode: CoderMode,
        shouldRunPlanInline: Bool,
        forcePlanInline: Bool,
        preferCodeReviewRuntimeProvider: Bool?,
        config: ProviderFactoryConfig
    ) -> String {
        if forcePlanInline || shouldRunPlanInline || coderMode == .plan {
            return ProviderFactory.resolveSwarmBackendId(
                configuredBackendId: config.planModeBackend,
                agentProviderId: selectedProviderId
            )
        }
        if shouldUseCodeReviewRuntimeProvider(
            coderMode: coderMode,
            preferredOverride: preferCodeReviewRuntimeProvider
        ) {
            return ProviderFactory.resolveSwarmBackendId(
                configuredBackendId: config.codeReviewExecutionBackend,
                agentProviderId: selectedProviderId
            )
        }
        return selectedProviderId ?? selectedProvider.id
    }

    static func resolvedConfig(
        providerId: String,
        config: ProviderFactoryConfig,
        readOnlyPlan: Bool
    ) -> MainChatRustResolvedProviderConfig? {
        guard let backend = MainChatProviderBridgeSupport.backend(for: providerId) else {
            return nil
        }

        let claudeAllowedTools = readOnlyPlan
            ? ["Read", "Glob", "Grep"]
            : config.claudeAllowedTools
        let codexSandbox = readOnlyPlan ? "workspace-read" : config.codexSandbox
        let codexSessionFullAccess = readOnlyPlan ? false : config.codexSessionFullAccess

        switch backend {
        case .codexCli:
            return MainChatRustResolvedProviderConfig(
                providerId: providerId,
                backend: backend,
                model: config.codexModelOverride.isEmpty ? nil : config.codexModelOverride,
                apiKey: nil,
                baseURL: nil,
                extraHeaders: [:],
                codexSandbox: codexSandbox,
                codexSessionFullAccess: codexSessionFullAccess,
                claudeAllowedTools: claudeAllowedTools
            )
        case .claudeCli:
            return MainChatRustResolvedProviderConfig(
                providerId: providerId,
                backend: backend,
                model: config.claudeModel,
                apiKey: nil,
                baseURL: nil,
                extraHeaders: [:],
                codexSandbox: codexSandbox,
                codexSessionFullAccess: codexSessionFullAccess,
                claudeAllowedTools: claudeAllowedTools
            )
        case .geminiCli:
            return MainChatRustResolvedProviderConfig(
                providerId: providerId,
                backend: backend,
                model: config.geminiModelOverride.isEmpty ? nil : config.geminiModelOverride,
                apiKey: nil,
                baseURL: nil,
                extraHeaders: [:],
                codexSandbox: codexSandbox,
                codexSessionFullAccess: codexSessionFullAccess,
                claudeAllowedTools: claudeAllowedTools
            )
        case .openaiApi:
            return MainChatRustResolvedProviderConfig(
                providerId: providerId,
                backend: backend,
                model: config.openaiModel,
                apiKey: config.openaiApiKey,
                baseURL: "https://api.openai.com/v1/chat/completions",
                extraHeaders: [:],
                codexSandbox: codexSandbox,
                codexSessionFullAccess: codexSessionFullAccess,
                claudeAllowedTools: claudeAllowedTools
            )
        case .anthropicApi:
            return MainChatRustResolvedProviderConfig(
                providerId: providerId,
                backend: backend,
                model: config.anthropicModel,
                apiKey: config.anthropicApiKey,
                baseURL: "https://api.anthropic.com/v1/messages",
                extraHeaders: [:],
                codexSandbox: codexSandbox,
                codexSessionFullAccess: codexSessionFullAccess,
                claudeAllowedTools: claudeAllowedTools
            )
        case .googleApi:
            return MainChatRustResolvedProviderConfig(
                providerId: providerId,
                backend: backend,
                model: config.googleModel,
                apiKey: config.googleApiKey,
                baseURL: "https://generativelanguage.googleapis.com/v1beta/openai/chat/completions",
                extraHeaders: [:],
                codexSandbox: codexSandbox,
                codexSessionFullAccess: codexSessionFullAccess,
                claudeAllowedTools: claudeAllowedTools
            )
        }
    }

    static func isAuthenticated(
        baseAuthenticated: Bool,
        cliAccounts: [MainChatCLIAccountSnapshotBridge]
    ) -> Bool {
        guard !cliAccounts.isEmpty else { return baseAuthenticated }
        if baseAuthenticated {
            return true
        }
        return cliAccounts.contains { $0.isEnabled && $0.isAuthenticated }
    }
}
