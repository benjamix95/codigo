import SwiftUI

extension PlanPanelView {
    func todosSection(canonicalTodos: [TodoItem]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Todos")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                let done = canonicalTodos.filter { $0.status == .done }.count
                Text("\(done)/\(canonicalTodos.count)")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }

            VStack(alignment: .leading, spacing: 6) {
                ForEach(canonicalTodos.prefix(50)) { todo in
                    HStack(spacing: 8) {
                        Image(systemName: todo.status.icon)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(todo.status.color)
                            .frame(width: 14, alignment: .center)
                        Text(todo.title)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.primary)
                            .lineLimit(2)
                        Spacer()
                        Text(todo.status.label)
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundStyle(todo.status.color)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(todo.status.color.opacity(0.12), in: Capsule())
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .padding(12)
        .background(Color.primary.opacity(0.02), in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5)
        )
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
