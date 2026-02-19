import SwiftUI

struct TodoListView: View {
    @ObservedObject var store: TodoStore
    @State private var newTodoText = ""
    @FocusState private var isNewTodoFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
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
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
            }
        }
    }

    private var addTodoRow: some View {
        HStack(spacing: 6) {
            TextField("Aggiungi to-do...", text: $newTodoText)
                .textFieldStyle(.roundedBorder)
                .font(.subheadline)
                .focused($isNewTodoFocused)
                .onSubmit { submitNewTodo() }

            Button {
                submitNewTodo()
            } label: {
                Image(systemName: "plus.circle.fill")
                    .foregroundStyle(newTodoText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? Color.secondary : .accentColor)
            }
            .buttonStyle(.plain)
            .disabled(newTodoText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(.horizontal, 4)
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
        if todo.completed { return .green }
        if isInProgress { return .orange }
        return .secondary
    }

    var body: some View {
        HStack(alignment: .center, spacing: 6) {
            Image(systemName: statusIcon)
                .font(.subheadline)
                .foregroundStyle(statusColor)

            Text(todo.title)
                .font(isInProgress ? .subheadline.weight(.medium) : .subheadline)
                .foregroundStyle(todo.completed ? .secondary : .primary)
                .strikethrough(todo.completed)
                .opacity(todo.completed ? 0.6 : 1)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)

            Button { onDelete() } label: {
                Image(systemName: "xmark.circle")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture { onTap() }
    }
}
