import SwiftUI

extension PlanPanelView {
    func todosSection(canonicalTodos: [TodoItem]) -> some View {
        TodoSummaryCardView(
            items: canonicalTodos,
            maxItems: nil,
            maxWidth: .infinity
        )
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    var traceSection: some View {
        PlanLiveTraceView(
            activities: planTraceActivities,
            workspaceHints: [],
            onOpenFile: nil
        )
    }

    func walkthroughSection(_ markdown: String) -> some View {
        let trimmed = markdown.trimmingCharacters(in: .whitespacesAndNewlines)
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Walkthrough")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    withAnimation(.snappy(duration: 0.2)) {
                        walkthroughExpanded.toggle()
                    }
                } label: {
                    Text(walkthroughExpanded ? "Collapse" : "Expand")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(planColor)
                }
                .buttonStyle(.plain)
            }

            if walkthroughExpanded {
                MarkdownContentView(
                    content: trimmed,
                    context: nil,
                    onFileClicked: { _ in },
                    textAlignment: .leading
                )
            } else {
                Text(trimmed)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(6)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(12)
        .background(Color.primary.opacity(0.02), in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5)
        )
    }
}
