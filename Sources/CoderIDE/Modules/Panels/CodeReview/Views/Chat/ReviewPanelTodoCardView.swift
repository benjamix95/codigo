import SwiftUI

struct ReviewPanelTodoCardView: View {
    let items: [TodoItem]
    @State private var isExpanded = false

    var body: some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                Button {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        isExpanded.toggle()
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "checklist")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.secondary)
                        Text("\(doneCount) / \(items.count) todo")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.secondary)
                        Spacer(minLength: 0)
                        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                }
                .buttonStyle(.plain)

                if isExpanded {
                    Divider().opacity(0.12)
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                            HStack(alignment: .top, spacing: 10) {
                                statusIcon(for: item.status)
                                    .padding(.top, 2)
                                Text("\(index + 1).")
                                    .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                                    .foregroundStyle(.secondary)
                                Text(item.title)
                                    .font(.system(size: 10.5, weight: .medium))
                                    .foregroundStyle(item.status == .done ? .secondary : .primary)
                                    .strikethrough(item.status == .done, color: .primary.opacity(0.18))
                                    .fixedSize(horizontal: false, vertical: true)
                                Spacer(minLength: 0)
                            }
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 12)
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor).opacity(0.32))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(DesignSystem.Colors.border.opacity(0.14), lineWidth: 0.5)
            )
        }
    }

    private var doneCount: Int {
        items.filter { $0.status == .done }.count
    }

    @ViewBuilder
    private func statusIcon(for status: TodoStatus) -> some View {
        switch status {
        case .pending:
            Image(systemName: "circle")
                .font(.system(size: 10))
                .foregroundStyle(.secondary.opacity(0.45))
        case .inProgress:
            Image(systemName: "circle.inset.filled")
                .font(.system(size: 10))
                .foregroundStyle(DesignSystem.Colors.planColor.opacity(0.85))
        case .blocked:
            Image(systemName: "exclamationmark.circle")
                .font(.system(size: 10))
                .foregroundStyle(.orange.opacity(0.85))
        case .done:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 10))
                .foregroundStyle(DesignSystem.Colors.success.opacity(0.9))
        }
    }
}
