import AppKit
import CoderEngine
import SwiftUI
import UniformTypeIdentifiers

extension ChatPanelView {
    @ViewBuilder
    internal var finalChatActionsBar: some View {
        let conv = chatStore.conversation(for: conversationId)
        let messageCount = conv?.messages.count ?? 0
        let assistantCount = conv?.messages.filter { $0.role == .assistant }.count ?? 0
        let userCount = conv?.messages.filter { $0.role == .user }.count ?? 0
        let latestAssistantMessageId = conv?.messages.last(where: { $0.role == .assistant })?.id
        let traceEvents = {
            guard let c = conv, let assistantId = latestAssistantMessageId else { return [ToolTraceEvent]() }
            return toolTraceStore.events(conversationId: c.id, assistantMessageId: assistantId)
        }()
        let editCount = traceEvents.filter { ToolTraceFileChangeMapper.isFileChangeEvent($0) }.count
        let fileChanges = ToolTraceFileChangeMapper.collect(from: traceEvents)
        let linesAdded = fileChanges.reduce(0) { $0 + max(0, $1.added) }
        let linesRemoved = fileChanges.reduce(0) { $0 + max(0, $1.removed) }

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

                if messageCount > 0 {
                    HStack(spacing: 16) {
                        finalStatPill(
                            icon: "bubble.left.and.bubble.right",
                            value: "\(userCount + assistantCount)",
                            label: "messages"
                        )
                        if editCount > 0 {
                            finalStatPill(
                                icon: "pencil",
                                value: "\(editCount)",
                                label: editCount == 1 ? "edit" : "edits"
                            )
                        }
                        if fileChanges.count > 0 {
                            finalStatPill(
                                icon: "doc.text",
                                value: "\(fileChanges.count)",
                                label: fileChanges.count == 1 ? "file" : "files"
                            )
                        }
                        if linesAdded > 0 || linesRemoved > 0 {
                            HStack(spacing: 4) {
                                Text("+\(linesAdded)")
                                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                                    .foregroundStyle(DesignSystem.Colors.success.opacity(0.8))
                                Text("-\(linesRemoved)")
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
