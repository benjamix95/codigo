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

    /// Only show streaming UI when both the message flag AND the actual loading state agree.
    private var isActivelyStreaming: Bool {
        message.isStreaming && isActuallyLoading
    }

    private var isUser: Bool { message.role == .user }

    private var bubbleBackground: Color {
        if isUser {
            return colorScheme == .dark
                ? Color(red: 0.35, green: 0.36, blue: 0.92).opacity(0.22)
                : Color.accentColor.opacity(0.12)
        }
        return colorScheme == .dark
            ? Color(nsColor: .controlBackgroundColor).opacity(0.85)
            : (isHovered
                ? DesignSystem.Colors.backgroundSecondary.opacity(0.65)
                : DesignSystem.Colors.backgroundSecondary.opacity(0.55))
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            if !isUser { avatar }
            VStack(alignment: isUser ? .trailing : .leading, spacing: 6) {
                HStack(spacing: 6) {
                    if isUser { Spacer(minLength: 0) }
                    Text(isUser ? "Tu" : "Coder AI")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(isUser ? Color.accentColor : modeColor)
                    if isUser {
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
                    if !isUser {
                        Image(systemName: "sparkle")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(modeColor.opacity(0.5))
                    }
                }
                if let paths = message.imagePaths, !paths.isEmpty {
                    userMessageImagesRow(paths: paths)
                }
                ClickableMessageContent(
                    content: message.content,
                    context: context,
                    onFileClicked: onFileClicked,
                    textAlignment: isUser ? .trailing : .leading
                )
                .frame(maxWidth: 620, alignment: isUser ? .trailing : .leading)
                if isActivelyStreaming { streamingBar }
            }
            if isUser { avatar }
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: isUser ? .trailing : .leading)
        .frame(maxWidth: 760, alignment: isUser ? .trailing : .leading)
        .fixedSize(horizontal: false, vertical: true)
        .modifier(MessageBubbleModifier(isUser: isUser, bubbleBackground: bubbleBackground))
        .onHover { isHovered = $0 }
        .animation(.easeOut(duration: 0.1), value: isHovered)
    }

    // MARK: - Avatar

    private var avatar: some View {
        ZStack {
            Circle()
                .fill(isUser ? Color.accentColor.opacity(0.14) : modeColor.opacity(0.14))
            Circle()
                .strokeBorder(
                    isUser ? Color.accentColor.opacity(0.25) : modeColor.opacity(0.25),
                    lineWidth: 1
                )
            Image(systemName: isUser ? "person.fill" : "brain.head.profile")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(isUser ? Color.accentColor : modeColor)
        }
        .frame(width: 28, height: 28)
    }

    // MARK: - Streaming Bar

    private var streamingBar: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                StreamingDots(color: modeColor)
                Text(streamingStatusText)
                    .font(.system(size: 10, weight: .medium))
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
                                .font(.system(size: 9, weight: .medium))
                            Image(
                                systemName: isReasoningExpanded ? "chevron.up" : "chevron.down"
                            )
                            .font(.system(size: 7, weight: .bold))
                        }
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Color.primary.opacity(0.06), in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            if let detail = streamingDetailText, !detail.isEmpty {
                Text(detail)
                    .font(.system(size: 10))
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
                            .foregroundStyle(modeColor.opacity(0.5))
                        Text(lastLine)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    .padding(6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        Color.black.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))
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
                        Color.black.opacity(0.1), in: RoundedRectangle(cornerRadius: 8)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(modeColor.opacity(0.15), lineWidth: 0.5)
                    )
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
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
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }
        }
        .padding(.bottom, 4)
    }
}

// MARK: - Message Bubble (solo per messaggi utente)
private struct MessageBubbleModifier: ViewModifier {
    let isUser: Bool
    let bubbleBackground: Color

    func body(content: Content) -> some View {
        if isUser {
            content
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(bubbleBackground)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(DesignSystem.Colors.border.opacity(0.5), lineWidth: 0.7)
                )
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .shadow(color: .black.opacity(0.12), radius: 6, y: 2)
        } else {
            content
        }
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
