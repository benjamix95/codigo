import Foundation
import CoderEngine

extension ChatPanelView {
    private func fallbackLegacyRuntimeProvider(
        selectedProvider: any LLMProvider,
        shouldRunPlanInline: Bool,
        forcePlanInline: Bool,
        preferCodeReviewRuntimeProvider: Bool?
    ) -> (any LLMProvider)? {
        resolveRuntimeProvider(
            selectedProvider: selectedProvider,
            shouldRunPlanInline: shouldRunPlanInline,
            forcePlanInline: forcePlanInline,
            preferCodeReviewRuntimeProvider: preferCodeReviewRuntimeProvider
        )
    }

    internal func resolveMainChatTransportProvider(
        selectedProvider: any LLMProvider,
        shouldRunPlanInline: Bool,
        forcePlanInline: Bool,
        preferCodeReviewRuntimeProvider: Bool? = nil
    ) -> (any LLMProvider)? {
        guard ReviewCoreBridge.isEnabled else {
            return fallbackLegacyRuntimeProvider(
                selectedProvider: selectedProvider,
                shouldRunPlanInline: shouldRunPlanInline,
                forcePlanInline: forcePlanInline,
                preferCodeReviewRuntimeProvider: preferCodeReviewRuntimeProvider
            )
        }
        let cfg = providerFactoryConfig()
        let resolvedProviderId = MainChatRustTransportSupport.resolveProviderId(
            selectedProviderId: providerRegistry.selectedProviderId,
            selectedProvider: selectedProvider,
            coderMode: coderMode,
            shouldRunPlanInline: shouldRunPlanInline,
            forcePlanInline: forcePlanInline,
            preferCodeReviewRuntimeProvider: preferCodeReviewRuntimeProvider,
            config: cfg
        )
        let readOnlyPlan = forcePlanInline || shouldRunPlanInline || coderMode == .plan

        guard let resolved = MainChatRustTransportSupport.resolvedConfig(
            providerId: resolvedProviderId,
            config: cfg,
            readOnlyPlan: readOnlyPlan
        ) else {
            return fallbackLegacyRuntimeProvider(
                selectedProvider: selectedProvider,
                shouldRunPlanInline: shouldRunPlanInline,
                forcePlanInline: forcePlanInline,
                preferCodeReviewRuntimeProvider: preferCodeReviewRuntimeProvider
            )
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

        return MainChatRustTransportProvider(
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
                codexPath: cfg.codexPath.isEmpty ? nil : cfg.codexPath,
                codexSandbox: resolved.codexSandbox,
                codexAskForApproval: cfg.codexAskForApproval,
                codexModelOverride: cfg.codexModelOverride.isEmpty ? nil : cfg.codexModelOverride,
                codexReasoningEffort: cfg.codexReasoningEffort.isEmpty ? nil : cfg.codexReasoningEffort,
                codexModelProvider: cfg.codexModelProvider.isEmpty ? nil : cfg.codexModelProvider,
                codexFastMode: cfg.codexFastMode,
                codexSessionFullAccess: resolved.codexSessionFullAccess,
                codexPreferResponsesWireAPI: cfg.codexPreferResponsesWireAPI,
                claudePath: cfg.claudePath.isEmpty ? nil : cfg.claudePath,
                claudeModel: cfg.claudeModel,
                claudeAllowedTools: resolved.claudeAllowedTools,
                geminiCliPath: cfg.geminiCliPath.isEmpty ? nil : cfg.geminiCliPath,
                geminiModelOverride: cfg.geminiModelOverride.isEmpty ? nil : cfg.geminiModelOverride,
                attachments: [],
                cliAccounts: cliAccounts
            )
        )
    }
}
