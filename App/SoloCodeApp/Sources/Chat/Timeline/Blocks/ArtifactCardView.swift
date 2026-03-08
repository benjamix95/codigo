import SwiftUI

struct ArtifactCardView: View {
    let block: PersistedChatTimelineBlock
    let accentColor: Color
    let context: ProjectContext?
    let onFileClicked: (String) -> Void

    @State private var isCollapsed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if block.isCollapsible {
                Button {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        isCollapsed.toggle()
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.secondary)
                        Text(block.title ?? fallbackTitle)
                            .font(.system(size: 11.5, weight: .semibold))
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                }
                .buttonStyle(.plain)
            }

            if !isCollapsed {
                content
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .frame(maxWidth: 800, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(nsColor: .textBackgroundColor).opacity(0.3))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.1), lineWidth: 0.5)
        )
        .onAppear {
            isCollapsed = block.isCollapsedByDefault
        }
    }

    @ViewBuilder
    private var content: some View {
        switch block.kind {
        case .mermaid:
            MermaidDiagramView(mermaidCode: block.text, accentColor: accentColor)
        case .commands, .files:
            VStack(alignment: .leading, spacing: 6) {
                if !block.isCollapsible {
                    Text(block.title ?? fallbackTitle)
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                ForEach(block.items, id: \.self) { item in
                    Text("• \(item)")
                        .font(.system(size: 11.5, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }
        case .status, .plan, .toolTrace, .reasoning, .primaryText:
            VStack(alignment: .leading, spacing: 6) {
                if !block.isCollapsible {
                    Text(block.title ?? fallbackTitle)
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                MarkdownContentView(
                    content: block.text,
                    context: context,
                    onFileClicked: onFileClicked,
                    textAlignment: .leading,
                    isStreaming: false
                )
            }
        }
    }

    private var fallbackTitle: String {
        switch block.kind {
        case .mermaid: return "Diagram"
        case .commands: return "Commands executed"
        case .files: return "Files touched"
        case .status: return "Status"
        case .plan: return "Plan"
        case .toolTrace: return "Trace"
        case .reasoning: return "Thinking"
        case .primaryText: return "Response"
        }
    }
}
