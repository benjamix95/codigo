import SwiftUI

struct TodoSummaryCardView: View {
    let items: [TodoItem]
    var maxItems: Int? = 8
    var maxWidth: CGFloat = 520
    var completedLabel: String = "Completed"
    var pendingLabel: String = "To-dos"

    private var displayedItems: [TodoItem] {
        let sorted = items.sorted { lhs, rhs in
            if lhs.status.rank != rhs.status.rank {
                return lhs.status.rank < rhs.status.rank
            }
            if lhs.isPlanCanonical != rhs.isPlanCanonical {
                return lhs.isPlanCanonical && !rhs.isPlanCanonical
            }
            if lhs.planOrder != rhs.planOrder {
                return (lhs.planOrder ?? .max) < (rhs.planOrder ?? .max)
            }
            return lhs.createdAt < rhs.createdAt
        }
        if let maxItems {
            return Array(sorted.prefix(maxItems))
        }
        return sorted
    }

    var body: some View {
        let items = displayedItems
        let doneCount = items.filter { $0.status == .done }.count
        let total = items.count

        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 5) {
                    Text("\(doneCount) of \(total)")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                        .contentTransition(.numericText())
                    Text(doneCount == total ? completedLabel : pendingLabel)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.bottom, 8)

                VStack(alignment: .leading, spacing: 1) {
                    ForEach(items) { todo in
                        todoRow(todo)
                    }
                }
                .animation(
                    .easeOut(duration: 0.2),
                    value: items.map { "\($0.id)-\($0.status.rawValue)" }
                )
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: maxWidth, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color(nsColor: .textBackgroundColor).opacity(0.3))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.5)
            )
        }
    }

    private func todoRow(_ todo: TodoItem) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            statusIcon(for: todo.status)

            Text(todo.title)
                .font(.system(size: 11.5))
                .foregroundStyle(todo.status == .done ? .tertiary : .primary)
                .strikethrough(todo.status == .done, color: .primary.opacity(0.25))
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 3)
    }

    @ViewBuilder
    private func statusIcon(for status: TodoStatus) -> some View {
        switch status {
        case .inProgress:
            Image(systemName: "circle.inset.filled")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.primary.opacity(0.55))
                .frame(width: 14)
        case .done:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.tertiary)
                .frame(width: 14)
        case .pending:
            Image(systemName: "circle")
                .font(.system(size: 11, weight: .regular))
                .foregroundStyle(.primary.opacity(0.2))
                .frame(width: 14)
        case .blocked:
            Image(systemName: "exclamationmark.circle")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.orange.opacity(0.6))
                .frame(width: 14)
        }
    }
}
