import SwiftUI

struct ChatTodoExecutionCardView: View {
    let items: [TodoItem]
    let fileChanges: [ToolTraceFileChange]
    let microStatusText: String?
    let isStreaming: Bool
    let onReviewChanges: () -> Void

    @State private var isExpanded = false

    private var orderedItems: [TodoItem] {
        // Keep original insertion order: sort by planOrder then createdAt.
        // Completed items stay in place (no status-based reordering).
        items.sorted { lhs, rhs in
            if lhs.planOrder != rhs.planOrder {
                return (lhs.planOrder ?? .max) < (rhs.planOrder ?? .max)
            }
            return lhs.createdAt < rhs.createdAt
        }
    }

    private var metrics: ChatTodoExecutionCardMetrics {
        ChatTodoExecutionCardMetrics.build(items: orderedItems, fileChanges: fileChanges)
    }

    var body: some View {
        if !orderedItems.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                header
                if let microStatusText, !microStatusText.isEmpty {
                    Divider()
                        .overlay(Color.primary.opacity(0.08))
                    microStatusRow(text: microStatusText)
                }
                if metrics.fileCount > 0 {
                    Divider()
                        .overlay(Color.primary.opacity(0.08))
                    footer
                }

                if isExpanded {
                    checklistSection
                }
            }
            .frame(maxWidth: 800, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color(nsColor: .textBackgroundColor).opacity(0.38))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.6)
            )
            .onAppear {
                isExpanded = ChatTodoExecutionCardMetrics.shouldStartExpanded(items: orderedItems)
            }
        }
    }

    private var header: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.18)) {
                isExpanded.toggle()
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "checklist")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
                Text("\(metrics.doneCount) su \(metrics.totalCount) attività completate")
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .contentTransition(.numericText())
                Spacer(minLength: 0)
                Image(systemName: isExpanded ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var checklistSection: some View {
        ScrollView(.vertical, showsIndicators: true) {
            VStack(alignment: .leading, spacing: 14) {
                ForEach(Array(orderedItems.enumerated()), id: \.element.id) { index, todo in
                    HStack(alignment: .top, spacing: 12) {
                        statusIcon(for: todo.status)
                            .padding(.top, 2)
                        Text("\(index + 1).")
                            .font(.system(size: 12.5, weight: .semibold, design: .monospaced))
                            .foregroundStyle(.secondary)
                        Text(todo.title)
                            .font(.system(size: 12.5, weight: .medium))
                            .foregroundStyle(todo.status == .done ? .secondary : .primary)
                            .strikethrough(todo.status == .done, color: .primary.opacity(0.18))
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 14)
        }
        .frame(maxHeight: 280)
    }

    private func microStatusRow(text: String) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(DesignSystem.Colors.planColor.opacity(0.75))
                .frame(width: 6, height: 6)
            Text(text)
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .textShimmer(active: isStreaming)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Text("\(metrics.fileCount) file modificati")
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(.secondary)
            Text("+\(metrics.linesAdded)")
                .font(.system(size: 12.5, weight: .semibold, design: .monospaced))
                .foregroundStyle(DesignSystem.Colors.success)
            Text("-\(metrics.linesRemoved)")
                .font(.system(size: 12.5, weight: .semibold, design: .monospaced))
                .foregroundStyle(DesignSystem.Colors.error)
            Spacer(minLength: 0)
            Button(action: onReviewChanges) {
                HStack(spacing: 6) {
                    Text("Rivedi modifiche")
                        .font(.system(size: 12.5, weight: .semibold))
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 11, weight: .semibold))
                }
                .foregroundStyle(.primary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    @ViewBuilder
    private func statusIcon(for status: TodoStatus) -> some View {
        switch status {
        case .pending:
            Image(systemName: "circle")
                .font(.system(size: 12, weight: .regular))
                .foregroundStyle(.secondary.opacity(0.5))
        case .inProgress:
            Image(systemName: "circle.inset.filled")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(DesignSystem.Colors.planColor.opacity(0.85))
        case .blocked:
            Image(systemName: "exclamationmark.circle")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.orange.opacity(0.8))
        case .done:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(DesignSystem.Colors.success.opacity(0.9))
        }
    }
}
