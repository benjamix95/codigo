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
                .foregroundStyle(.white.opacity(0.96))
                .textSelection(.enabled)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    userBubbleFill,
                    in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(userBubbleBorder, lineWidth: 0.6)
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
                assistantContentBody
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
            systemContentBody
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
}
