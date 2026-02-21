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
    let streamingReasoningText: String?
    let onFileClicked: (String) -> Void
    var onRestoreCheckpoint: (() -> Void)? = nil
    var canRestoreCheckpoint: Bool = false
    @State private var isHovered = false
    @State private var isReasoningExpanded = false
    @Environment(\.colorScheme) private var colorScheme
    private let userRowMaxWidth: CGFloat = 560
    private let assistantRowMaxWidth: CGFloat = 780

    /// Only show streaming UI when both the message flag AND the actual loading state agree.
    private var isActivelyStreaming: Bool {
        message.isStreaming && isActuallyLoading
    }

    private var isUser: Bool { message.role == .user }
    private var rowMaxWidth: CGFloat { isUser ? userRowMaxWidth : assistantRowMaxWidth }
    private var contentMaxWidth: CGFloat { isUser ? 480 : 680 }

    var body: some View {
        VStack(alignment: isUser ? .trailing : .leading, spacing: 0) {
            if isUser {
                userHeader
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

    // MARK: - User Header (label + checkpoint)

    private var userHeader: some View {
        HStack(spacing: 6) {
            Spacer(minLength: 0)
            Text("Tu")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
            Button {
                onRestoreCheckpoint?()
            } label: {
                Image(systemName: "arrow.uturn.backward")
                    .font(.system(size: 10, weight: .semibold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(canRestoreCheckpoint ? .primary : .tertiary)
            .disabled(!canRestoreCheckpoint)
            .help("Ripristina chat e file da questo punto")
            .accessibilityLabel("Ripristina checkpoint")
        }
        .padding(.trailing, 14)
        .padding(.bottom, 4)
    }

    // MARK: - Message Content

    private var messageContent: some View {
        VStack(alignment: isUser ? .trailing : .leading, spacing: 6) {
            if let paths = message.imagePaths, !paths.isEmpty {
                userMessageImagesRow(paths: paths)
            }
            if isUser {
                // User bubble — clean pill
                ClickableMessageContent(
                    content: message.content,
                    context: context,
                    onFileClicked: onFileClicked,
                    textAlignment: .trailing
                )
                .frame(maxWidth: contentMaxWidth, alignment: .trailing)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(DesignSystem.Colors.chatUserBubbleFill)
                )
            } else {
                // Assistant — flat text, no background (ChatGPT-style)
                HStack(alignment: .top, spacing: 10) {
                    // Subtle AI indicator
                    Image(systemName: "sparkle")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(modeColor.opacity(0.55))
                        .padding(.top, 3)

                    MarkdownContentView(
                        content: message.content,
                        context: context,
                        onFileClicked: onFileClicked,
                        textAlignment: .leading
                    )
                    .frame(maxWidth: contentMaxWidth, alignment: .leading)
                }
                .padding(.vertical, 4)
                if isActivelyStreaming { streamingBar }
            }
        }
    }

    // MARK: - Streaming Bar

    private var streamingBar: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                StreamingDots(color: modeColor)
                Text(streamingStatusText)
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundStyle(.tertiary)
                Spacer()
                if let reasoning = streamingReasoningText, !reasoning.isEmpty {
                    Button {
                        withAnimation(.easeOut(duration: 0.15)) {
                            isReasoningExpanded.toggle()
                        }
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: "brain")
                                .font(.system(size: 9, weight: .semibold))
                            Text(isReasoningExpanded ? "Nascondi" : "Reasoning")
                                .font(.system(size: 8.5, weight: .medium))
                            Image(
                                systemName: isReasoningExpanded ? "chevron.up" : "chevron.down"
                            )
                            .font(.system(size: 7, weight: .bold))
                        }
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Color.primary.opacity(0.05), in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            if let detail = streamingDetailText, !detail.isEmpty {
                Text(detail)
                    .font(.system(size: 9.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            // Reasoning preview — always show last snippet
            if let reasoning = streamingReasoningText, !reasoning.isEmpty {
                if !isReasoningExpanded {
                    // Compact preview of last reasoning line
                    let lastLine =
                        reasoning.split(separator: "\n").last.map(String.init) ?? reasoning
                    HStack(spacing: 4) {
                        Image(systemName: "brain")
                            .font(.system(size: 8))
                            .foregroundStyle(modeColor.opacity(0.45))
                        Text(lastLine)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    .padding(6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
                } else {
                    // Full expanded reasoning
                    ScrollView(.vertical, showsIndicators: true) {
                        Text(reasoning)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                    }
                    .frame(maxHeight: 240)
                    .padding(8)
                    .background(
                        Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10)
                    )
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
        }
        .padding(.top, 2)
        .padding(.leading, 21) // align with text after sparkle icon
    }

    // MARK: - User Message Images Row

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
                    .frame(width: 60, height: 60)
                    .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }
            }
        }
        .padding(.bottom, 4)
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
