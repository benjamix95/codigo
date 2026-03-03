import Foundation
import CoderEngine
import SwiftUI

extension UsageFooterView {
    func scheduleRefresh() {
        usageRefreshTask?.cancel()
        usageRefreshTask = Task {
            try? await Task.sleep(nanoseconds: 800_000_000)
            guard !Task.isCancelled else { return }
            refreshUsage()
        }
    }

    static let contextEstimateThrottleInterval: TimeInterval = 1.5

    func scheduleContextEstimateRefresh() {
        contextEstimateWorkItem?.cancel()
        contextEstimateGeneration += 1
        let generation = contextEstimateGeneration

        let timeSinceLast = Date().timeIntervalSince(lastContextEstimateFireDate)
        let delay: TimeInterval = max(
            0,
            Self.contextEstimateThrottleInterval - timeSinceLast
        )
        let workItem = DispatchWorkItem {
            Task { @MainActor in
                guard generation == self.contextEstimateGeneration else { return }
                self.runContextEstimateRefresh(generation: generation)
            }
        }
        contextEstimateWorkItem = workItem
        Self.contextEstimateQueue.asyncAfter(
            deadline: .now() + delay,
            execute: workItem
        )
    }

    @MainActor
    private func runContextEstimateRefresh(generation: Int) {
        let model = effectiveContextModel
        let contextWindowSize = resolvedContextWindowSize(providerId: effectiveProviderId, model: model)
        guard let conversation = chatStore.conversation(for: selectedConversationId) else {
            contextEstimateSnapshot = (0, contextWindowSize, 0)
            return
        }

        let realTokens = conversation.lastInputTokens
        let promptContext = chatStore.buildPromptContext(
            conversationId: conversation.id,
            maxMessages: 20,
            maxCharsPerMessage: 2000,
            includeMemorySummary: true
        )
        let scopedContext = effectiveContext
        let openFiles = openFilesStore.openFilesForContext()
        let activeFilePath = openFilesStore.openFilePath
        let scopeMode = ContextScopeMode(rawValue: contextScopeModeRaw) ?? .auto

        let estimateWorkItem = DispatchWorkItem {
            let workspaceContext = scopedContext.toWorkspaceContext(
                openFiles: openFiles,
                activeSelection: nil,
                activeFilePath: activeFilePath,
                scopeMode: scopeMode
            )
            let prompt = workspaceContext.contextPrompt()
            let compactConversation = promptContext.trimmingCharacters(in: .whitespacesAndNewlines)
            let compactMessages: [ChatMessage]
            if compactConversation.isEmpty {
                compactMessages = []
            } else {
                compactMessages = [ChatMessage(role: .assistant, content: compactConversation)]
            }
            let estimate = ContextEstimator.estimate(
                messages: compactMessages,
                contextPrompt: prompt,
                modelContextSize: contextWindowSize,
                lastInputTokens: realTokens
            )
            Task { @MainActor in
                guard generation == self.contextEstimateGeneration else { return }
                self.lastContextEstimateFireDate = Date()
                self.contextEstimateSnapshot = (estimate.0, estimate.1, estimate.2)
            }
        }
        contextEstimateWorkItem?.cancel()
        contextEstimateWorkItem = estimateWorkItem
        Self.contextEstimateQueue.async(execute: estimateWorkItem)
    }

    func refreshUsage() {
        let pid = effectiveProviderId ?? ""
        let wd = effectiveContext.primaryPath
        Task {
            if pid == "codex-cli" {
                let path = CodexDetector.findCodexPath(
                    customPath: codexPath.isEmpty ? nil : codexPath
                ) ?? ""
                await providerUsageStore.fetchCodexUsage(
                    codexPath: path,
                    workingDirectory: wd,
                    environmentOverride: usageEnvironmentOverride(for: .codex)
                )
            } else if pid == "claude-cli" {
                let path = ClaudeDetector.findClaudePath(
                    customPath: claudePath.isEmpty ? nil : claudePath
                ) ?? ""
                await providerUsageStore.fetchClaudeUsage(
                    claudePath: path,
                    workingDirectory: wd,
                    environmentOverride: usageEnvironmentOverride(for: .claude),
                    anthropicAdminApiKey: anthropicAdminApiKey
                )
            } else if pid == "gemini-cli" {
                let path = GeminiDetector.findGeminiPath(
                    customPath: geminiCliPath.isEmpty ? nil : geminiCliPath
                ) ?? ""
                await providerUsageStore.fetchGeminiUsage(
                    geminiPath: path,
                    workingDirectory: wd,
                    environmentOverride: usageEnvironmentOverride(for: .gemini)
                )
            }
        }
    }

    func usageEnvironmentOverride(for provider: CLIProviderKind) -> [String: String]? {
        guard let account = activeAccount(for: provider) else { return nil }
        let secret = cliSecretsStore.secret(for: account.id)
        let env = CLIProfileProvisioner.environmentOverrides(
            provider: provider,
            profilePath: account.profilePath,
            secret: secret
        )
        return env.isEmpty ? nil : env
    }

    func activeAccount(for provider: CLIProviderKind) -> CLIAccount? {
        if let active = cliAccountRouter.activeAccount(for: provider) {
            return active
        }
        return cliAccountsStore.accounts(for: provider).first(where: \.isEnabled)
    }
}
