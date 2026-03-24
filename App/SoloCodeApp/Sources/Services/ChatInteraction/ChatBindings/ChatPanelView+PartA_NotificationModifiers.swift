import AppKit
import SwiftUI
import UniformTypeIdentifiers

extension ChatPanelView {
    internal func applyNotificationAndImporterModifiers<Content: View>(to content: Content) -> some View {
        content
            .sheet(isPresented: $showSwarmHelp) { AgentSwarmHelpView() }
            .fileImporter(
                isPresented: $isSelectingImage,
                allowedContentTypes: [.item],
                allowsMultipleSelection: true
            ) { result in
                handleAttachmentSelection(result: result)
            }
            .onAppear {
                installPasteMonitor()
            }
            .onDisappear {
                composerAutoFocusTask?.cancel()
                composerAutoFocusTask = nil
                toolRuntimeSyncTask?.cancel()
                toolRuntimeSyncTask = nil
                taskFlushTask?.cancel()
                taskFlushTask = nil
                streamThrottleTask?.cancel()
                streamThrottleTask = nil
                planStreamThrottleTask?.cancel()
                planStreamThrottleTask = nil
                cancelFallbackTurnStartEvent()
                autoScrollWorkItem?.cancel()
                composerTimerAutoHideTask?.cancel()
                composerTimerAutoHideTask = nil
                voiceInputController.cancel()
                flushPendingTaskActivities()
                removePasteMonitor()
                for (_, task) in activeRunTaskByConversation {
                    task.cancel()
                }
                activeRunTaskByConversation.removeAll()
                activeRunTokenByConversation.removeAll()
            }
            .onReceive(NotificationCenter.default.publisher(for: Self.attachmentPastedNotification)) {
                notification in
                if let attachments = notification.userInfo?["attachments"] as? [ComposerAttachment] {
                    appendComposerAttachments(attachments)
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: Self.threadSearchAskAINotification)) {
                notification in
                guard let prompt = notification.userInfo?["prompt"] as? String else { return }
                if selectedConversationId == nil {
                    selectedConversationId = chatStore.createConversation(
                        contextId: nil,
                        contextFolderPath: nil,
                        mode: coderMode
                    )
                }
                inputText = prompt
                sendMessage()
            }
            .onReceive(NotificationCenter.default.publisher(for: Self.threadDeletionRequestedNotification)) {
                notification in
                let rawConversationId =
                    notification.userInfo?["conversationId"] as? String
                    ?? notification.userInfo?["conversation_id"] as? String
                guard let rawConversationId,
                      let conversationId = UUID(uuidString: rawConversationId) else { return }
                interruptTask(for: conversationId)
            }
    }
}
