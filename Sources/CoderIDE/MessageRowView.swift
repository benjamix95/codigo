import AppKit
import CoderEngine
import SwiftUI

// MARK: - Message Row

struct MessageRow: View {
    let message: ChatMessage
    let context: ProjectContext?
    let modeColor: Color
    let isActuallyLoading: Bool
    let streamingStatusText: String
    let streamingDetailText: String?
    var streamingReasoningText: String? = nil
    var showStreamingBar: Bool = true
    let onFileClicked: (String) -> Void
    var onRestoreCheckpoint: (() -> Void)? = nil
    var canRewind: Bool = false
    var hasCheckpointForRestore: Bool = false
    var showTopDivider: Bool = false
    @State private var isHovered = false
    @State private var didCopyMessage = false
    private let userRowMaxWidth: CGFloat = 620
    private let assistantRowMaxWidth: CGFloat = 920
    private let userImageThumbWidth: CGFloat = 52
    private let userImageThumbHeight: CGFloat = 34

    private var isActivelyStreaming: Bool {
        message.isStreaming && isActuallyLoading
    }

    private var shouldShowStreamingBar: Bool {
        showStreamingBar && isActivelyStreaming
    }

    private var isUser: Bool { message.role == .user }
    private var rowMaxWidth: CGFloat { isUser ? userRowMaxWidth : assistantRowMaxWidth }
    private var contentMaxWidth: CGFloat { isUser ? 560 : 860 }

    var body: some View {
        VStack(alignment: isUser ? .trailing : .leading, spacing: 0) {
            if showTopDivider {
                messageDivider
            }
            if isUser {
                userHeader
            } else {
                assistantHeader
            }
            HStack(alignment: .top, spacing: 0) {
                if isUser { Spacer(minLength: 0) }
                messageContent
                if !isUser { Spacer(minLength: 0) }
            }
        }
        .padding(.horizontal, 4)
        .frame(maxWidth: .infinity, alignment: isUser ? .trailing : .leading)
        .frame(maxWidth: rowMaxWidth, alignment: isUser ? .trailing : .leading)
        .fixedSize(horizontal: false, vertical: true)
        .onHover { isHovered = $0 }
    }

    // MARK: - Message Divider

    private var messageDivider: some View {
        Rectangle()
            .fill(
                LinearGradient(
                    colors: [
                        Color.clear,
                        Color.primary.opacity(0.05),
                        Color.primary.opacity(0.05),
                        Color.clear,
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .frame(height: 0.5)
            .frame(maxWidth: rowMaxWidth)
            .padding(.bottom, 18)
    }

    // MARK: - User Header

    private var userHeader: some View {
        HStack(spacing: 6) {
            Spacer(minLength: 0)
            Text("You")
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(.tertiary)
            if canRewind {
                Button {
                    onRestoreCheckpoint?()
                } label: {
                    Image(systemName: "arrow.uturn.backward")
                        .font(.system(size: 9.5, weight: .semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.tertiary)
                .help(
                    hasCheckpointForRestore
                        ? "Restore chat and files from this point"
                        : "Restore chat from this point"
                )
                .accessibilityLabel("Restore checkpoint")
            }
        }
        .padding(.trailing, 14)
        .padding(.bottom, 5)
    }

    // MARK: - Assistant Header

    private var assistantHeader: some View {
        HStack(spacing: 5) {
            Image(systemName: "sparkles")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(modeColor.opacity(0.55))
            Text("Codigo")
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(.tertiary)
            Spacer(minLength: 0)
        }
        .padding(.leading, 2)
        .padding(.bottom, 5)
    }

    // MARK: - Message Content

    private var messageContent: some View {
        VStack(alignment: isUser ? .trailing : .leading, spacing: 6) {
            if isUser {
                if let attachments = message.attachments, !attachments.isEmpty {
                    userAttachmentsRow(attachments: attachments)
                } else if let paths = message.imagePaths, !paths.isEmpty {
                    userMessageImagesRow(paths: paths)
                }
            }
            if isUser {
                ClickableMessageContent(
                    content: message.content,
                    context: context,
                    onFileClicked: onFileClicked,
                    textAlignment: .leading
                )
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(DesignSystem.Colors.chatUserBubbleFill)
                )
                .frame(maxWidth: contentMaxWidth, alignment: .trailing)
                if !message.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    userActionsRow
                }
            } else {
                // Thinking block
                if isActivelyStreaming,
                   let reasoning = streamingReasoningText, !reasoning.isEmpty
                {
                    ThinkingBlockView(text: reasoning)
                        .padding(.bottom, 8)
                }
                // Main content
                MarkdownContentView(
                    content: message.content,
                    context: context,
                    onFileClicked: onFileClicked,
                    textAlignment: .leading,
                    isStreaming: isActivelyStreaming
                )
                .frame(maxWidth: contentMaxWidth, alignment: .leading)
                .padding(.vertical, 4)
                // Streaming bar
                if shouldShowStreamingBar { streamingBar }
            }
        }
    }

    @ViewBuilder
    private func userAttachmentsRow(attachments: [ChatAttachment]) -> some View {
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

    private var userActionsRow: some View {
        HStack(spacing: 6) {
            Button {
                copyUserMessageToClipboard()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: didCopyMessage ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 9.5, weight: .semibold))
                    Text(didCopyMessage ? "Copied" : "Copy")
                        .font(.system(size: 10, weight: .semibold))
                }
                .foregroundStyle(didCopyMessage ? DesignSystem.Colors.success : .secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    Capsule()
                        .fill(Color(nsColor: .controlBackgroundColor).opacity(0.55))
                )
            }
            .buttonStyle(.plain)
            .help("Copia il messaggio")
            .opacity((isHovered || didCopyMessage) ? 1 : 0.72)
            .animation(.easeOut(duration: 0.15), value: didCopyMessage)
        }
        .padding(.trailing, 6)
    }

    private func copyUserMessageToClipboard() {
        let trimmed = message.content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(message.content, forType: .string)
        didCopyMessage = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            didCopyMessage = false
        }
    }

