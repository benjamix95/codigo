import AppKit
import CoderEngine
import QuickLookUI
import SwiftUI

extension MessageRow {

    // MARK: - Message Divider

    func messageDivider() -> some View {
        Rectangle()
            .fill(
                LinearGradient(
                    colors: [
                        Color.primary.opacity(0.0),
                        Color.primary.opacity(0.06),
                        Color.primary.opacity(0.06),
                        Color.primary.opacity(0.0),
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .frame(height: 0.5)
            .frame(maxWidth: rowMaxWidth)
            .padding(.bottom, 20)
    }

    // MARK: - User Header

    func userHeader() -> some View {
        HStack(spacing: 6) {
            Spacer(minLength: 0)
            if canRewind {
                Button {
                    onRestoreCheckpoint?()
                } label: {
                    Image(systemName: "arrow.uturn.backward")
                        .font(.system(size: 9, weight: .semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.quaternary)
                .help(
                    hasCheckpointForRestore
                        ? "Restore chat and files from this point"
                        : "Restore chat from this point"
                )
                .accessibilityLabel("Restore checkpoint")
            }
            Text("You")
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(.tertiary)
                .tracking(0.3)
        }
        .padding(.trailing, 10)
        .padding(.bottom, 5)
    }

    // MARK: - Assistant Header

    func assistantHeader() -> some View {
        HStack(spacing: 5) {
            Circle()
                .fill(modeColor.opacity(0.6))
                .frame(width: 5.5, height: 5.5)
            Spacer(minLength: 0)
        }
        .padding(.leading, 2)
        .padding(.bottom, 5)
    }

    // MARK: - Message Content

    func messageContent() -> some View {
        VStack(alignment: isUser ? .trailing : .leading, spacing: 8) {
            if isUser {
                if let attachments = message.attachments, !attachments.isEmpty {
                    userAttachmentsRow(attachments: attachments)
                } else if let paths = message.imagePaths, !paths.isEmpty {
                    userMessageImagesRow(paths: paths)
                }
            }
            if isUser {
                if isEditingInline {
                    inlineEditBubble
                } else {
                    MarkdownContentView(
                        content: message.content,
                        context: context,
                        onFileClicked: onFileClicked,
                        textAlignment: .leading,
                        isStreaming: false,
                        aggressiveSanitization: false,
                        fillWidth: false,
                        normalizeDisplayLayout: false
                    )
                    .padding(.horizontal, 18)
                    .padding(.vertical, 13)
                    .background(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .fill(DesignSystem.Colors.chatUserBubbleFill)
                    )
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: contentMaxWidth, alignment: .trailing)
                }
                if shouldShowCopyAction {
                    messageActionsRow()
                }
            } else {
                let providerId = message.turnMetadata?.providerId ?? ""
                let shouldRenderInlineReasoning =
                    ChatReasoningPresentationPolicy.mode(
                        providerId: providerId,
                        separateCodexThinkingMessagesEnabled: false
                    ) == .inline
                let reasoningBlocks: [ReasoningBlock] = {
                    guard shouldRenderInlineReasoning else { return [] }
                    if isActivelyStreaming, !streamingReasoningBlocks.isEmpty {
                        return streamingReasoningBlocks
                    }
                    if let text = isActivelyStreaming ? streamingReasoningText : message.reasoningText,
                       !text.isEmpty {
                        return [ReasoningBlock(id: "single", text: text)]
                    }
                    return []
                }()
                if !reasoningBlocks.isEmpty {
                    ThinkingBlocksView(blocks: reasoningBlocks, isLiveStreaming: isActivelyStreaming)
                    // Visual divider between reasoning and response
                    Rectangle()
                        .fill(Color.primary.opacity(0.06))
                        .frame(height: 0.5)
                        .padding(.vertical, 8)
                }
                MarkdownContentView(
                    content: message.content,
                    context: context,
                    onFileClicked: onFileClicked,
                    textAlignment: .leading,
                    isStreaming: isActivelyStreaming
                )
                .frame(maxWidth: contentMaxWidth, alignment: .leading)
                .padding(.vertical, 4)
                if shouldShowStreamingBar { streamingBar() }
                if shouldShowCopyAction {
                    messageActionsRow()
                }
            }
        }
    }

    @ViewBuilder
    func userAttachmentsRow(attachments: [ChatAttachment]) -> some View {
        let imagePaths = attachments
            .filter { $0.kind == .image }
            .map(\.localPath)
        if !imagePaths.isEmpty {
            userMessageImagesRow(paths: imagePaths)
        }
        let nonImage = attachments.filter { $0.kind != .image }
        if !nonImage.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(nonImage) { attachment in
                        HStack(spacing: 6) {
                            Image(systemName: attachment.kind == .document ? "doc.text" : "paperclip")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(.secondary)
                            Text(attachment.originalName)
                                .font(.system(size: 10.5, weight: .medium))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                            if let size = attachment.sizeBytes {
                                Text(ByteCountFormatter.string(fromByteCount: size, countStyle: .file))
                                    .font(.system(size: 9.5, weight: .regular))
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        .padding(.horizontal, 9)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.45))
                        )
                    }
                }
            }
            .fixedSize(horizontal: true, vertical: false)
            .padding(.bottom, 4)
        }
    }

