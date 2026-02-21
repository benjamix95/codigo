import SwiftUI
import CoderEngine

/// Pannello laterale stile Cursor per il piano.
/// Top bar fissa (breadcrumb, model picker, Build), contenuto scrollabile sotto.
struct PlanPanelView: View {
    @ObservedObject var todoStore: TodoStore
    @ObservedObject var chatStore: ChatStore
    @ObservedObject var taskActivityStore: TaskActivityStore
    @EnvironmentObject var providerRegistry: ProviderRegistry
    let conversationId: UUID?
    let planningState: PlanningState
    let onClose: () -> Void
    let onSelectOption: (PlanOption) -> Void
    let onCustomResponse: (String) -> Void

    @State private var planText: String = ""
    @State private var isEditing = false
    /// Override provider for plan execution (nil = use conversation/global default)
    @State private var planProviderId: String?

    private let planColor = DesignSystem.Colors.planColor

    var body: some View {
        VStack(spacing: 0) {
            fixedToolbar
            thinSeparator

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Plan Board (steps overview)
                    if let board = chatStore.planBoard(for: conversationId) {
                        planBoardSection(board)
                    }

                    // Plan Options (if awaiting choice)
                    if case .awaitingChoice(_, let options) = planningState {
                        PlanOptionsView(
                            options: options,
                            planColor: planColor,
                            onSelectOption: onSelectOption,
                            onCustomResponse: onCustomResponse
                        )
                    }

                    // Plan content
                    planContentSection

                    // Walkthrough (appears when plan completes)
                    if let board = chatStore.planBoard(for: conversationId),
                       let wt = board.walkthroughMarkdown, !wt.isEmpty {
                        walkthroughSection(wt)
                    }

                    // Todos
                    if !todoStore.todos.isEmpty {
                        todosSection
                    }

                    // Live activity trace
                    if !taskActivityStore.activities.isEmpty {
                        traceSection
                    }
                }
                .padding(16)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            thinSeparator
            bottomBar
        }
        .background(DesignSystem.Colors.backgroundDeep)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(DesignSystem.Colors.border.opacity(0.4), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.1), radius: 8, y: 2)
        .onAppear { loadPlanText() }
    }

    // MARK: - Fixed Toolbar (Cursor-style)

    private var fixedToolbar: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                // Breadcrumb
                breadcrumb

                Spacer(minLength: 4)

                // Model/provider picker
                providerPicker

                // Build button
                buildButton

                // Close
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.tertiary)
                        .frame(width: 20, height: 20)
                        .background(
                            Color(nsColor: .controlBackgroundColor).opacity(0.4),
                            in: RoundedRectangle(cornerRadius: 5, style: .continuous)
                        )
                }
                .buttonStyle(.plain)
                .help("Chiudi (Shift+Tab)")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
    }

    // MARK: - Breadcrumb

    private var breadcrumb: some View {
        HStack(spacing: 4) {
            Text("Plans")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
            Image(systemName: "chevron.right")
                .font(.system(size: 7, weight: .bold))
                .foregroundStyle(.quaternary)
            HStack(spacing: 3) {
                Image(systemName: "doc.text")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(planColor)
                Text(planFileName)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
            }
        }
    }

    private var planFileName: String {
        guard let conv = chatStore.conversation(for: conversationId) else {
            return "plan.md"
        }
        let slug = conv.title
            .lowercased()
            .replacingOccurrences(of: " ", with: "_")
            .prefix(30)
        return "\(slug).plan.md"
    }

    // MARK: - Provider Picker

    private var providerPicker: some View {
        Menu {
            ForEach(Array(providerRegistry.providers.enumerated()), id: \.offset) { _, provider in
                Button {
                    planProviderId = provider.id
                } label: {
                    HStack {
                        Text(provider.displayName)
                        if activeProviderId == provider.id {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }

            Divider()

            Button {
                planProviderId = nil
            } label: {
                HStack {
                    Text("Usa default")
                    if planProviderId == nil {
                        Image(systemName: "checkmark")
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text(activeProviderLabel)
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(.secondary)
                Image(systemName: "chevron.down")
                    .font(.system(size: 7, weight: .bold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Color(nsColor: .controlBackgroundColor).opacity(0.4),
                in: RoundedRectangle(cornerRadius: 5, style: .continuous)
            )
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    private var activeProviderId: String {
        planProviderId ?? providerRegistry.selectedProviderId ?? ""
    }

    private var activeProviderLabel: String {
        let targetId = activeProviderId
        if let p = providerRegistry.providers.first(where: { $0.id == targetId }) {
            return p.displayName
        }
        return "Provider"
    }

    // MARK: - Build Button

    private var buildButton: some View {
        Button {
            // TODO: wire up plan execution with activeProviderId
        } label: {
            HStack(spacing: 4) {
                Text("Build")
                    .font(.system(size: 11, weight: .semibold))
                HStack(spacing: 1) {
                    Image(systemName: "command")
                        .font(.system(size: 7, weight: .bold))
                    Image(systemName: "return")
                        .font(.system(size: 7, weight: .bold))
                }
                .foregroundStyle(.white.opacity(0.7))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                DesignSystem.Colors.planGradient,
                in: RoundedRectangle(cornerRadius: 6, style: .continuous)
            )
        }
        .buttonStyle(.plain)
        .help("Esegui il plan (⌘⏎)")
    }

    // MARK: - Bottom Bar

    private var bottomBar: some View {
        HStack(spacing: 6) {
            let total = todoStore.todos.count
            let done = todoStore.todos.filter { $0.status == .done }.count
            if total > 0 {
                Text("\(done) To-dos · Completed In Order")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.tertiary)
            }
            Spacer()
            Button {
                // TODO: Add new todo
            } label: {
                HStack(spacing: 3) {
                    Image(systemName: "plus")
                        .font(.system(size: 8, weight: .bold))
                    Text("New Todo")
                        .font(.system(size: 10, weight: .medium))
                }
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    Color(nsColor: .controlBackgroundColor).opacity(0.3),
                    in: RoundedRectangle(cornerRadius: 5, style: .continuous)
                )
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    // MARK: - Plan Content

    private var planContentSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Spacer()
                Button {
                    isEditing.toggle()
                } label: {
                    Text(isEditing ? "Fine" : "Modifica")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(planColor)
                }
                .buttonStyle(.plain)
            }

            if isEditing {
                TextEditor(text: $planText)
                    .font(.system(size: 12, design: .monospaced))
                    .scrollContentBackground(.hidden)
                    .padding(10)
                    .frame(minHeight: 180)
                    .background(
                        Color(nsColor: .controlBackgroundColor).opacity(0.3),
                        in: RoundedRectangle(cornerRadius: 8)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(DesignSystem.Colors.border.opacity(0.4), lineWidth: 0.5)
                    )
            } else if !planText.isEmpty {
                MarkdownContentView(
                    content: planText,
                    context: nil,
                    onFileClicked: { _ in },
                    textAlignment: .leading
                )
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                HStack(spacing: 8) {
                    Image(systemName: "doc.text")
                        .font(.system(size: 16))
                        .foregroundStyle(.quaternary)
                    Text("Usa /plan nella chat per generare un piano")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 30)
            }
        }
    }

    // MARK: - Plan Board

    private func planBoardSection(_ board: PlanBoard) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(board.goal)
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(2)

            let total = board.steps.count
            let done = board.steps.filter { $0.status == .done }.count
            let progress = total > 0 ? Double(done) / Double(total) : 0

            ProgressView(value: progress)
                .progressViewStyle(.linear)
                .tint(planColor)

            ForEach(board.steps.prefix(20)) { step in
                HStack(spacing: 6) {
                    Image(systemName: stepIcon(step.status))
                        .font(.system(size: 9))
                        .foregroundStyle(stepColor(step.status))
                        .frame(width: 14)
                    Text(step.title)
                        .font(.system(size: 11))
                        .lineLimit(1)
                    Spacer()
                }
            }
        }
        .padding(12)
        .background(
            Color(nsColor: .controlBackgroundColor).opacity(0.3),
            in: RoundedRectangle(cornerRadius: 10)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(DesignSystem.Colors.border.opacity(0.3), lineWidth: 0.5)
        )
    }

    // MARK: - Todos Section

    private var todosSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "checklist")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(planColor)
                Text("Todo")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                let total = todoStore.todos.count
                let done = todoStore.todos.filter { $0.status == .done }.count
                Text("\(done)/\(total)")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }

            ForEach(todoStore.todos) { todo in
                HStack(spacing: 8) {
                    Button {
                        let newStatus: TodoStatus = todo.status == .done ? .pending : .done
                        todoStore.setStatus(id: todo.id, status: newStatus)
                    } label: {
                        Image(systemName: todo.status == .done ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 13))
                            .foregroundStyle(
                                todo.status == .done
                                    ? planColor
                                    : Color.secondary.opacity(0.4)
                            )
                    }
                    .buttonStyle(.plain)

                    Text(todo.title)
                        .font(.system(size: 12))
                        .strikethrough(todo.status == .done, color: .secondary)
                        .foregroundStyle(todo.status == .done ? .tertiary : .primary)
                        .lineLimit(2)
                }
                .padding(.vertical, 2)
            }
        }
        .padding(12)
        .background(
            Color(nsColor: .controlBackgroundColor).opacity(0.2),
            in: RoundedRectangle(cornerRadius: 10)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(DesignSystem.Colors.border.opacity(0.3), lineWidth: 0.5)
        )
    }

    // MARK: - Trace Section

    private var traceSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: "chart.bar.doc.horizontal")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.tertiary)
                Text("Attività")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            PlanLiveTraceView(activities: taskActivityStore.activities)
        }
    }

    // MARK: - Walkthrough Section

    private func walkthroughSection(_ markdown: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(planColor.opacity(0.15))
                        .frame(width: 24, height: 24)
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(planColor)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text("Walkthrough")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.primary)
                    Text("Riepilogo completamento")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.tertiary)
                }
                Spacer()
                Image(systemName: "doc.text.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(planColor.opacity(0.5))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                planColor.opacity(0.04)
            )

            Rectangle()
                .fill(planColor.opacity(0.12))
                .frame(height: 0.5)

            // Content
            MarkdownContentView(
                content: markdown,
                context: nil,
                onFileClicked: { _ in },
                textAlignment: .leading
            )
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(
            Color(nsColor: .controlBackgroundColor).opacity(0.15)
        )
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(planColor.opacity(0.15), lineWidth: 0.5)
        )
    }

    // MARK: - Helpers

    private var thinSeparator: some View {
        Rectangle()
            .fill(DesignSystem.Colors.border.opacity(0.4))
            .frame(height: 0.5)
    }

    private func stepIcon(_ status: PlanStepStatus) -> String {
        switch status {
        case .pending: return "circle"
        case .running: return "play.circle.fill"
        case .done: return "checkmark.circle.fill"
        case .failed: return "xmark.circle.fill"
        }
    }

    private func stepColor(_ status: PlanStepStatus) -> Color {
        switch status {
        case .pending: return .secondary
        case .running: return .orange
        case .done: return .green
        case .failed: return .red
        }
    }

    private func loadPlanText() {
        if let conv = chatStore.conversation(for: conversationId),
           let lastAssistant = conv.messages.last(where: { $0.role == .assistant }),
           !lastAssistant.content.isEmpty
        {
            let opts = PlanOptionsParser.parse(from: lastAssistant.content)
            if opts.count > 1 || (opts.first?.fullText.count ?? 0) > 50 {
                planText = lastAssistant.content
            }
        }
    }
}
