import CoderEngine
import Foundation

private struct ThreadProviderRegistryEntryBridge: Encodable {
    let id: String
    let isAuthenticated: Bool
}

private struct ThreadProviderSelectionRequestBridge: Encodable {
    let schemaVersion: Int
    let conversationMode: String?
    let preferredProviderId: String?
    let currentProviderId: String?
    let selectedProviderId: String?
    let registrySelectedProviderId: String?
    let registryProviders: [ThreadProviderRegistryEntryBridge]
}

private struct ThreadProviderSelectionResponseBridge: Decodable {
    let schemaVersion: Int
    let error: ThreadProviderSelectionErrorBridge?
    let effectiveMode: String?
    let resolvedProviderId: String?
    let missingBoundProviderId: String?
}

private struct ThreadProviderSelectionErrorBridge: Decodable {
    let code: String
    let message: String
}

enum ThreadProviderSelectionService {
    static func effectiveMode(for conversation: Conversation?) -> CoderMode {
        let response = resolve(
            conversation: conversation,
            currentProviderId: nil,
            selectedProviderId: nil,
            registry: nil
        )
        return response.effectiveMode.flatMap(CoderMode.init(rawValue:)) ?? .agent
    }

    static func resolveProviderId(
        conversation: Conversation?,
        currentProviderId: String?,
        registry: ProviderRegistry
    ) -> String? {
        resolve(
            conversation: conversation,
            currentProviderId: currentProviderId,
            selectedProviderId: nil,
            registry: registry
        ).resolvedProviderId
    }

    static func missingBoundProviderId(
        conversation: Conversation?,
        selectedProviderId: String?,
        registry: ProviderRegistry
    ) -> String? {
        resolve(
            conversation: conversation,
            currentProviderId: nil,
            selectedProviderId: selectedProviderId,
            registry: registry
        ).missingBoundProviderId
    }

    @MainActor
    static func persistRuntimeProviderSelection(
        chatStore: ChatStore,
        conversationId: UUID?,
        runtimeProviderId: String
    ) {
        guard let normalizedProviderId = normalizedProviderId(runtimeProviderId) else { return }
        chatStore.updatePreferredProvider(
            conversationId: conversationId,
            providerId: normalizedProviderId
        )
    }

    private static func resolve(
        conversation: Conversation?,
        currentProviderId: String?,
        selectedProviderId: String?,
        registry: ProviderRegistry?
    ) -> ThreadProviderSelectionResponseBridge {
        let request = ThreadProviderSelectionRequestBridge(
            schemaVersion: 1,
            conversationMode: conversation?.mode?.rawValue,
            preferredProviderId: normalizedProviderId(conversation?.preferredProviderId),
            currentProviderId: normalizedProviderId(currentProviderId),
            selectedProviderId: normalizedProviderId(selectedProviderId),
            registrySelectedProviderId: normalizedProviderId(registry?.selectedProviderId),
            registryProviders: registry.map(registryEntries) ?? []
        )
        return ReviewCoreBridge.call(
            functionName: "chat_core_thread_provider_selection",
            request: request
        ) ?? ThreadProviderSelectionResponseBridge(
            schemaVersion: 1,
            error: ThreadProviderSelectionErrorBridge(
                code: "bridge_unavailable",
                message: "Rust thread provider selection unavailable"
            ),
            effectiveMode: conversation?.mode?.rawValue ?? CoderMode.agent.rawValue,
            resolvedProviderId: nil,
            missingBoundProviderId: nil
        )
    }

    private static func normalizedProviderId(_ providerId: String?) -> String? {
        let trimmed = providerId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func registryEntries(_ registry: ProviderRegistry) -> [ThreadProviderRegistryEntryBridge] {
        registry.providers.map { provider in
            ThreadProviderRegistryEntryBridge(
                id: provider.id,
                isAuthenticated: provider.isAuthenticated()
            )
        }
    }
}

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
