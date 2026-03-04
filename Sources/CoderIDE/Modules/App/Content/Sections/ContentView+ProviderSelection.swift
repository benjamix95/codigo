import CoderEngine
import SwiftUI

extension ContentView {
    func syncThreadBoundProviderSelection(for conversationId: UUID?) {
        let conversation = chatStore.conversation(for: conversationId)
        guard let resolved = ThreadProviderSelectionService.resolveProviderId(
            conversation: conversation,
            currentProviderId: providerRegistry.selectedProviderId,
            registry: providerRegistry
        ) else {
            return
        }
        if providerRegistry.selectedProviderId != resolved {
            providerRegistry.selectedProviderId = resolved
        }
    }
}
