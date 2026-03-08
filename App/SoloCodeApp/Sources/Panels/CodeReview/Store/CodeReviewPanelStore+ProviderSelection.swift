import CoderEngine
import Foundation

struct ReviewPanelProviderOption: Identifiable, Equatable {
    let id: String
    let displayName: String
    let modelName: String
    let iconName: String
    let isAuthenticated: Bool
}

extension CodeReviewPanelStore {
    var usesAutomaticProviderSelection: Bool {
        selectedProviderOverrideId == nil
    }

    var effectivePanelProviderId: String? {
        selectedProviderOverrideId
            ?? providerRegistry.selectedProviderId
            ?? providerRegistry.providers.first(where: {
                ProviderSupport.isAgentCompatibleProvider(id: $0.id)
            })?.id
    }

    var effectivePanelProvider: (any LLMProvider)? {
        guard let effectivePanelProviderId else { return providerRegistry.selectedProvider }
        return providerRegistry.provider(for: effectivePanelProviderId)
            ?? providerRegistry.selectedProvider
    }

    var effectivePanelProviderLabel: String {
        effectivePanelProviderOption?.modelName ?? "No provider"
    }

    var effectivePanelProviderName: String {
        effectivePanelProviderOption?.displayName ?? "Auto"
    }

    var effectivePanelProviderIconName: String {
        effectivePanelProviderOption?.iconName ?? "bolt.circle"
    }

    var effectivePanelProviderOption: ReviewPanelProviderOption? {
        guard let effectivePanelProviderId else { return nil }
        return providerOption(for: effectivePanelProviderId)
    }

    var panelRunBackendId: String? {
        effectivePanelProviderId
    }

    var panelProviderOptions: [ReviewPanelProviderOption] {
        providerRegistry.providers
            .filter { ProviderSupport.isAgentCompatibleProvider(id: $0.id) }
            .map { provider in
                ReviewPanelProviderOption(
                    id: provider.id,
                    displayName: provider.displayName,
                    modelName: providerModelName(for: provider.id),
                    iconName: providerIconName(for: provider.id),
                    isAuthenticated: provider.isAuthenticated()
                )
            }
            .sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
    }

    func setPanelProviderOverride(_ providerId: String?) {
        guard let providerId, !providerId.isEmpty else {
            selectedProviderOverrideId = nil
            return
        }
        guard panelProviderOptions.contains(where: { $0.id == providerId }) else { return }
        selectedProviderOverrideId = providerId
    }

    private func providerOption(for id: String) -> ReviewPanelProviderOption? {
        panelProviderOptions.first(where: { $0.id == id })
    }

    private func providerModelName(for id: String) -> String {
        let config = providerFactoryConfigBuilder()
        switch id {
        case "openai-api": return config.openaiModel
        case "anthropic-api": return config.anthropicModel
        case "google-api": return config.googleModel
        case "openrouter-api": return config.openrouterModel
        case "minimax-api": return config.minimaxModel
        case "grok-api": return config.grokModel
        case "codex-cli": return config.codexModelOverride.nilIfEmpty ?? "codex"
        case "claude-cli": return config.claudeModel
        case "gemini-cli": return config.geminiModelOverride.nilIfEmpty ?? "gemini"
        default: return id
        }
    }

    private func providerIconName(for id: String) -> String {
        switch id {
        case "codex-cli": return "sparkles.rectangle.stack"
        case "claude-cli": return "message.badge.waveform"
        case "gemini-cli": return "diamond"
        case "openai-api": return "sparkles"
        case "anthropic-api": return "text.quote"
        case "google-api": return "globe"
        case "openrouter-api": return "point.3.connected.trianglepath.dotted"
        case "minimax-api": return "m.circle"
        case "grok-api": return "bolt"
        default: return "bolt.circle"
        }
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
