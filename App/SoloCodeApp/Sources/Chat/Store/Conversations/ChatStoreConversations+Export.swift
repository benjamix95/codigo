import Foundation
import CoderEngine

extension ChatStore {
    func exportConversationMarkdown(conversationId: UUID?) -> String? {
        guard let conversation = conversation(for: conversationId) else { return nil }

        let title = conversation.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedTitle = title.isEmpty ? "Chat" : title
        let formatter = ISO8601DateFormatter()

        var lines: [String] = []
        lines.append("# \(resolvedTitle)")
        lines.append("Exported: \(formatter.string(from: Date()))")
        lines.append("")

        for message in conversation.messages {
            let content = message.exportMarkdownContent.trimmingCharacters(in: .whitespacesAndNewlines)
            let nonImageAttachments = (message.attachments ?? []).filter { $0.kind != .image }
            if content.isEmpty, nonImageAttachments.isEmpty { continue }

            lines.append("## \(message.role == .user ? "You" : "Assistant")")
            if !content.isEmpty {
                lines.append(content)
            }

            if !nonImageAttachments.isEmpty {
                if !content.isEmpty {
                    lines.append("")
                }
                lines.append("Attachments:")
                for attachment in nonImageAttachments {
                    lines.append("- \(attachment.originalName)")
                }
            }

            lines.append("")
        }

        return lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines) + "\n"
    }

    func defaultMarkdownFilename(for conversationId: UUID?) -> String {
        let rawTitle = conversation(for: conversationId)?.title ?? ""
        let sanitized = Self.sanitizeFilenameComponent(rawTitle)
        return "\(sanitized).md"
    }

    @discardableResult
    func forkConversation(from conversationId: UUID?) -> UUID? {
        guard let source = conversation(for: conversationId) else { return nil }

        let baseTitle = source.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedBaseTitle = baseTitle.isEmpty ? "Chat" : baseTitle

        let forkedMessages = source.messages.map { message in
            ChatMessage(
                id: UUID(),
                role: message.role,
                content: message.content,
                primaryTextSnapshot: message.primaryTextSnapshot,
                blocks: message.blocks,
                turnMetadata: message.turnMetadata,
                isStreaming: false,
                imagePaths: message.imagePaths,
                attachments: message.attachments,
                planAttachment: nil
            )
        }

        let forkedConversation = Conversation(
            threadRootConversationId: source.threadRootConversationId,
            title: "\(resolvedBaseTitle) (Fork)",
            messages: forkedMessages,
            createdAt: .now,
            contextId: source.contextId,
            contextFolderPath: source.contextFolderPath,
            mode: source.mode,
            preferredProviderId: source.preferredProviderId,
            isArchived: false,
            isPinned: false,
            isFavorite: false,
            workspaceId: source.workspaceId,
            adHocFolderPaths: source.adHocFolderPaths,
            checkpoints: []
        )

        conversations.append(forkedConversation)
        saveConversations()
        return forkedConversation.id
    }

    private static func sanitizeFilenameComponent(_ raw: String) -> String {
        var value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.isEmpty { return "chat" }

        value = value.replacingOccurrences(
            of: #"[\\/:*?"<>|]"#,
            with: "-",
            options: .regularExpression
        )
        value = value.replacingOccurrences(
            of: #"\s+"#,
            with: " ",
            options: .regularExpression
        )
        value = value.replacingOccurrences(of: " ", with: "_")
        value = value.trimmingCharacters(in: CharacterSet(charactersIn: "._-"))
        if value.isEmpty { return "chat" }
        return String(value.prefix(80))
    }
}
