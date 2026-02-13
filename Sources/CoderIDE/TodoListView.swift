import SwiftUI

struct TodoListView: View {
    @ObservedObject var store: TodoStore
    @State private var newTodoText = ""
    @FocusState private var isNewTodoFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
            addTodoRow

            ForEach(store.todos) { todo in
                TodoRowView(
                    todo: todo,
                    isInProgress: store.inProgressTodoId == todo.id,
                    onTap: { store.handleRowTap(id: todo.id) },
                    onDelete: { store.remove(id: todo.id) }
                )
            }

            if store.todos.isEmpty {
                Text("Nessun to-do")
                    .font(DesignSystem.Typography.caption)
                    .foregroundStyle(DesignSystem.Colors.textTertiary)
                    .padding(.horizontal, DesignSystem.Spacing.md)
                    .padding(.vertical, DesignSystem.Spacing.sm)
            }
        }
    }

    private var addTodoRow: some View {
        HStack(spacing: DesignSystem.Spacing.sm) {
            TextField("Aggiungi to-do...", text: $newTodoText)
                .textFieldStyle(.plain)
                .font(DesignSystem.Typography.subheadline)
                .foregroundStyle(DesignSystem.Colors.textPrimary)
                .focused($isNewTodoFocused)
                .onSubmit {
                    submitNewTodo()
                }
                .padding(DesignSystem.Spacing.sm)
                .background {
                    RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.small)
                        .fill(Color.white.opacity(0.04))
                }

            Button {
                submitNewTodo()
            } label: {
                Image(systemName: "plus.circle.fill")
                    .font(.body)
                    .foregroundStyle(newTodoText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        ? DesignSystem.Colors.textTertiary
                        : DesignSystem.Colors.primary)
            }
            .buttonStyle(.plain)
            .hoverEffect(scale: 1.1)
            .disabled(newTodoText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(.horizontal, DesignSystem.Spacing.sm)
        .padding(.vertical, DesignSystem.Spacing.xs)
    }

    private func submitNewTodo() {
        let trimmed = newTodoText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        store.add(title: trimmed)
        newTodoText = ""
    }
}

private struct TodoRowView: View {
    let todo: TodoItem
    let isInProgress: Bool
    let onTap: () -> Void
    let onDelete: () -> Void

    private var statusIcon: String {
        if todo.completed { return "checkmark.circle.fill" }
        if isInProgress { return "arrow.right.circle" }
        return "circle"
    }

    private var statusColor: Color {
        if todo.completed { return DesignSystem.Colors.textTertiary }
        if isInProgress { return DesignSystem.Colors.textSecondary }
        return DesignSystem.Colors.textTertiary
    }

    var body: some View {
        HStack(alignment: .center, spacing: DesignSystem.Spacing.sm) {
            Image(systemName: statusIcon)
                .font(DesignSystem.Typography.subheadline)
                .foregroundStyle(statusColor)

            Text(todo.title)
                .font(isInProgress ? DesignSystem.Typography.subheadlineMedium : DesignSystem.Typography.subheadline)
                .foregroundStyle(todo.completed ? DesignSystem.Colors.textTertiary : DesignSystem.Colors.textPrimary)
                .strikethrough(todo.completed)
                .opacity(todo.completed ? 0.7 : 1)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, DesignSystem.Spacing.xs)

            Button {
                onDelete()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(DesignSystem.Typography.caption)
                    .foregroundStyle(DesignSystem.Colors.textTertiary.opacity(0.7))
            }
            .buttonStyle(.plain)
            .hoverEffect(scale: 1.1)
        }
        .padding(.leading, DesignSystem.Spacing.md)
        .padding(.horizontal, DesignSystem.Spacing.sm)
        .padding(.vertical, DesignSystem.Spacing.sm)
        .background {
            RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium)
                .fill(Color.white.opacity(0.03))
        }
        .contentShape(Rectangle())
        .onTapGesture {
            onTap()
        }
    }
}
