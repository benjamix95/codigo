import AppKit
import SwiftUI
import CoderEngine
import UniformTypeIdentifiers

func isPlanBuildEnabled(phase: PlanFlowPhase, hasBuildChoice: Bool) -> Bool {
    switch phase {
    case .proposalReady, .readyToBuild:
        return true
    case .idle:
        return hasBuildChoice
    case .discovery, .awaitingClarification, .building:
        return false
    }
}

/// Pannello laterale stile Cursor per il piano.
/// Top bar fissa (breadcrumb, model picker, Build), contenuto scrollabile sotto.
struct PlanPanelView: View {
    @ObservedObject var todoStore: TodoStore
    @ObservedObject var chatStore: ChatStore
    @ObservedObject var taskActivityStore: TaskActivityStore
    @EnvironmentObject var providerRegistry: ProviderRegistry
    @EnvironmentObject var planHistoryStore: PlanHistoryStore
    let conversationId: UUID?
    let planningState: PlanningState
    let planFlowPhase: PlanFlowPhase
    let onClose: () -> Void
    let onSelectOption: (PlanOption, String?) -> Void
    let onCustomResponse: (String) -> Void
    let onBuild: (String, String?) -> Void
    let onStop: () -> Void

    @State private var planText: String = ""
    @State private var isEditing = false
    @State private var buildHint: String?
    @State private var showDeleteAllHistoryConfirmation = false
    /// Override provider for plan execution (nil = use conversation/global default)
    @State private var planProviderId: String?
    /// Keeps top controls out of the macOS titlebar non-interactive zone.
    private let topInteractiveInset: CGFloat = 22

    private let planColor = DesignSystem.Colors.planColor

