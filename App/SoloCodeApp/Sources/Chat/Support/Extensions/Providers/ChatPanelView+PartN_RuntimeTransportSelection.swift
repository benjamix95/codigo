import Foundation
import CoderEngine

extension ChatPanelView {
    private func cliAccountSnapshots(for kind: CLIProviderKind) -> [MainChatCLIAccountSnapshotBridge] {
        let cfg = providerFactoryConfig()
        return cliAccountsStore.accounts(for: kind).map { account in
            let executable = switch kind {
            case .codex:
                CLIAccountAuthDetector.resolveExecutable(provider: .codex, providerPath: cfg.codexPath)
            case .claude:
                CLIAccountAuthDetector.resolveExecutable(provider: .claude, providerPath: cfg.claudePath)
            case .gemini:
                CLIAccountAuthDetector.resolveExecutable(provider: .gemini, providerPath: cfg.geminiCliPath)
            }
            let auth = CLIAccountAuthDetector.detect(account: account, providerPath: executable)
            let secret = cliAccountsStore.secret(for: account.id)
            let env = CLIProfileProvisioner.environmentOverrides(
                provider: kind,
                profilePath: account.profilePath,
                secret: secret
            )
            return MainChatCLIAccountSnapshotBridge(
                id: account.id.uuidString,
                provider: account.provider.rawValue,
                label: account.label,
                isEnabled: account.isEnabled,
                isAuthenticated: auth.isLoggedIn,
                priority: account.priority,
                profilePath: account.profilePath,
                envOverrides: env,
                quota: MainChatCLIQuotaSnapshotBridge(account.quota),
                health: MainChatCLIHealthSnapshotBridge(account.health),
                createdAt: account.createdAt,
                updatedAt: account.updatedAt
            )
        }
    }

    internal func resolveMainChatTransportProvider(
        selectedProvider: any LLMProvider,
        shouldRunPlanInline: Bool,
        forcePlanInline: Bool,
        preferCodeReviewRuntimeProvider: Bool? = nil
    ) -> (any LLMProvider)? {
        guard ReviewCoreBridge.isEnabled else {
            return resolveRuntimeProvider(
                selectedProvider: selectedProvider,
                shouldRunPlanInline: shouldRunPlanInline,
                forcePlanInline: forcePlanInline,
                preferCodeReviewRuntimeProvider: preferCodeReviewRuntimeProvider
            )
        }
        guard let runtimeProvider = resolveRuntimeProvider(
            selectedProvider: selectedProvider,
            shouldRunPlanInline: shouldRunPlanInline,
            forcePlanInline: forcePlanInline,
            preferCodeReviewRuntimeProvider: preferCodeReviewRuntimeProvider
        ) else {
            return nil
        }

        let cfg = providerFactoryConfig()
        let isMultiAdapter = runtimeProvider is CLIMultiAccountProviderAdapter
        let (backend, model, apiKey, baseURL, extraHeaders, cliAccounts): (
            MainChatProviderBackendBridge, String?, String?, String?, [String: String], [MainChatCLIAccountSnapshotBridge]
        ) = switch runtimeProvider.id {
        case "codex-cli":
            (.codexCli, cfg.codexModelOverride.isEmpty ? nil : cfg.codexModelOverride, nil, nil, [:], multiCLIAccountEnabled ? cliAccountSnapshots(for: .codex) : [])
        case "claude-cli":
            (.claudeCli, cfg.claudeModel, nil, nil, [:], multiCLIAccountEnabled ? cliAccountSnapshots(for: .claude) : [])
        case "gemini-cli":
            (.geminiCli, cfg.geminiModelOverride.isEmpty ? nil : cfg.geminiModelOverride, nil, nil, [:], multiCLIAccountEnabled ? cliAccountSnapshots(for: .gemini) : [])
        case "anthropic-api":
            (.anthropicApi, cfg.anthropicModel, cfg.anthropicApiKey, "https://api.anthropic.com/v1/messages", [:], [])
        case "google-api":
            (.googleApi, cfg.googleModel, cfg.googleApiKey, "https://generativelanguage.googleapis.com/v1beta/openai/chat/completions", [:], [])
        default:
            (.openaiApi, cfg.openaiModel, cfg.openaiApiKey, "https://api.openai.com/v1/chat/completions", [:], [])
        }

        let attachmentCapabilities = isMultiAdapter
            ? selectedProvider.attachmentCapabilities
            : runtimeProvider.attachmentCapabilities

        return MainChatRustTransportProvider(
            id: runtimeProvider.id,
            displayName: runtimeProvider.displayName,
            attachmentCapabilities: attachmentCapabilities,
            authenticated: runtimeProvider.isAuthenticated(),
            config: MainChatProviderSessionConfigBridge(
                providerId: runtimeProvider.id,
                displayName: runtimeProvider.displayName,
                backend: backend,
                workspacePath: runtimeWorkspacePaths.first?.path ?? FileManager.default.currentDirectoryPath,
                workspacePaths: runtimeWorkspacePaths.map(\.path),
                prompt: "",
                systemPrompt: nil,
                contextPrompt: nil,
                model: model,
                apiKey: apiKey,
                baseURL: baseURL,
                toolDefinitionsJson: nil,
                extraHeaders: extraHeaders,
                codexPath: cfg.codexPath.isEmpty ? nil : cfg.codexPath,
                codexSandbox: cfg.codexSandbox,
                codexAskForApproval: cfg.codexAskForApproval,
                codexModelOverride: cfg.codexModelOverride.isEmpty ? nil : cfg.codexModelOverride,
                codexReasoningEffort: cfg.codexReasoningEffort.isEmpty ? nil : cfg.codexReasoningEffort,
                codexModelProvider: cfg.codexModelProvider.isEmpty ? nil : cfg.codexModelProvider,
                codexFastMode: cfg.codexFastMode,
                codexSessionFullAccess: cfg.codexSessionFullAccess,
                codexPreferResponsesWireAPI: cfg.codexPreferResponsesWireAPI,
                claudePath: cfg.claudePath.isEmpty ? nil : cfg.claudePath,
                claudeModel: cfg.claudeModel,
                claudeAllowedTools: cfg.claudeAllowedTools,
                geminiCliPath: cfg.geminiCliPath.isEmpty ? nil : cfg.geminiCliPath,
                geminiModelOverride: cfg.geminiModelOverride.isEmpty ? nil : cfg.geminiModelOverride,
                attachments: [],
                cliAccounts: isMultiAdapter ? cliAccounts : []
            )
        )
    }
}
