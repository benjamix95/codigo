import AppKit
import CoderEngine
import SwiftUI
import UniformTypeIdentifiers

extension ChatPanelView {
    private struct FinalChatActionMetrics {
        let messageCount: Int
        let assistantCount: Int
        let userCount: Int
        let editCount: Int
        let fileChanges: [ToolTraceFileChange]
        let linesAdded: Int
        let linesRemoved: Int
    }

    private func buildFinalChatActionMetrics(for conversation: Conversation?) -> FinalChatActionMetrics {
        guard let conversation else {
            return .init(
                messageCount: 0,
                assistantCount: 0,
                userCount: 0,
                editCount: 0,
                fileChanges: [],
                linesAdded: 0,
                linesRemoved: 0
            )
        }

        var assistantCount = 0
        var userCount = 0
        var latestAssistantMessageId: UUID?
        for message in conversation.messages {
            switch message.role {
            case .assistant:
                assistantCount += 1
                latestAssistantMessageId = message.id
            case .user:
                userCount += 1
            default:
                break
            }
        }

        guard let latestAssistantMessageId else {
            return .init(
                messageCount: conversation.messages.count,
                assistantCount: assistantCount,
                userCount: userCount,
                editCount: 0,
                fileChanges: [],
                linesAdded: 0,
                linesRemoved: 0
            )
        }

        let traceEvents = toolTraceStore.events(
            conversationId: conversation.id,
            assistantMessageId: latestAssistantMessageId
        )
        guard !traceEvents.isEmpty else {
            return .init(
                messageCount: conversation.messages.count,
                assistantCount: assistantCount,
                userCount: userCount,
                editCount: 0,
                fileChanges: [],
                linesAdded: 0,
                linesRemoved: 0
            )
        }

        var editCount = 0
        for event in traceEvents where ToolTraceFileChangeMapper.isFileChangeEvent(event) {
            editCount += 1
        }

        let fileChanges = editCount > 0 ? ToolTraceFileChangeMapper.collect(from: traceEvents) : []
        var linesAdded = 0
        var linesRemoved = 0
        for change in fileChanges {
            linesAdded += max(0, change.added)
            linesRemoved += max(0, change.removed)
        }

        return .init(
            messageCount: conversation.messages.count,
            assistantCount: assistantCount,
            userCount: userCount,
            editCount: editCount,
            fileChanges: fileChanges,
            linesAdded: linesAdded,
            linesRemoved: linesRemoved
        )
    }

    @ViewBuilder
    internal var finalChatActionsBar: some View {
        let conv = chatStore.conversation(for: conversationId)
        let metrics = buildFinalChatActionMetrics(for: conv)

        VStack(spacing: 0) {
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [
                            activeModeColor.opacity(0.0),
                            activeModeColor.opacity(0.12),
                            activeModeColor.opacity(0.0),
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(height: 1)
                .padding(.horizontal, 40)

            VStack(spacing: 14) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(activeModeColor.opacity(0.8))
                        .frame(width: 6, height: 6)
                    Text("Task completed")
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .tracking(0.2)
                }

                if metrics.messageCount > 0 {
                    HStack(spacing: 16) {
                        finalStatPill(
                            icon: "bubble.left.and.bubble.right",
                            value: "\(metrics.userCount + metrics.assistantCount)",
                            label: "messages"
                        )
                        if metrics.editCount > 0 {
                            finalStatPill(
                                icon: "pencil",
                                value: "\(metrics.editCount)",
                                label: metrics.editCount == 1 ? "edit" : "edits"
                            )
                        }
                        if metrics.fileChanges.count > 0 {
                            finalStatPill(
                                icon: "doc.text",
                                value: "\(metrics.fileChanges.count)",
                                label: metrics.fileChanges.count == 1 ? "file" : "files"
                            )
                        }
                        if metrics.linesAdded > 0 || metrics.linesRemoved > 0 {
                            HStack(spacing: 4) {
                                Text("+\(metrics.linesAdded)")
                                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                                    .foregroundStyle(DesignSystem.Colors.success.opacity(0.8))
                                Text("-\(metrics.linesRemoved)")
                                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                                    .foregroundStyle(DesignSystem.Colors.error.opacity(0.8))
                            }
                        }
                    }
                }

                HStack(spacing: 6) {
                    finalChatActionButton(
                        icon: didCopyAllChat ? "checkmark" : "doc.on.doc",
                        title: didCopyAllChat ? "Copied" : "Copy all",
                        help: didCopyAllChat ? "Copied" : "Copy entire chat as Markdown",
                        foreground: didCopyAllChat ? DesignSystem.Colors.success : .secondary,
                        action: copyWholeChatToClipboard
                    )
                    finalChatActionButton(
                        icon: "arrow.down.to.line",
                        title: "Export",
                        help: "Download chat as Markdown",
                        foreground: .secondary,
                        action: downloadCurrentConversationMarkdown
                    )
                    finalChatActionButton(
                        icon: "arrow.triangle.branch",
                        title: "Fork",
                        help: "Fork this chat into a new thread",
                        foreground: .secondary,
                        action: forkCurrentConversation
                    )
                }
            }
            .padding(.vertical, 16)
        }
        .frame(maxWidth: chatColumnMaxWidth)
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.horizontal, 24)
    }

    internal func finalStatPill(icon: String, value: String, label: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.quaternary)
            Text(value)
                .font(.system(size: 10.5, weight: .bold, design: .monospaced))
                .foregroundStyle(.tertiary)
            Text(label)
                .font(.system(size: 9.5, weight: .medium))
                .foregroundStyle(.quaternary)
        }
    }
}
