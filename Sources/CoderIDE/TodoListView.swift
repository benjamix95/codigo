import SwiftUI

struct TodoListView: View {
    @ObservedObject var store: TodoStore
    @State private var newTodoText = ""
    @FocusState private var isNewTodoFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            addTodoRow
            filterRow

            ForEach(store.visibleTodos) { todo in
                TodoRowView(
                    todo: todo,
                    onOpenFile: nil,
                    onStart: { store.setStatus(id: todo.id, status: .inProgress) },
                    onDone: { store.setStatus(id: todo.id, status: .done) },
                    onBlock: { store.setStatus(id: todo.id, status: .blocked) },
                    onDelete: { store.remove(id: todo.id) }
                )
            }

            if store.visibleTodos.isEmpty {
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

    private var filterRow: some View {
        Picker("Filtro", selection: $store.filter) {
            ForEach(TodoFilter.allCases, id: \.self) { f in
                Text(f.rawValue).tag(f)
            }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal, 4)
    }

    private func submitNewTodo() {
        let trimmed = newTodoText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        store.add(title: trimmed)
        newTodoText = ""
    }
}

struct TodoLiveInlineCard: View {
    @ObservedObject var store: TodoStore
    let onOpenFile: (String) -> Void

    var body: some View {
        let items = store.todos
            .filter { $0.status != .done }
            .sorted { $0.updatedAt > $1.updatedAt }
            .prefix(4)
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Todo Live")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(Int(store.completionRatio * 100))%")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.tertiary)
                }
                ProgressView(value: store.completionRatio)
                    .progressViewStyle(.linear)

                ForEach(Array(items)) { todo in
                    TodoRowView(
                        todo: todo,
                        onOpenFile: { onOpenFile($0) },
                        onStart: { store.setStatus(id: todo.id, status: .inProgress) },
                        onDone: { store.setStatus(id: todo.id, status: .done) },
                        onBlock: { store.setStatus(id: todo.id, status: .blocked) },
                        onDelete: { store.remove(id: todo.id) }
                    )
                }
            }
            .padding(10)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.5), in: RoundedRectangle(cornerRadius: 9))
            .overlay(
                RoundedRectangle(cornerRadius: 9)
                    .strokeBorder(DesignSystem.Colors.border.opacity(0.8), lineWidth: 0.6)
            )
        }
    }
}

struct TodoRowView: View {
    let todo: TodoItem
    let onOpenFile: ((String) -> Void)?
    let onStart: () -> Void
    let onDone: () -> Void
    let onBlock: () -> Void
    let onDelete: () -> Void

    private var statusIcon: String {
        switch todo.status {
        case .pending: return "circle"
        case .inProgress: return "play.circle.fill"
        case .blocked: return "exclamationmark.triangle.fill"
        case .done: return "checkmark.circle.fill"
        }
    }

    private var statusColor: Color {
        switch todo.status {
        case .pending: return .secondary
        case .inProgress: return .orange
        case .blocked: return .red
        case .done: return .green
        }
    }

    private var priorityColor: Color {
        switch todo.priority {
        case .low: return .secondary
        case .medium: return .blue
        case .high: return .pink
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .center, spacing: 6) {
                Image(systemName: statusIcon)
                    .font(.subheadline)
                    .foregroundStyle(statusColor)

                Text(todo.title)
                    .font(.subheadline.weight(todo.status == .inProgress ? .semibold : .regular))
                    .foregroundStyle(todo.status == .done ? .secondary : .primary)
                    .strikethrough(todo.status == .done)
                    .opacity(todo.status == .done ? 0.7 : 1)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Text(todo.priority.rawValue.uppercased())
                    .font(.system(size: 9, weight: .bold))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(priorityColor.opacity(0.18), in: Capsule())
                    .foregroundStyle(priorityColor)
            }

            if !todo.notes.isEmpty {
                Text(todo.notes)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            if !todo.linkedFiles.isEmpty {
                HStack(spacing: 4) {
                    ForEach(todo.linkedFiles.prefix(2), id: \.self) { file in
                        Button {
                            onOpenFile?(file)
                        } label: {
                            Text((file as NSString).lastPathComponent)
                                .font(.system(size: 10, weight: .medium, design: .monospaced))
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.blue)
                    }
                }
            }

            HStack(spacing: 8) {
                Button("Start", action: onStart)
                    .buttonStyle(.plain)
                    .font(.caption2)
                Button("Done", action: onDone)
                    .buttonStyle(.plain)
                    .font(.caption2)
                Button("Block", action: onBlock)
                    .buttonStyle(.plain)
                    .font(.caption2)
                    .foregroundStyle(.red)
                Spacer()
                Button {
                    onDelete()
                } label: {
                    Image(systemName: "trash")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.45), in: RoundedRectangle(cornerRadius: 8))
    }
}
