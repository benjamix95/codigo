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
    private let userRowMaxWidth: CGFloat = 580
    private let assistantRowMaxWidth: CGFloat = 820

    /// Only show streaming UI when both the message flag AND the actual loading state agree.
    private var isActivelyStreaming: Bool {
        message.isStreaming && isActuallyLoading
    }

    /// Mostra la barra streaming durante lo streaming attivo (nascosta se c'è feed attività inline).
    private var shouldShowStreamingBar: Bool {
        showStreamingBar && isActivelyStreaming
    }

    private var isUser: Bool { message.role == .user }
    private var rowMaxWidth: CGFloat { isUser ? userRowMaxWidth : assistantRowMaxWidth }
    private var contentMaxWidth: CGFloat { isUser ? 500 : 720 }

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
                        Color.primary.opacity(0.06),
                        Color.primary.opacity(0.06),
                        Color.clear,
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .frame(height: 0.5)
            .frame(maxWidth: rowMaxWidth)
            .padding(.bottom, 16)
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
            .foregroundStyle(canRewind ? .primary : .tertiary)
            .disabled(!canRewind)
            .help(
                hasCheckpointForRestore
                    ? "Ripristina chat e file da questo punto"
                    : "Ripristina chat da questo punto (file non ripristinati)"
            )
            .accessibilityLabel("Ripristina checkpoint")
        }
        .padding(.trailing, 14)
        .padding(.bottom, 4)
    }

    // MARK: - Assistant Header

    private var assistantHeader: some View {
        HStack(spacing: 6) {
            Image(systemName: "sparkles")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(modeColor.opacity(0.7))
            Text("Assistant")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
        .padding(.leading, 2)
        .padding(.bottom, 4)
    }

    // MARK: - Message Content

    private var messageContent: some View {
        VStack(alignment: isUser ? .trailing : .leading, spacing: 6) {
            if let paths = message.imagePaths, !paths.isEmpty {
                userMessageImagesRow(paths: paths)
            }
            if isUser {
                // User bubble — clean pill, allineato a destra
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
            } else {
                // Assistant — flat text, no background (ChatGPT-style)
                if isActivelyStreaming,
                   let reasoning = streamingReasoningText, !reasoning.isEmpty
                {
                    ThinkingBlockView(text: reasoning)
                        .padding(.bottom, 8)
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
                if shouldShowStreamingBar { streamingBar }
            }
        }
    }

    // MARK: - Streaming Bar

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
        .fixedSize(horizontal: true, vertical: false) // larghezza solo per contenuto, così VStack .trailing la allinea a destra
        .padding(.bottom, 4)
    }
}

// MARK: - Thinking Block (LLM reasoning)

struct ThinkingBlockView: View {
    let text: String
    @State private var isExpanded = false
    private let collapsedLineLimit = 6
    private let contentMaxWidth: CGFloat = 720

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "brain.head.profile")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary.opacity(0.7))
                Text("Thinking")
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { isExpanded.toggle() }
                } label: {
                    HStack(spacing: 3) {
                        Text(isExpanded ? "Riduci" : "Espandi")
                            .font(.system(size: 9.5, weight: .medium))
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 8, weight: .semibold))
                    }
                    .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }
            if isExpanded {
                ScrollView {
                    Text(text)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary.opacity(0.8))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 240)
            } else {
                Text(text)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary.opacity(0.8))
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
                .fill(Color.secondary.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.secondary.opacity(0.08), lineWidth: 0.5)
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
