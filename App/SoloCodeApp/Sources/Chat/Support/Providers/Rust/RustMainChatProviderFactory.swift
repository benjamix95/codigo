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
                // Keep startup provider resolution cheap. Runtime/send paths and
                // async auth refresh perform the real authentication checks.
                isAuthenticated: true
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
    static func resolveTransportConfig(
        selectedProviderId: String?,
        fallbackSelectedProviderId: String?,
        coderMode: CoderMode,
        shouldRunPlanInline: Bool,
        forcePlanInline: Bool,
        preferCodeReviewRuntimeProvider: Bool?,
        config: ProviderFactoryConfig
    ) -> MainChatRustResolvedProviderConfig? {
        let request = MainChatRuntimeTransportRequestBridge(
            schemaVersion: 1,
            selectedProviderId: selectedProviderId,
            fallbackSelectedProviderId: fallbackSelectedProviderId,
            coderMode: coderMode.rawValue,
            shouldRunPlanInline: shouldRunPlanInline,
            forcePlanInline: forcePlanInline,
            preferCodeReviewRuntimeProvider: preferCodeReviewRuntimeProvider,
            planModeBackend: config.planModeBackend,
            codeReviewExecutionBackend: config.codeReviewExecutionBackend,
            openaiApiKey: config.openaiApiKey,
            openaiModel: config.openaiModel,
            anthropicApiKey: config.anthropicApiKey,
            anthropicModel: config.anthropicModel,
            googleApiKey: config.googleApiKey,
            googleModel: config.googleModel,
            codexModelOverride: config.codexModelOverride,
            codexSandbox: config.codexSandbox,
            codexSessionFullAccess: config.codexSessionFullAccess,
            claudeModel: config.claudeModel,
            claudeAllowedTools: config.claudeAllowedTools,
            geminiModelOverride: config.geminiModelOverride
        )
        guard let response: MainChatRuntimeTransportResponseBridge = ReviewCoreBridge.call(
            functionName: "chat_core_provider_resolve_transport",
            request: request
        ), response.error == nil,
              let providerId = response.providerId,
              let backend = response.backend else {
            return nil
        }

        return MainChatRustResolvedProviderConfig(
            providerId: providerId,
            backend: backend,
            model: response.model,
            apiKey: response.apiKey,
            baseURL: response.baseURL,
            extraHeaders: response.extraHeaders,
            codexSandbox: response.codexSandbox,
            codexSessionFullAccess: response.codexSessionFullAccess,
            claudeAllowedTools: response.claudeAllowedTools
        )
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
