import SwiftUI

private enum SidebarTodoFilter: String, CaseIterable {
    case all = "All"
    case open = "Open"
    case doing = "Doing"
    case done = "Done"
}

struct TodoListView: View {
    @ObservedObject var store: TodoStore
    @State private var newTodoText = ""
    @State private var selectedFilter: SidebarTodoFilter = .open
    @State private var expandedTaskId: UUID?

    private var filteredTodos: [TodoItem] {
        let base: [TodoItem]
        switch selectedFilter {
        case .all: base = store.todos
        case .open: base = store.todos.filter { $0.status == .pending || $0.status == .blocked }
        case .doing: base = store.todos.filter { $0.status == .inProgress }
        case .done: base = store.todos.filter { $0.status == .done }
        }
        return base.sorted {
            if $0.status.rank != $1.status.rank { return $0.status.rank < $1.status.rank }
            if $0.priority.rank != $1.priority.rank { return $0.priority.rank < $1.priority.rank }
            return $0.updatedAt > $1.updatedAt
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                TextField("Aggiungi task...", text: $newTodoText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                Button {
                    submitNewTodo()
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 11, weight: .bold))
                }
                .buttonStyle(.plain)
                .disabled(newTodoText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 5)

            HStack(spacing: 8) {
                ForEach(SidebarTodoFilter.allCases, id: \.self) { filter in
                    Button(filter.rawValue) { selectedFilter = filter }
                        .buttonStyle(.plain)
                        .font(.system(size: 10, weight: selectedFilter == filter ? .semibold : .regular))
                        .foregroundStyle(selectedFilter == filter ? Color.accentColor : .secondary)
                }
            }
            .padding(.horizontal, 6)

            if filteredTodos.isEmpty {
                Text("Nessun task")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 4)
            } else {
                ForEach(filteredTodos.prefix(4)) { todo in
                    row(todo)
                    if expandedTaskId == todo.id {
                        drawer(todo)
                    }
                }
            }
        }
    }

    private func row(_ todo: TodoItem) -> some View {
        let expanded = expandedTaskId == todo.id
        return HStack(spacing: 7) {
            Button {
                toggleStatus(todo)
            } label: {
                Image(systemName: statusIcon(todo.status))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(statusColor(todo.status))
            }
            .buttonStyle(.plain)

            Circle().fill(priorityColor(todo.priority)).frame(width: 5, height: 5)

            Text(todo.title)
                .font(.system(size: 11))
                .strikethrough(todo.status == .done)
                .foregroundStyle(todo.status == .done ? .secondary : .primary)
                .lineLimit(1)

            Spacer()

            Button {
                expandedTaskId = expanded ? nil : todo.id
            } label: {
                Image(systemName: expanded ? "chevron.down" : "chevron.right")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(expanded ? Color.accentColor.opacity(0.10) : Color.clear)
    }

    private func drawer(_ todo: TodoItem) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if !todo.notes.isEmpty {
                Text(todo.notes)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            if !todo.linkedFiles.isEmpty {
                ForEach(todo.linkedFiles.prefix(3), id: \.self) { file in
                    Text((file as NSString).lastPathComponent)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }

            HStack(spacing: 8) {
                Button("Open") { store.setStatus(id: todo.id, status: .pending) }
                Button("Doing") { store.setStatus(id: todo.id, status: .inProgress) }
                Button("Done") { store.setStatus(id: todo.id, status: .done) }
                Spacer()
                Button(role: .destructive) {
                    store.remove(id: todo.id)
                    if expandedTaskId == todo.id { expandedTaskId = nil }
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 10))
                }
            }
            .buttonStyle(.plain)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 4)
    }

    private func submitNewTodo() {
        let trimmed = newTodoText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        store.add(title: trimmed)
        newTodoText = ""
    }

    private func toggleStatus(_ todo: TodoItem) {
        switch todo.status {
        case .pending, .blocked: store.setStatus(id: todo.id, status: .inProgress)
        case .inProgress: store.setStatus(id: todo.id, status: .done)
        case .done: store.setStatus(id: todo.id, status: .pending)
        }
    }

    private func statusIcon(_ status: TodoStatus) -> String {
        switch status {
        case .pending: return "circle"
        case .inProgress: return "play.circle.fill"
        case .blocked: return "exclamationmark.triangle.fill"
        case .done: return "checkmark.circle.fill"
        }
    }

    private func statusColor(_ status: TodoStatus) -> Color {
        switch status {
        case .pending: return .secondary
        case .inProgress: return .orange
        case .blocked: return .red
        case .done: return .green
        }
    }

    private func priorityColor(_ priority: TodoPriority) -> Color {
        switch priority {
        case .low: return .secondary
        case .medium: return .blue
        case .high: return .pink
        }
    }
}

struct TodoLiveInlineCard: View {
    @ObservedObject var store: TodoStore
    let onOpenFile: (String) -> Void

    var body: some View {
        let items = store.todos.filter { $0.status != .done }.prefix(3)
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Text("Todo Live")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                ForEach(Array(items)) { todo in
                    Text("• \(todo.title)")
                        .font(.system(size: 11))
                        .lineLimit(1)
                }
            }
            .padding(.vertical, 4)
        }
    }
}