    private var streamingBar: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 0) {
                Text(streamingStatusText.isEmpty ? "Thinking" : streamingStatusText)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                    .clipShape(Rectangle())
                    .overlay {
                        ActivityShimmerTrail()
                            .allowsHitTesting(false)
                    }
                Spacer()
            }
            if let detail = streamingDetailText, !detail.isEmpty {
                Text(detail)
                    .font(.system(size: 9.5))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
        }
        .padding(.top, 2)
    }

    // MARK: - User Images

    @ViewBuilder
    private func userMessageImagesRow(paths: [String]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(paths, id: \.self) { path in
                    Group {
                        if FileManager.default.fileExists(atPath: path),
                            let nsImage = NSImage(contentsOf: URL(fileURLWithPath: path))
                        {
                            Image(nsImage: nsImage)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                        } else {
                            Image(systemName: "photo")
                                .font(.system(size: 24))
                                .foregroundStyle(.tertiary)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                    }
                    .frame(width: userImageThumbWidth, height: userImageThumbHeight)
                    .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
                    .clipShape(RoundedRectangle(cornerRadius: 7))
                }
            }
        }
        .fixedSize(horizontal: true, vertical: false)
        .padding(.bottom, 4)
    }
}

// MARK: - Thinking Block (LLM reasoning)

struct ThinkingBlockView: View {
    let text: String
    @State private var isExpanded = false
    private let collapsedLineLimit = 5
    private let contentMaxWidth: CGFloat = 720

    @Environment(\.colorScheme) private var colorScheme

    private var bgColor: Color {
        colorScheme == .dark
            ? Color(red: 0.10, green: 0.10, blue: 0.14)
            : Color(red: 0.96, green: 0.96, blue: 0.97)
    }
    private var borderColor: Color {
        colorScheme == .dark
            ? Color.white.opacity(0.06)
            : Color.black.opacity(0.05)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header
            HStack(spacing: 6) {
                Image(systemName: "brain.head.profile")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary.opacity(0.6))
                Text("Thinking")
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(.secondary.opacity(0.7))
                Spacer()
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { isExpanded.toggle() }
                } label: {
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 8.5, weight: .bold))
                        .foregroundStyle(.quaternary)
                }
                .buttonStyle(.plain)
            }
            // Content
            if isExpanded {
                ScrollView {
                    Text(text)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary.opacity(0.75))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 260)
            } else {
                Text(text)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary.opacity(0.75))
                    .lineLimit(collapsedLineLimit)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: contentMaxWidth, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(bgColor)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(borderColor, lineWidth: 0.5)
        )
    }
}

// MARK: - Backward compat aliases
typealias MessageBubbleView = MessageRow

// MARK: - Streaming Dots

struct StreamingDots: View {
    let color: Color
    @State private var phase: Int = 0
    @State private var timer: Timer?

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .fill(color)
                    .frame(width: 4, height: 4)
                    .opacity(phase == i ? 1 : 0.25)
            }
        }
        .onAppear {
            timer?.invalidate()
            timer = Timer.scheduledTimer(withTimeInterval: 0.35, repeats: true) { _ in
                withAnimation(.easeInOut(duration: 0.2)) { phase = (phase + 1) % 3 }
            }
        }
        .onDisappear {
            timer?.invalidate()
            timer = nil
        }
    }
}

// MARK: - Typing Indicator

struct TypingIndicator: View {
    @State private var dot = 0
    @State private var timer: Timer?

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .fill(Color.secondary)
                    .frame(width: 4, height: 4)
                    .opacity(dot == i ? 1 : 0.3)
            }
        }
        .onAppear {
            timer?.invalidate()
            timer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: true) { _ in
                withAnimation { dot = (dot + 1) % 3 }
            }
        }
        .onDisappear {
            timer?.invalidate()
            timer = nil
        }
    }
}
