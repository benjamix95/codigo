import CoderEngine
import Foundation

enum ThreadProviderSelectionService {
    static func effectiveMode(for conversation: Conversation?) -> CoderMode {
        conversation?.mode ?? .agent
    }

    static func resolveProviderId(
        conversation: Conversation?,
        currentProviderId: String?,
        registry: ProviderRegistry
    ) -> String? {
        let mode = effectiveMode(for: conversation)
        if mode == .mcpServer {
            return "claude-cli"
        }

        let preferred = normalizedProviderId(conversation?.preferredProviderId)
        if let preferred, isProviderAllowed(preferred, for: mode) {
            // Policy vincolante: se il thread ha provider preferito valido per la mode,
            // mantiene quell'identità senza fallback automatico.
            return preferred
        }

        return fallbackProviderId(
            mode: mode,
            currentProviderId: currentProviderId,
            registry: registry
        )
    }

    static func missingBoundProviderId(
        conversation: Conversation?,
        selectedProviderId: String?,
        registry: ProviderRegistry
    ) -> String? {
        let mode = effectiveMode(for: conversation)
        let preferred = normalizedProviderId(conversation?.preferredProviderId)
        let selected = normalizedProviderId(selectedProviderId)
        guard let candidate = preferred ?? selected else { return nil }
        guard isProviderAllowed(candidate, for: mode) else { return nil }
        return registry.provider(for: candidate) == nil ? candidate : nil
    }

    @MainActor
    static func persistRuntimeProviderSelection(
        chatStore: ChatStore,
        conversationId: UUID?,
        runtimeProviderId: String
    ) {
        let normalizedProviderId = normalizedProviderId(runtimeProviderId)
        guard let normalizedProviderId else { return }
        chatStore.updatePreferredProvider(
            conversationId: conversationId,
            providerId: normalizedProviderId
        )
    }

    private static func fallbackProviderId(
        mode: CoderMode,
        currentProviderId: String?,
        registry: ProviderRegistry
    ) -> String? {
        let current = normalizedProviderId(currentProviderId)
        switch mode {
        case .ide:
            if let current, isProviderAllowed(current, for: .ide), registry.provider(for: current) != nil {
                return current
            }
            return ProviderSupport.preferredIDEProvider(in: registry)

        case .agent, .codeReviewMultiSwarm, .debug, .plan, .browser:
            if let current, isProviderAllowed(current, for: mode), registry.provider(for: current) != nil {
                return current
            }
            if let healthy = ProviderSupport.firstHealthyAgentProviderId(
                preferred: nil,
                registry: registry
            ) {
                return healthy
            }
            return firstRegisteredAgentCompatibleProviderId(in: registry)

        case .mcpServer:
            return "claude-cli"
        }
    }

    private static func firstRegisteredAgentCompatibleProviderId(
        in registry: ProviderRegistry
    ) -> String? {
        let preferredOrder = [
            "codex-cli", "claude-cli", "gemini-cli",
            "openai-api", "anthropic-api", "google-api",
            "openrouter-api", "minimax-api", "grok-api",
        ]
        for id in preferredOrder where registry.provider(for: id) != nil {
            return id
        }
        return registry.providers.first(where: {
            ProviderSupport.isAgentCompatibleProvider(id: $0.id)
        })?.id
    }

    private static func normalizedProviderId(_ providerId: String?) -> String? {
        let trimmed = providerId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func isProviderAllowed(_ providerId: String, for mode: CoderMode) -> Bool {
        switch mode {
        case .ide:
            return ProviderSupport.isIDEProvider(id: providerId)
        case .agent, .codeReviewMultiSwarm, .debug, .plan, .browser:
            return ProviderSupport.isAgentCompatibleProvider(id: providerId)
        case .mcpServer:
            return providerId == "claude-cli"
        }
    }
}
