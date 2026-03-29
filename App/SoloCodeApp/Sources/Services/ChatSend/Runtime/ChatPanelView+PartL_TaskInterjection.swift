import Foundation

extension ChatPanelView {
    internal func sendFollowUpDuringActiveTask() {
        guard isLoadingForCurrentConversation else {
            sendMessage()
            return
        }

        let targetConversationId = conversationId
        lastTaskEndedByManualStop = false
        interruptTask(for: targetConversationId, source: "composer_follow_up_send")
        sendMessage()
    }
}