    var body: some View {
        VStack(spacing: 0) {
            Color.clear
                .frame(height: topInteractiveInset)
                .allowsHitTesting(false)
            fixedToolbar
            thinSeparator

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Plan Board (steps overview)
                    if let board = chatStore.planBoard(for: conversationId) {
                        planBoardSection(board)
                    }

                    // Domande di chiarimento (se in attesa)
                    if case .awaitingClarification(let questions) = planningState {
                        PlanClarificationView(questions: questions, planColor: planColor)
                    }

                    // Plan Options (if awaiting choice)
                    if case .awaitingChoice(_, let options) = planningState {
                        PlanOptionsView(
                            options: options,
                            planColor: planColor,
                            onSelectOption: { option in
                                onSelectOption(option, planProviderId)
                            },
                            onCustomResponse: onCustomResponse
                        )
                    }

                    // New workspace sempre vuoto
                    planContentSection

                    // History persistente
                    historySection

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
        .onAppear {
            planText = ""
            isEditing = false
        }
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

            if let hint = phaseHint {
                Text(hint)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 6)
            }
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

    private var isPlanFullyBuilt: Bool {
        guard let board = chatStore.planBoard(for: conversationId), !board.steps.isEmpty else {
            return false
        }
        return board.steps.allSatisfy { $0.status == .done } && !chatStore.isLoading
    }

    private var isBuildEnabledByPhase: Bool {
        isPlanBuildEnabled(
            phase: planFlowPhase,
            hasBuildChoice: resolveBuildChoiceText() != nil
        )
    }

    private var phaseHint: String? {
        switch planFlowPhase {
        case .idle:
            return buildHint
        case .discovery:
            return "Analisi in corso: attendi il completamento della discovery."
        case .awaitingClarification:
            return "Servono chiarimenti: rispondi alle domande prima del build."
        case .proposalReady:
            return "Proposta pronta: seleziona/conferma l'opzione e avvia Build."
        case .readyToBuild:
            return "Piano pronto: puoi avviare Build."
        case .building:
            return "Build in esecuzione..."
        }
    }

    private var buildButton: some View {
        let fullyBuilt = isPlanFullyBuilt
        return Group {
            if fullyBuilt {
                Menu {
                    Button {
                        performBuild()
                    } label: {
                        Label("Esegui di nuovo", systemImage: "arrow.clockwise")
                    }
                    .keyboardShortcut(.return, modifiers: [.command])
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark")
                            .font(.system(size: 10, weight: .bold))
                        Text("Built")
                            .font(.system(size: 11, weight: .semibold))
                        Image(systemName: "chevron.down")
                            .font(.system(size: 7, weight: .bold))
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
                .menuStyle(.borderlessButton)
                .fixedSize()
                .help("Plan completato. Clicca per eseguire di nuovo (⌘⏎)")
                .disabled(!isBuildEnabledByPhase)
            } else {
                Button {
                    if chatStore.isLoading {
                        onStop()
                        buildHint = "Build interrotto"
                    } else {
                        performBuild()
                    }
                } label: {
                    HStack(spacing: 4) {
                        if chatStore.isLoading {
                            ProgressView()
                                .controlSize(.mini)
                                .tint(.white)
                        }
                        Text(chatStore.isLoading ? "Building…" : "Build")
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
                    .opacity(chatStore.isLoading ? 0.8 : 1)
                }
                .buttonStyle(PlanBuildButtonStyle())
                .keyboardShortcut(.return, modifiers: [.command])
                .help(chatStore.isLoading ? "Ferma il build (⌘⏎)" : "Esegui il plan (⌘⏎)")
                .disabled(!isBuildEnabledByPhase && !chatStore.isLoading)
            }
        }
    }

    private func performBuild() {
        guard isBuildEnabledByPhase else {
            buildHint = phaseHint ?? "Build non disponibile in questa fase."
            return
        }
        guard let choice = resolveBuildChoiceText() else {
            buildHint = "Nessuna opzione disponibile da eseguire."
            return
        }
        buildHint = "Build avviata..."
        onBuild(choice, planProviderId)
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

    /// Contenuto live dalla conversazione durante streaming; altrimenti planText (buffer locale in edit).
    private var displayPlanContent: String {
        if isEditing { return planText }
        if let conv = chatStore.conversation(for: conversationId),
           let last = conv.messages.last(where: { $0.role == .assistant }),
           !last.content.isEmpty
        { return last.content }
        return planText
    }

    private var planContentSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("New Plan Workspace")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Spacer()
                Button {
                    if !isEditing {
                        planText = displayPlanContent
                    }
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
            } else if !displayPlanContent.isEmpty {
                MarkdownContentView(
                    content: displayPlanContent,
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
                    Text("Workspace vuoto. Seleziona un planning dallo storico o genera un nuovo plan.")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 30)
            }
        }
    }

    private var historySection: some View {
        let conv = chatStore.conversation(for: conversationId)
        let ctxId = conv?.contextId
        let ctxPath = conv?.contextFolderPath
        let items = planHistoryStore.entriesForContext(
            contextId: ctxId,
            contextFolderPath: ctxPath
        )
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("History")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(items.count)")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.tertiary)
                if !items.isEmpty {
                    Button(role: .destructive) {
                        showDeleteAllHistoryConfirmation = true
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 10, weight: .semibold))
                    }
                    .buttonStyle(.plain)
                    .help("Elimina tutta la history")
                }
            }
            if items.isEmpty {
                Text("Nessun planning salvato per questo contesto.")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .padding(.vertical, 6)
            } else {
                ForEach(items) { entry in
                    HStack(alignment: .top, spacing: 8) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(entry.title)
                                .font(.system(size: 12, weight: .medium))
                                .lineLimit(1)
                            Text(entry.createdAt.formatted(date: .abbreviated, time: .shortened))
                                .font(.system(size: 10))
                                .foregroundStyle(.tertiary)
                        }
                        Spacer()
                        Button("Preview") {
                            planHistoryStore.setSelectedEntry(id: entry.id)
                        }
                        .buttonStyle(.plain)
                        .font(.system(size: 10, weight: .medium))
                        Button {
                            guard isBuildEnabledByPhase else {
                                buildHint = phaseHint ?? "Build non disponibile in questa fase."
                                return
                            }
                            planHistoryStore.setSelectedEntry(id: entry.id)
                            let choice = entry.chosenPath?.isEmpty == false
                                ? (entry.chosenPath ?? entry.markdown) : entry.markdown
                            onBuild(choice, planProviderId)
                            planHistoryStore.markRebuilt(id: entry.id)
                            buildHint = "Rebuild avviata..."
                        } label: {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 11, weight: .semibold))
                        }
                        .buttonStyle(.plain)
                        Button {
                            _ = planHistoryStore.duplicateEntry(id: entry.id)
                        } label: {
                            Image(systemName: "doc.on.doc")
                                .font(.system(size: 11, weight: .semibold))
                        }
                        .buttonStyle(.plain)
                        Button {
                            downloadPlan(entry)
                        } label: {
                            Image(systemName: "arrow.down.to.line")
                                .font(.system(size: 11, weight: .semibold))
                        }
                        .buttonStyle(.plain)
                        Button(role: .destructive) {
                            planHistoryStore.deleteEntry(id: entry.id)
                        } label: {
                            Image(systemName: "trash")
                                .font(.system(size: 11, weight: .semibold))
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(8)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(
                                planHistoryStore.selectedEntryId == entry.id
                                    ? DesignSystem.Colors.planColor.opacity(0.12)
                                    : Color(nsColor: .controlBackgroundColor).opacity(0.2)
                            )
                    )
                }
                if let selected = planHistoryStore.findEntry(id: planHistoryStore.selectedEntryId) {
                    Divider()
                    MarkdownContentView(
                        content: selected.markdown,
                        context: nil,
                        onFileClicked: { _ in },
                        textAlignment: .leading
                    )
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
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
        .alert("Elimina tutta la history?", isPresented: $showDeleteAllHistoryConfirmation) {
            Button("Annulla", role: .cancel) {}
            Button("Elimina tutto", role: .destructive) {
                planHistoryStore.deleteAllForContext(contextId: ctxId, contextFolderPath: ctxPath)
            }
        } message: {
            Text("Tutti i planning salvati per questo contesto verranno eliminati definitivamente.")
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

    private func resolveBuildChoiceText() -> String? {
        let workspaceText = planText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !workspaceText.isEmpty {
            return workspaceText
        }
        if let selected = planHistoryStore.findEntry(id: planHistoryStore.selectedEntryId) {
            if let chosen = selected.chosenPath?.trimmingCharacters(in: .whitespacesAndNewlines),
               !chosen.isEmpty {
                return chosen
            }
            return selected.markdown
        }
        if let board = chatStore.planBoard(for: conversationId) {
            if let chosen = board.chosenPath?.trimmingCharacters(in: .whitespacesAndNewlines),
               !chosen.isEmpty {
                return chosen
            }
            if let first = board.options.sorted(by: { $0.id < $1.id }).first {
                return first.fullText
            }
        }
        if case .awaitingChoice(_, let options) = planningState,
           let first = options.sorted(by: { $0.id < $1.id }).first {
            return first.fullText
        }
        return nil
    }

    private func downloadPlan(_ entry: PlanHistoryEntry) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        panel.canCreateDirectories = true
        let baseName = entry.title.isEmpty ? "PLAN" : entry.title
        panel.nameFieldStringValue = "\(baseName.replacingOccurrences(of: " ", with: "_")).md"
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            try? entry.markdown.write(to: url, atomically: true, encoding: .utf8)
        }
    }
}

private struct PlanBuildButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .brightness(configuration.isPressed ? -0.06 : 0)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