    // MARK: - Streaming Bar

    func messageActionsRow() -> some View {
        HStack(spacing: 2) {
            Button {
                copyMessageToClipboard()
            } label: {
                Image(systemName: didCopyMessage ? "checkmark" : "doc.on.doc")
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundStyle(didCopyMessage ? DesignSystem.Colors.success : DesignSystem.Colors.textTertiary)
                    .frame(width: 24, height: 20)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(didCopyMessage ? "Copied" : "Copy message")
            .accessibilityLabel(didCopyMessage ? "Copied" : "Copy message")
            .animation(.easeOut(duration: 0.15), value: didCopyMessage)

            if onEdit != nil {
                Button {
                    editText = message.content
                    isEditingInline = true
                } label: {
                    Image(systemName: isEditingInline ? "xmark" : "pencil")
                        .font(.system(size: 9.5, weight: .medium))
                        .foregroundStyle(isEditingInline ? DesignSystem.Colors.error : DesignSystem.Colors.textTertiary)
                        .frame(width: 24, height: 20)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(isEditingInline ? "Cancel edit" : "Edit message")
                .accessibilityLabel(isEditingInline ? "Cancel edit" : "Edit message")
            }

            if let onReply {
                Button(action: onReply) {
                    Image(systemName: "arrowshape.turn.up.left")
                        .font(.system(size: 9.5, weight: .medium))
                        .foregroundStyle(.tertiary)
                        .frame(width: 24, height: 20)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Reply")
                .accessibilityLabel("Reply")
            }

            if let onDelete {
                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .font(.system(size: 9.5, weight: .medium))
                        .foregroundStyle(.tertiary)
                        .frame(width: 24, height: 20)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Delete message")
                .accessibilityLabel("Delete message")
            }
        }
        .opacity((isHovered || isActionsHovered) ? 1 : 0)
        .animation(.easeOut(duration: 0.12), value: isHovered)
        .frame(maxWidth: .infinity, alignment: isUser ? .trailing : .leading)
        .padding(.trailing, isUser ? 6 : 0)
        .padding(.leading, isUser ? 0 : 2)
        .contentShape(Rectangle())
        .onHover { hovering in
            if hovering {
                hoverTask?.cancel()
                isActionsHovered = true
                isHovered = true
            } else {
                isActionsHovered = false
                hoverTask?.cancel()
                hoverTask = Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 160_000_000)
                    guard !Task.isCancelled else { return }
                    if !isActionsHovered {
                        isHovered = false
                    }
                }
            }
        }
    }

    // MARK: - Inline Edit Bubble

    private var inlineEditBubble: some View {
        VStack(alignment: .trailing, spacing: 4) {
            InlineEditTextView(
                text: $editText,
                onSubmit: {
                    let trimmed = editText.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty else { return }
                    isEditingInline = false
                    onEdit?(trimmed)
                },
                onCancel: {
                    isEditingInline = false
                }
            )
            .frame(minHeight: 36, maxHeight: 200)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 18)
            .padding(.vertical, 13)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(DesignSystem.Colors.chatUserBubbleFill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(DesignSystem.Colors.info.opacity(0.5), lineWidth: 1.5)
            )
            .frame(maxWidth: contentMaxWidth, alignment: .trailing)

            Text("Enter to send · Esc to cancel")
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(DesignSystem.Colors.textQuaternary)
        }
    }

    func copyMessageToClipboard() {
        let trimmed = message.content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(message.content, forType: .string)
        didCopyMessage = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            didCopyMessage = false
        }
    }

    static func shouldShowCopyAction(for message: ChatMessage) -> Bool {
        let trimmed = message.content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        switch message.role {
        case .user:
            return true
        case .assistant:
            return !message.isStreaming
        }
    }

    func streamingBar() -> some View {
        let status = streamingStatusText.isEmpty ? "Thinking" : streamingStatusText
        return HStack(spacing: 6) {
            Text(status)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
                .textShimmer(active: true)
            if status != "Planning next move", status != "Thinking",
               let detail = streamingDetailText, !detail.isEmpty {
                Text("·")
                    .foregroundStyle(.secondary)
                Text(detail)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .textShimmer(active: true)
            }
            Spacer()
        }
        .padding(.top, 2)
    }

    // MARK: - User Images

    @ViewBuilder
    func userMessageImagesRow(paths: [String]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(paths, id: \.self) { path in
                    CachedThumbnailView(
                        path: path,
                        width: userImageThumbWidth,
                        height: userImageThumbHeight
                    )
                }
            }
        }
        .fixedSize(horizontal: true, vertical: false)
        .padding(.bottom, 4)
    }
}
