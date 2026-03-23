import SwiftUI

/// Compact thinking block for the review panel chat,
/// styled similarly to the main chat's ThinkingBlockView.
struct ReviewPanelChatThinkingView: View {
    let section: ReviewPanelChatStructuredSection
    var isStreaming: Bool = false

    @State private var isExpanded = false

    private var accentBarColor: Color {
        Color(red: 0.55, green: 0.63, blue: 0.95).opacity(0.25)
    }
    private var thinkingTextColor: Color { .primary.opacity(0.35) }
    private var headerTextColor: Color { .primary.opacity(0.30) }

    private var previewLine: String {
        let first = section.lines.first(where: { !$0.isEmpty }) ?? ""
        return first.count > 72 ? String(first.prefix(72)) + "..." : first
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.18)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 7, weight: .bold))
                        .foregroundStyle(headerTextColor)
                        .frame(width: 8)
                    Image(systemName: "brain.head.profile")
                        .font(.system(size: 8.5, weight: .medium))
                        .foregroundStyle(accentBarColor)
                    Text(isStreaming ? "Thinking..." : "Thought process")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(headerTextColor)
                        .tracking(0.2)
                    if !isExpanded {
                        Text(previewLine)
                            .font(.system(size: 8.5))
                            .foregroundStyle(.quaternary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.bottom, isExpanded ? 6 : 0)

            if isExpanded {
                HStack(alignment: .top, spacing: 0) {
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(accentBarColor)
                        .frame(width: 2)
                    Text(section.lines.joined(separator: "\n"))
                        .font(.system(size: 9.5))
                        .foregroundStyle(thinkingTextColor)
                        .lineSpacing(4)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.leading, 10)
                }
                .padding(.leading, 3)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(DesignSystem.Colors.thinkingBackground)
        )
        .onChange(of: isStreaming) { streaming in
            if streaming { isExpanded = true }
        }
    }
}
