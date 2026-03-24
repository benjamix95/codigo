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
            coderMode: coderMode,
            shouldRunPlanInline: shouldRunPlanInline,
            forcePlanInline: forcePlanInline,
            preferCodeReviewRuntimeProvider: preferCodeReviewRuntimeProvider,
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
            codexCLIAccounts: providerSettings.multiCLIAccountEnabled ? cliAccountSnapshots(for: .codex) : [],
            claudeCLIAccounts: providerSettings.multiCLIAccountEnabled ? cliAccountSnapshots(for: .claude) : [],
            geminiCLIAccounts: providerSettings.multiCLIAccountEnabled ? cliAccountSnapshots(for: .gemini) : []
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
        let cliAccounts = providerSettings.multiCLIAccountEnabled
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
                claudeMcpServerPath: Self.resolveCoderideMCPServerPath(),
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

    /// Resolves the path to the actual Rust MCP server binary so it can
    /// be passed to Claude CLI for MCP integration.  Resolution order:
    /// 1. Env override `SOLOCODE_MCP_SERVER_PATH`
    /// 2. `coderide-mcp-server-rust` sibling in app bundle (Rust binary)
    /// 3. `Native/target/{debug,release}/coderide-mcp-server-rust` (cargo build)
    ///
    /// Note: the Swift wrapper `coderide-mcp-server` is NOT used because
    /// it requires the Rust binary as a sibling which may not be bundled.
    /// We resolve the Rust binary directly to avoid the wrapper indirection.
    static func resolveCoderideMCPServerPath() -> String? {
        let fm = FileManager.default
        let env = ProcessInfo.processInfo.environment

        if let override = env["SOLOCODE_MCP_SERVER_PATH"]?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !override.isEmpty,
           fm.isExecutableFile(atPath: override) {
            return override
        }

        let mainExe = URL(fileURLWithPath: CommandLine.arguments[0])
        let bundleDir = mainExe.deletingLastPathComponent()

        // Prefer the Rust binary directly (avoids Swift wrapper indirection)
        let rustBundleCandidate = bundleDir
            .appendingPathComponent("coderide-mcp-server-rust")
        if fm.isExecutableFile(atPath: rustBundleCandidate.path) {
            return rustBundleCandidate.path
        }

        // Development: Rust cargo output
        let sourceFile = URL(fileURLWithPath: #filePath)
        var dir = sourceFile.deletingLastPathComponent()
        while dir.path != "/" {
            let workspace = dir.appendingPathComponent("Solo Code.xcworkspace")
            let cargo = dir.appendingPathComponent("Native/Cargo.toml")
            if fm.fileExists(atPath: workspace.path), fm.fileExists(atPath: cargo.path) {
                for variant in ["debug", "release"] {
                    let candidate = dir
                        .appendingPathComponent("Native/target/\(variant)/coderide-mcp-server-rust")
                    if fm.isExecutableFile(atPath: candidate.path) {
                        return candidate.path
                    }
                }
                break
            }
            dir.deleteLastPathComponent()
        }

        // Last resort: Swift wrapper (only works if Rust binary is co-located)
        let swiftWrapper = bundleDir.appendingPathComponent("coderide-mcp-server")
        if fm.isExecutableFile(atPath: swiftWrapper.path) {
            return swiftWrapper.path
        }

        return nil
    }
}
