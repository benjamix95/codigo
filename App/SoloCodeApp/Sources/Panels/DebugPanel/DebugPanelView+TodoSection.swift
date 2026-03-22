import SwiftUI

extension DebugPanelView {
    func debugTodoCard(_ items: [TodoItem]) -> some View {
        let ordered = items.sorted { lhs, rhs in
            if lhs.planOrder != rhs.planOrder {
                return (lhs.planOrder ?? .max) < (rhs.planOrder ?? .max)
            }
            if lhs.status.rank != rhs.status.rank {
                return lhs.status.rank < rhs.status.rank
            }
            return lhs.createdAt < rhs.createdAt
        }
        let doneCount = ordered.filter { $0.status == .done }.count

        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "checklist")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(accent)
                Text("\(doneCount) / \(ordered.count) tasks")
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(DesignSystem.Colors.textSecondary)
                    .contentTransition(.numericText())
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)

            Divider().overlay(Color.primary.opacity(0.06))

            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(ordered.enumerated()), id: \.element.id) { index, todo in
                    HStack(alignment: .top, spacing: 8) {
                        debugTodoStatusIcon(todo.status)
                            .padding(.top, 1)
                        Text("\(index + 1).")
                            .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                            .foregroundStyle(DesignSystem.Colors.textTertiary)
                        Text(todo.title)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(
                                todo.status == .done
                                    ? DesignSystem.Colors.textTertiary
                                    : DesignSystem.Colors.textPrimary
                            )
                            .strikethrough(
                                todo.status == .done,
                                color: DesignSystem.Colors.textTertiary.opacity(0.4)
                            )
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(accent.opacity(0.03))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(accent.opacity(0.15), lineWidth: 0.5)
        )
    }

    @ViewBuilder
    private func debugTodoStatusIcon(_ status: TodoStatus) -> some View {
        switch status {
        case .pending:
            Image(systemName: "circle")
                .font(.system(size: 11, weight: .regular))
                .foregroundStyle(DesignSystem.Colors.textTertiary.opacity(0.5))
        case .inProgress:
            Image(systemName: "circle.inset.filled")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(accent.opacity(0.85))
        case .blocked:
            Image(systemName: "exclamationmark.circle")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(DesignSystem.Colors.warning.opacity(0.8))
        case .done:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(DesignSystem.Colors.success.opacity(0.9))
        }
    }
}
