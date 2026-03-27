import AppKit
import CoderEngine
import QuickLookUI
import SwiftUI

struct ReasoningBlock: Identifiable, Equatable {
    let id: String
    var text: String
}

enum MessageSegmentKind: Equatable {
    case reasoning(String)
    case text(String)
    case toolTrace([ToolTraceEvent])

    static func == (lhs: Self, rhs: Self) -> Bool {
        switch (lhs, rhs) {
        case (.reasoning(let a), .reasoning(let b)): return a == b
        case (.text(let a), .text(let b)): return a == b
        case (.toolTrace(let a), .toolTrace(let b)): return a.map(\.id) == b.map(\.id)
        default: return false
        }
    }
}

struct MessageSegment: Identifiable {
    let id: String
    var kind: MessageSegmentKind
}

// MARK: - Single Block

struct ThinkingBlockView: View {
    let text: String
    var isLiveStreaming: Bool = false
    @State private var isExpanded = false
    private let contentMaxWidth: CGFloat = 800

    private var displayText: String {
        ChatStore.sanitizedChatReasoningText(text)
    }

    @Environment(\.colorScheme) private var colorScheme

    private var accentBarColor: Color {
        colorScheme == .dark
            ? Color(red: 0.82, green: 0.63, blue: 0.28).opacity(0.34)
            : Color(red: 0.66, green: 0.46, blue: 0.12).opacity(0.28)
    }
    private var thinkingTextColor: Color { DesignSystem.Colors.textTertiary }
    private var headerTextColor: Color { accentBarColor.opacity(0.9) }
    /// In streaming il titolo deve restare leggibile: l’oro molto trasparente annulla lo shimmer sul testo.
    private var headerTitleColor: Color {
        isLiveStreaming ? DesignSystem.Colors.textSecondary : headerTextColor
    }

    private var isShowingContent: Bool { isExpanded }

    private var previewLine: String {
        let first = displayText.components(separatedBy: .newlines)
            .first(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }) ?? ""
        return first.count > 80 ? String(first.prefix(80)) + "..." : first
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            headerButton
            if isShowingContent {
                reasoningContent(text: displayText)
            }
        }
        .frame(maxWidth: contentMaxWidth, alignment: .leading)
        .onChange(of: isLiveStreaming) { streaming in
            if streaming { DispatchQueue.main.async { isExpanded = true } }
        }
    }

    private var headerButton: some View {
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
                    .foregroundStyle(headerTitleColor)
                    .tracking(0.2)
                    .textShimmer(active: isLiveStreaming)
                if !isShowingContent {
                    Text(previewLine)
                        .font(.system(size: 10))
                        .foregroundStyle(
                            isLiveStreaming
                                ? DesignSystem.Colors.textTertiary
                                : DesignSystem.Colors.textQuaternary
                        )
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .textShimmer(active: isLiveStreaming)
                }
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.bottom, isShowingContent ? 8 : 0)
    }

    private func reasoningContent(text: String) -> some View {
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
                .textShimmer(active: isLiveStreaming)
        }
        .padding(.leading, 4)
        .transition(.opacity.combined(with: .move(edge: .top)))
    }
}

// MARK: - Multi-Block

struct ThinkingBlocksView: View {
    let blocks: [ReasoningBlock]
    var isLiveStreaming: Bool = false
    @State private var isExpanded = false
    private let contentMaxWidth: CGFloat = 800

    @Environment(\.colorScheme) private var colorScheme

    private var accentBarColor: Color {
        colorScheme == .dark
            ? Color(red: 0.82, green: 0.63, blue: 0.28).opacity(0.34)
            : Color(red: 0.66, green: 0.46, blue: 0.12).opacity(0.28)
    }
    private var thinkingTextColor: Color { DesignSystem.Colors.textTertiary }
    private var headerTextColor: Color { accentBarColor.opacity(0.9) }
    private var headerTitleColor: Color {
        isLiveStreaming ? DesignSystem.Colors.textSecondary : headerTextColor
    }

    private var separatorColor: Color { .primary.opacity(0.06) }
    private var isShowingContent: Bool { isExpanded }

    private var previewLine: String {
        let text = ChatStore.sanitizedChatReasoningText(blocks.last?.text ?? blocks.first?.text ?? "")
        let first = text.components(separatedBy: .newlines)
            .first(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }) ?? ""
        return first.count > 80 ? String(first.prefix(80)) + "..." : first
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            headerButton
            if isShowingContent {
                expandedContent
            }
        }
        .frame(maxWidth: contentMaxWidth, alignment: .leading)
        .onChange(of: isLiveStreaming) { streaming in
            if streaming { DispatchQueue.main.async { isExpanded = true } }
        }
    }

    private var headerButton: some View {
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
                    .foregroundStyle(headerTitleColor)
                    .tracking(0.2)
                    .textShimmer(active: isLiveStreaming)
                if blocks.count > 1 {
                    Text("(\(blocks.count))")
                        .font(.system(size: 9.5, weight: .medium))
                        .foregroundStyle(.quaternary)
                }
                if !isShowingContent {
                    Text(previewLine)
                        .font(.system(size: 10))
                        .foregroundStyle(
                            isLiveStreaming
                                ? DesignSystem.Colors.textTertiary
                                : DesignSystem.Colors.textQuaternary
                        )
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .textShimmer(active: isLiveStreaming)
                }
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.bottom, isShowingContent ? 8 : 0)
    }

    private var expandedContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(Array(blocks.enumerated()), id: \.element.id) { index, block in
                HStack(alignment: .top, spacing: 0) {
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(accentBarColor)
                        .frame(width: 2)
                    Text(ChatStore.sanitizedChatReasoningText(block.text))
                        .font(.system(size: 11.5))
                        .foregroundStyle(thinkingTextColor)
                        .lineSpacing(5.5)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.leading, 12)
                        .textShimmer(active: index == blocks.count - 1 && isLiveStreaming)
                }
                .padding(.leading, 4)
                if index != blocks.count - 1 {
                    Rectangle()
                        .fill(separatorColor)
                        .frame(height: 0.5)
                        .padding(.leading, 18)
                }
            }
        }
        .transition(.opacity.combined(with: .move(edge: .top)))
    }
}
