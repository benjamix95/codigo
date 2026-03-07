import CoderEngine
import SwiftUI

/// Chat bubble for a single message in the review panel chat.
struct ReviewPanelChatBubble: View {
    let message: ReviewPanelMessage
    let accent: Color

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
        }
    }

    // MARK: - Assistant Bubble

    private var assistantBubble: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Image(systemName: "sparkles")
                    .font(.system(size: 8))
                    .foregroundStyle(accent)

                if message.isStreaming {
                    ProgressView()
                        .controlSize(.mini)
                        .scaleEffect(0.6)
                }
            }

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
        }
    }

    // MARK: - System Bubble

    private var systemBubble: some View {
        HStack(spacing: 4) {
            Image(systemName: "info.circle")
                .font(.system(size: 8))
                .foregroundStyle(.tertiary)
            Text(message.content)
                .font(.system(size: 9.5))
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 4)
    }
}
