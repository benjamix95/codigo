import AppKit
import CoderEngine
import QuickLookUI
import SwiftUI
// MARK: - Thinking Block (LLM reasoning — inline Cursor-style)

struct ThinkingBlockView: View {
    let text: String
    var isLiveStreaming: Bool = false
    @State private var isExpanded = false
    private let contentMaxWidth: CGFloat = 800

    @Environment(\.colorScheme) private var colorScheme

    private var accentBarColor: Color {
        colorScheme == .dark
            ? Color(red: 0.55, green: 0.63, blue: 0.95).opacity(0.25)
            : Color(red: 0.30, green: 0.38, blue: 0.75).opacity(0.20)
    }
    private var thinkingTextColor: Color { .primary.opacity(0.35) }
    private var headerTextColor: Color { .primary.opacity(0.30) }

    private var isShowingContent: Bool { isExpanded }

    private var previewLine: String {
        let first = text.components(separatedBy: .newlines)
            .first(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }) ?? ""
        return first.count > 80 ? String(first.prefix(80)) + "..." : first
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.18)) { isExpanded.toggle() }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: isShowingContent ? "chevron.down" : "chevron.right")
                        .font(.system(size: 7, weight: .bold))
                        .foregroundStyle(headerTextColor)
                        .frame(width: 10)
                    Image(systemName: "brain.head.profile")
                        .font(.system(size: 9.5, weight: .medium))
                        .foregroundStyle(accentBarColor)
                    Text(isLiveStreaming ? "Thinking..." : "Thought process")
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(headerTextColor)
                        .tracking(0.2)
                        .textShimmer(active: isLiveStreaming)
                    if !isShowingContent {
                        Text(previewLine)
                            .font(.system(size: 10))
                            .foregroundStyle(.quaternary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.bottom, isShowingContent ? 8 : 0)

            if isShowingContent {
                HStack(alignment: .top, spacing: 0) {
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(accentBarColor)
                        .frame(width: 2)
                    Text(text)
                        .font(.system(size: 11.5))
                        .foregroundStyle(thinkingTextColor)
                        .lineSpacing(5.5)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.leading, 12)
                }
                .padding(.leading, 4)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .frame(maxWidth: contentMaxWidth, alignment: .leading)
        .onChange(of: isLiveStreaming) { _, streaming in
            if streaming { isExpanded = true }
        }
    }

}
