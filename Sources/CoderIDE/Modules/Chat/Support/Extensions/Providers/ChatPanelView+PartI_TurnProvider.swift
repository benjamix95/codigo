import AppKit
import CoderEngine
import SwiftUI
import UniformTypeIdentifiers

extension ChatPanelView {
    internal func resolvedTurnProviderId(
        for conversationId: UUID?,
        fallback: String = "unknown"
    ) -> String {
        guard let conversationId else {
            return providerRegistry.selectedProviderId ?? fallback
        }

        if let activeProviderId = activeToolTraceTurnsByConversation[conversationId]?.providerId,
           !activeProviderId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return activeProviderId
        }

        if let runtimeProviderId = pipelineIntegrationService.providerId(for: conversationId),
           !runtimeProviderId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return runtimeProviderId
        }

        if let assistantProviderId = chatStore.conversation(for: conversationId)?
            .messages
            .last(where: { $0.role == .assistant })?
            .turnMetadata?
            .providerId,
           !assistantProviderId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return assistantProviderId
        }

        if let preferredProviderId = chatStore.conversation(for: conversationId)?.preferredProviderId,
           !preferredProviderId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return preferredProviderId
        }

        return providerRegistry.selectedProviderId ?? fallback
    }
}
