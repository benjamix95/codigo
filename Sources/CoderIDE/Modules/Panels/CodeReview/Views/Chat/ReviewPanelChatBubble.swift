import CoderEngine
import SwiftUI

/// Chat bubble for a single message in the review panel chat.
struct ReviewPanelChatBubble: View {
    let message: ReviewPanelMessage
    let accent: Color
    let onOpenFile: ((String) -> Void)?
    let onOpenFileAtLocation: ((String, Int?) -> Void)?
    let onSelectFinding: ((String) -> Void)?

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            if message.role == .user {
                Spacer(minLength: 40)
                userBubble
            } else if message.role == .assistant {
                assistantBubble
                Spacer(minLength: 40)
            } else {
                systemBubble
            }
        }
    }

    // MARK: - User Bubble

    private var userBubble: some View {
        VStack(alignment: .trailing, spacing: 2) {
            bubbleHeader(
                title: message.kind.title,
                icon: message.kind.icon,
                color: accent.opacity(0.85),
                isTrailing: true
            )
            Text(message.content)
                .font(.system(size: 10.5))
                .foregroundStyle(.white)
                .textSelection(.enabled)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    accent,
                    in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                )

            Text(message.timestamp, style: .time)
                .font(.system(size: 8))
                .foregroundStyle(.quaternary)
            actionBar(alignment: .trailing)
        }
    }

    // MARK: - Assistant Bubble

    private var assistantBubble: some View {
        VStack(alignment: .leading, spacing: 2) {
            bubbleHeader(
                title: message.kind.title,
                icon: message.kind.icon,
                color: accent,
                isTrailing: false,
                showsProgress: message.isStreaming
            )

            if message.content.isEmpty && message.isStreaming {
                HStack(spacing: 3) {
                    ForEach(0..<3) { i in
                        Circle()
                            .fill(accent.opacity(0.4))
                            .frame(width: 4, height: 4)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(
                    Color(nsColor: .controlBackgroundColor).opacity(0.5),
                    in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                )
            } else {
                Text(message.content)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.primary.opacity(0.9))
                    .textSelection(.enabled)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        Color(nsColor: .controlBackgroundColor).opacity(0.5),
                        in: RoundedRectangle(
                            cornerRadius: 10, style: .continuous)
                    )
                    .overlay(
                        RoundedRectangle(
                            cornerRadius: 10, style: .continuous
                        )
                        .strokeBorder(
                            DesignSystem.Colors.border.opacity(0.2),
                            lineWidth: 0.5
                        )
                    )
            }

            Text(message.timestamp, style: .time)
                .font(.system(size: 8))
                .foregroundStyle(.quaternary)
            actionBar(alignment: .leading)
        }
    }

    // MARK: - System Bubble

    private var systemBubble: some View {
        VStack(alignment: .leading, spacing: 4) {
            bubbleHeader(
                title: message.kind.title,
                icon: message.kind.icon,
                color: systemBubbleAccent,
                isTrailing: false
            )
            Text(message.content)
                .font(systemBubbleFont)
                .foregroundStyle(systemBubbleForeground)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
            actionBar(alignment: .leading)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(systemBubbleFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(systemBubbleAccent.opacity(0.2), lineWidth: 0.5)
        )
        .frame(maxWidth: .infinity)
    }

    private func bubbleHeader(
        title: String,
        icon: String,
        color: Color,
        isTrailing: Bool,
        showsProgress: Bool = false
    ) -> some View {
        HStack(spacing: 4) {
            if isTrailing {
                Spacer(minLength: 0)
            }
            Image(systemName: icon)
                .font(.system(size: 8, weight: .semibold))
                .foregroundStyle(color)
            Text(title.uppercased())
                .font(.system(size: 7.5, weight: .bold))
                .foregroundStyle(color.opacity(0.85))
                .tracking(0.6)
            if showsProgress {
                ProgressView()
                    .controlSize(.mini)
                    .scaleEffect(0.6)
            }
            if !isTrailing {
                Spacer(minLength: 0)
            }
        }
    }

    private var systemBubbleFill: Color {
        switch message.kind {
        case .summary:
            return accent.opacity(0.08)
        case .findingMutation:
            return DesignSystem.Colors.info.opacity(0.08)
        case .statusNote, .plain, .commandInvocation, .reviewRun:
            return Color(nsColor: .controlBackgroundColor).opacity(0.35)
        }
    }

    private var systemBubbleAccent: Color {
        switch message.kind {
        case .summary:
            return accent
        case .findingMutation:
            return DesignSystem.Colors.info
        case .statusNote, .plain, .commandInvocation, .reviewRun:
            return .secondary
        }
    }

    private var systemBubbleFont: Font {
        switch message.kind {
        case .summary:
            return .system(size: 9.5, weight: .medium, design: .monospaced)
        case .findingMutation:
            return .system(size: 9.5, weight: .medium)
        case .statusNote, .plain, .commandInvocation, .reviewRun:
            return .system(size: 9.5)
        }
    }

    private var systemBubbleForeground: Color {
        switch message.kind {
        case .summary:
            return accent.opacity(0.9)
        case .findingMutation:
            return DesignSystem.Colors.info
        case .statusNote, .plain, .commandInvocation, .reviewRun:
            return .secondary
        }
    }

    private var fileTargets: [ReviewPanelChatMessageFileTarget] {
        ReviewPanelChatMessageContext.fileTargets(from: message.content)
    }

    private var findingTargets: [ReviewPanelChatFindingTarget] {
        ReviewPanelChatMessageContext.findingTargets(from: message.content)
    }

    private var hasActions: Bool {
        !message.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func actionBar(alignment: HorizontalAlignment) -> some View {
        let targets = fileTargets
        return VStack(alignment: alignment, spacing: 4) {
            if hasActions {
                HStack(spacing: 6) {
                    Button {
                        ReviewPanelChatMessageContext.copyToPasteboard(message.content)
                    } label: {
                        actionChip("Copy", systemName: "doc.on.doc")
                    }
                    .buttonStyle(.plain)

                    ForEach(targets) { target in
                        Button {
                            if let onOpenFileAtLocation {
                                onOpenFileAtLocation(target.path, target.line)
                            } else {
                                onOpenFile?(target.path)
                            }
                        } label: {
                            actionChip(target.displayLabel, systemName: "arrow.up.forward.app")
                        }
                        .buttonStyle(.plain)
                        .disabled(onOpenFileAtLocation == nil && onOpenFile == nil)
                    }

                    ForEach(findingTargets) { target in
                        Button {
                            onSelectFinding?(target.findingId)
                        } label: {
                            actionChip(target.displayLabel, systemName: "scope")
                        }
                        .buttonStyle(.plain)
                        .disabled(onSelectFinding == nil)
                    }

                    Spacer(minLength: 0)
                }
            }
        }
    }

    private func actionChip(_ text: String, systemName: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: systemName)
                .font(.system(size: 7, weight: .semibold))
            Text(text)
                .font(.system(size: 8.5, weight: .medium))
                .lineLimit(1)
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(
            Capsule()
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.55))
        )
        .overlay(
            Capsule()
                .strokeBorder(DesignSystem.Colors.border.opacity(0.18), lineWidth: 0.5)
        )
    }
}
