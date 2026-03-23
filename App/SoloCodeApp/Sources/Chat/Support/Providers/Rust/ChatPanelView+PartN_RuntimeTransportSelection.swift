import Foundation
import CoderEngine

extension ChatPanelView {
    internal func resolveMainChatTransportProvider(
        selectedProvider: any LLMProvider,
        shouldRunPlanInline: Bool,
        forcePlanInline: Bool,
        preferCodeReviewRuntimeProvider: Bool? = nil
    ) -> (any LLMProvider)? {
        let environment = ProcessInfo.processInfo.environment
        let allowLegacyFallback = shouldAllowLegacyMainChatProviderFallback(environment: environment)

        guard ReviewCoreBridge.isEnabled else {
            if allowLegacyFallback {
                return selectedProvider
            }
            appendTechnicalErrorMessage(
                "[Runtime] Rust transport unavailable for main chat provider resolution. Standard path is fail-closed outside XCTest or explicit rollback flags.",
                in: conversationId
            )
            return nil
        }

        let cfg = providerFactoryConfig()
        let registryEntries = providerRegistry.providers.map {
            MainChatRuntimeProviderRegistryEntryBridge(
                id: $0.id,
                isAuthenticated: $0.isAuthenticated()
            )
        }

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
            config: cfg,
            registryProviders: registryEntries,
            codexCLIAccounts: multiCLIAccountEnabled ? cliAccountSnapshots(for: .codex) : [],
            claudeCLIAccounts: multiCLIAccountEnabled ? cliAccountSnapshots(for: .claude) : [],
            geminiCLIAccounts: multiCLIAccountEnabled ? cliAccountSnapshots(for: .gemini) : []
        )

        guard let resolved else {
            if allowLegacyFallback {
                return selectedProvider
            }
            appendTechnicalErrorMessage(
                "[Runtime] Rust transport resolution returned no provider. Standard path is fail-closed outside XCTest or explicit rollback flags.",
                in: conversationId
            )
            return nil
        }

        let runtimeProvider = providerRegistry.provider(for: resolved.providerId)

        let displayName = runtimeProvider?.displayName ?? selectedProvider.displayName
        let cliAccounts = multiCLIAccountEnabled
            ? CLIProviderKind.fromProviderId(resolved.providerId).map(cliAccountSnapshots(for:)) ?? []
            : []

        let provider = MainChatRustTransportProvider(
            id: resolved.providerId,
            displayName: displayName,
            attachmentCapabilities: resolved.attachmentCapabilities,
            authenticated: resolved.isAuthenticated,
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
