import Foundation
import CoderEngine

extension ChatPanelView {
    internal func resolveMainChatTransportProvider(
        selectedProvider: any LLMProvider,
        shouldRunPlanInline: Bool,
        forcePlanInline: Bool,
        preferCodeReviewRuntimeProvider: Bool? = nil
    ) -> (any LLMProvider)? {
        guard ReviewCoreBridge.isEnabled else {
            return selectedProvider
        }

        let cfg = providerFactoryConfig()

        if MainChatRustTransportSupport.shouldBypassRustTransport(
            selectedProviderId: providerRegistry.selectedProviderId,
            fallbackSelectedProviderId: selectedProvider.id,
            config: cfg
        ) {
            return selectedProvider
        }

        let resolved = MainChatRustTransportSupport.resolveTransportConfig(
            selectedProviderId: providerRegistry.selectedProviderId,
            fallbackSelectedProviderId: selectedProvider.id,
            coderMode: coderMode,
            shouldRunPlanInline: shouldRunPlanInline,
            forcePlanInline: forcePlanInline,
            preferCodeReviewRuntimeProvider: preferCodeReviewRuntimeProvider,
            config: cfg
        )

        guard let resolved else {
            return selectedProvider
        }

        let runtimeProvider = providerRegistry.provider(for: resolved.providerId)

        let displayName = runtimeProvider?.displayName ?? selectedProvider.displayName
        let attachmentCapabilities =
            runtimeProvider?.attachmentCapabilities
            ?? MainChatProviderBridgeSupport.attachmentCapabilities(for: resolved.providerId)

        let baseAuthenticated = runtimeProvider?.isAuthenticated() ?? selectedProvider.isAuthenticated()

        let cliAccounts = multiCLIAccountEnabled
            ? CLIProviderKind.fromProviderId(resolved.providerId).map(cliAccountSnapshots(for:)) ?? []
            : []

        let authenticated = MainChatRustTransportSupport.isAuthenticated(
            baseAuthenticated: baseAuthenticated,
            cliAccounts: cliAccounts
        )

        let provider = MainChatRustTransportProvider(
            id: resolved.providerId,
            displayName: displayName,
            attachmentCapabilities: attachmentCapabilities,
            authenticated: authenticated,
            config: MainChatProviderSessionConfigBridge(
                providerId: resolved.providerId,
                displayName: displayName,
                backend: resolved.backend,
                workspacePath: runtimeWorkspacePaths.first?.path ?? FileManager.default.currentDirectoryPath,
                workspacePaths: runtimeWorkspacePaths.map(\.path),
                prompt: "",
                systemPrompt: nil,
                contextPrompt: nil,
                model: resolved.model,
                apiKey: resolved.apiKey,
                baseURL: resolved.baseURL,
                toolDefinitionsJson: nil,
                extraHeaders: resolved.extraHeaders,
                codexPath: cfg.resolvedCodexPath(),
                codexSandbox: resolved.codexSandbox,
                codexAskForApproval: cfg.codexAskForApproval,
                codexModelOverride: cfg.codexModelOverride.isEmpty ? nil : cfg.codexModelOverride,
                codexReasoningEffort: cfg.codexReasoningEffort.isEmpty ? nil : cfg.codexReasoningEffort,
                codexModelProvider: cfg.codexModelProvider.isEmpty ? nil : cfg.codexModelProvider,
                codexFastMode: cfg.codexFastMode,
                codexSessionFullAccess: resolved.codexSessionFullAccess,
                codexPreferResponsesWireAPI: cfg.codexPreferResponsesWireAPI,
                claudePath: cfg.resolvedClaudePath(),
                claudeModel: cfg.claudeModel,
                claudeAllowedTools: resolved.claudeAllowedTools,
                geminiCliPath: cfg.geminiCliPath.isEmpty ? nil : cfg.geminiCliPath,
                geminiModelOverride: cfg.geminiModelOverride.isEmpty ? nil : cfg.geminiModelOverride,
                kiloPath: cfg.resolvedKiloPath(),
                kiloModel: cfg.kiloModel.isEmpty ? nil : cfg.kiloModel,
                attachments: [],
                cliAccounts: cliAccounts
            )
        )

        return provider
    }
}
