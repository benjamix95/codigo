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
        return store.sortedCanonicalFirstTodos(base)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                TextField("Add task...", text: $newTodoText)
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
                Text("No tasks")
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
        return HStack(alignment: .firstTextBaseline, spacing: 7) {
            Button {
                toggleStatus(todo)
            } label: {
                Image(systemName: todo.status.icon)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(todo.status.color)
            }
            .buttonStyle(.plain)

            Circle().fill(todo.priority.color).frame(width: 5, height: 5)

            VStack(alignment: .leading, spacing: 3) {
                Text(todo.title)
                    .font(.system(size: 11, weight: .medium))
                    .strikethrough(todo.status == .done)
                    .foregroundStyle(todo.status == .done ? .secondary : .primary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                if todo.status == .inProgress, !todo.activeForm.isEmpty {
                    Text(todo.activeForm)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(DesignSystem.Colors.planColor.opacity(0.8))
                        .lineLimit(1)
                }
                HStack(spacing: 6) {
                    Text(todo.status.label)
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(todo.status.color)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(todo.status.color.opacity(0.14), in: Capsule())
                    Text(todo.priority.rawValue.uppercased())
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .foregroundStyle(todo.priority.color)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(todo.priority.color.opacity(0.12), in: Capsule())
                }
            }

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
        .padding(.vertical, 5)
        .background(expanded ? DesignSystem.Colors.backgroundElevated : Color.clear)
    }

    private func drawer(_ todo: TodoItem) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if !todo.notes.isEmpty {
                Text(todo.notes)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
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

}

struct TodoLiveInlineCard: View {
    @ObservedObject var store: TodoStore
    let onOpenFile: (String) -> Void

    private var displayedTodos: [TodoItem] {
        Array(store.sortedCanonicalFirstTodos().prefix(8))
    }

    var body: some View {
        let items = displayedTodos
        let doneCount = items.filter { $0.status == .done }.count
        let total = items.count

        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                // Header
                HStack(spacing: 5) {
                    Text("\(doneCount) of \(total)")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                        .contentTransition(.numericText())
                    Text(doneCount == total ? "Completed" : "To-dos")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.bottom, 8)

                // Items
                VStack(alignment: .leading, spacing: 1) {
                    ForEach(items) { todo in
                        todoRow(todo)
                    }
                }
                .animation(.easeOut(duration: 0.2), value: items.map { "\($0.id)-\($0.status.rawValue)" })
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color(nsColor: .textBackgroundColor).opacity(0.3))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5)
            )
        }
    }

    private func todoRow(_ todo: TodoItem) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            switch todo.status {
            case .inProgress:
                Image(systemName: "arrow.right")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.primary.opacity(0.5))
                    .frame(width: 12)
            case .done:
                Image(systemName: "checkmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.tertiary)
                    .frame(width: 12)
            case .pending, .blocked:
                Circle()
                    .fill(Color.primary.opacity(0.12))
                    .frame(width: 5, height: 5)
                    .frame(width: 12)
            }

            Text(todo.title)
                .font(.system(size: 11.5))
                .foregroundStyle(todo.status == .done ? .tertiary : .primary)
                .strikethrough(todo.status == .done, color: .primary.opacity(0.25))
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 3)
    }
}
