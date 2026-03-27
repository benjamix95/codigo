import CoderEngine
import SwiftUI

extension ChatPanelView {
    /// Azione utente su “Planning next move”: promuove il prossimo todo canonico se possibile;
    /// se il thread è fermo e non c’era nulla da promuovere, invia un messaggio minimo al modello.
    @MainActor
    internal func performPlanningNextMoveUserAction() {
        guard let cid = conversationId, effectiveContext.hasSendableProjectContext else { return }
        let providerId = providerRegistry.selectedProviderId ?? "solocode"

        let promoted = todoStore.advanceNextCanonicalTodoIfNeeded(conversationId: cid)
        let inProgressTitle = todoStore.canonicalTodos(for: cid)
            .first(where: { $0.status == .inProgress })?
            .title
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        if promoted {
            recordTaskActivity(
                type: "plan_next_move_user",
                payload: [
                    "title": "Prossimo passo del piano",
                    "detail": inProgressTitle.isEmpty ? "Todo avviato" : inProgressTitle,
                    "status": "completed",
                ],
                providerId: providerId,
                conversationId: cid
            )
            updateSidebarTaskStatus()
            refreshMessagesSnapshot()
            return
        }

        if isLoadingForCurrentConversation {
            recordTaskActivity(
                type: "plan_next_move_user",
                payload: [
                    "title": "Piano: conferma",
                    "detail": "Nessun todo pendente da avviare ora (o già in corso).",
                    "status": "pending",
                ],
                providerId: providerId,
                conversationId: cid
            )
            updateSidebarTaskStatus()
            refreshMessagesSnapshot()
            return
        }

        let composerBusy = !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !attachedComposerAttachments.isEmpty
        if composerBusy {
            recordTaskActivity(
                type: "plan_next_move_user",
                payload: [
                    "title": "Piano: conferma",
                    "detail": "Composer occupato: scrivi il messaggio o svuota l’input per inviare un promemoria automatico.",
                    "status": "pending",
                ],
                providerId: providerId,
                conversationId: cid
            )
            updateSidebarTaskStatus()
            refreshMessagesSnapshot()
            return
        }

        recordTaskActivity(
            type: "plan_next_move_user",
            payload: [
                "title": "Piano: promemoria inviato",
                "detail": "Richiesta al modello di proseguire col piano.",
                "status": "completed",
            ],
            providerId: providerId,
            conversationId: cid
        )

        inputText =
            "Continua con il prossimo passo del piano. (Confermo da Planning next move nell’interfaccia.)"
        sendMessage()
    }
}
