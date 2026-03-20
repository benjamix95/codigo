import AppKit
import CoderEngine
import SwiftUI
import UniformTypeIdentifiers

extension ChatPanelView {
    @discardableResult
    internal func handleAutoCodeReviewLaunchIfNeeded(
        _ autoCodeReviewRequest: AutoCodeReviewRequest,
        displayedInput: String,
        targetConversationId: UUID
    ) -> Bool {
        guard autoCodeReviewRequest.prefersCodeReviewRuntimeProvider else { return false }

        let storedAttachments = attachedComposerAttachments.map { attachment in
            ChatAttachment(
                kind: attachment.kind,
                originalName: attachment.originalName,
                mimeType: attachment.mimeType,
                localPath: attachment.url.path(percentEncoded: false),
                sizeBytes: attachment.sizeBytes
            )
        }
        let imagePaths = storedAttachments
            .filter { $0.kind == .image }
            .map(\.localPath)

        inputText = ""
        attachedComposerAttachments = []

        let storedContent = displayedInput.isEmpty
            ? (storedAttachments.isEmpty ? "Review request" : "[Attached files]")
            : displayedInput
        chatStore.addMessage(
            ChatMessage(
                role: .user,
                content: storedContent,
                isStreaming: false,
                imagePaths: imagePaths.isEmpty ? nil : imagePaths,
                attachments: storedAttachments.isEmpty ? nil : storedAttachments
            ),
            to: targetConversationId
        )

        if coderMode != .codeReviewMultiSwarm {
            selectMode(.codeReviewMultiSwarm)
        }
        launchCodeReviewPanelRequest(
            prompt: autoCodeReviewRequest.prompt,
            scope: autoCodeReviewRequest.scopeTarget ?? .uncommitted,
            modes: autoCodeReviewRequest.selectedModes,
            invocationLabel: "Findings-first review"
        )
        return true
    }
}
