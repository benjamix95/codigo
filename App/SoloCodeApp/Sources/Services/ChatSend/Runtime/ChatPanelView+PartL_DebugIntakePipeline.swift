import CoderEngine
import SwiftUI

extension ChatPanelView {
    /// Prima richiesta in debug (nessuna sessione attiva): abilita il routing verso `executeDebugPipelineIntent(.startSession)` — slice intake deterministico.
    internal func shouldOfferDeterministicDebugIntakePipeline(
        isPlanModeRequested: Bool,
        targetConversationId: UUID,
        userText: String,
        hasComposerAttachments: Bool
    ) -> Bool {
        guard coderMode == .debug || showDebugPanel else { return false }
        guard !isPlanModeRequested else { return false }
        guard !hasComposerAttachments else { return false }
        guard !userText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        guard !debugStore.phase.isActive else { return false }
        guard !pipelineIntegrationService.isRunning(for: targetConversationId) else { return false }
        return true
    }
}
