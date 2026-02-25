import AppKit
import SwiftUI
import CoderEngine
import UniformTypeIdentifiers

func isPlanBuildEnabled(phase: PlanFlowPhase, hasBuildChoice: Bool, allowIdleRebuild: Bool = false) -> Bool {
    switch phase {
    case .proposalReady, .readyToBuild:
        return true
    case .idle:
        return allowIdleRebuild && hasBuildChoice
    case .analyzing, .questioning, .generating, .building:
        return false
    }
}

func planBuildDisabledReason(
    phase: PlanFlowPhase,
    hasBuildChoice: Bool,
    providerExecutionCapable: Bool
) -> String? {
    if !providerExecutionCapable {
        return "Provider not ready: select an authenticated execution-capable provider."
    }
    if !hasBuildChoice {
        return "No executable option available."
    }
    switch phase {
    case .idle:
        return "Build unavailable in idle state: generate or select a plan first."
    case .analyzing:
        return "Codebase analysis in progress: wait for completion."
    case .questioning:
        return "Clarifications required: answer the questions before Build."
    case .generating:
        return "Plan generation in progress: wait for completion."
    case .building:
        return "Build in progress..."
    case .proposalReady, .readyToBuild:
        return nil
    }
}

func hasPlanContext(
    phase: PlanFlowPhase,
    planningState: PlanningState,
    hasPlanBoard: Bool,
    hasSelectedHistoryEntry: Bool
) -> Bool {
    if [.analyzing, .questioning, .generating, .proposalReady, .readyToBuild, .building]
        .contains(phase)
    {
        return true
    }
    if planningState != .idle {
        return true
    }
    return hasPlanBoard || hasSelectedHistoryEntry
}

func shouldMirrorAssistantContentInPlanWorkspace(hasPlanContext: Bool) -> Bool {
    hasPlanContext
}

/// Cursor-style side panel for planning.
/// Fixed top bar (breadcrumb, model picker, Build), with scrollable content below.
struct PlanPanelView: View {
    @ObservedObject var todoStore: TodoStore
    @ObservedObject var chatStore: ChatStore
    @ObservedObject var taskActivityStore: TaskActivityStore
    @EnvironmentObject var providerRegistry: ProviderRegistry
    @EnvironmentObject var planHistoryStore: PlanHistoryStore
    let conversationId: UUID?
    /// True only when the current task belongs to this conversation (prevents "Building…" on other threads).
    let isCurrentConversationLoading: Bool
    let planningState: PlanningState
    let planFlowPhase: PlanFlowPhase
    /// Live streaming content from multi-turn plan flow (displayed during analyzing/questioning/generating phases).
    let planStreamingContent: String
    let showHistorySection: Bool
    let workspaceSource: PlanPanelPresentationSource
    let onClose: () -> Void
    let onSelectOption: (PlanOption, String?) -> Void
    let onCustomResponse: (String) -> Void
    let onSubmitClarificationAnswers: (PlanClarificationSubmission) -> Void
    let onBuild: (String, String?, Bool) -> Void
    let onStop: () -> Void
    /// Called when the user selects a history entry with executable content (enables main Build button).
    var onHistoryEntrySelectedForBuild: (() -> Void)? = nil

    @State private var planText: String = ""
    @State private var isEditing = false
    @State private var buildHint: String?
    @State private var showDeleteAllHistoryConfirmation = false
    @State private var walkthroughExpanded = false
    @State private var historySelectionVersion = 0
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
                    // 1) Progress (analyzing/questioning/generating)
                    if planFlowPhase == .analyzing || planFlowPhase == .questioning || planFlowPhase == .generating {
                        PlanPhaseProgressView(phase: planFlowPhase)
                    }

                    // 2) Clarification questions (only when truly waiting)
                    if case .awaitingClarification(let questions) = planningState {
                        if let questionnaire = PlanOptionsParser.parseClarificationQuestionnaire(from: questions) {
                            PlanClarificationWizardView(
                                questionnaire: questionnaire,
                                planColor: planColor,
                                onSubmit: onSubmitClarificationAnswers
                            )
                            .id("plan-clarification-wizard-\(questions.hashValue)")
                        } else {
                            PlanClarificationView(questions: questions, planColor: planColor)
                        }
                    }

                    // 3) Option chooser (proposal ready)
                    if case .awaitingChoice(_, let options) = planningState {
                        PlanOptionsView(
                            options: options,
                            selectedOptionId: selectedOptionId(in: options),
                            planColor: planColor,
                            onSelectOption: { option in
                                onSelectOption(option, planProviderId)
                            },
                            onCustomResponse: onCustomResponse
                        )
                    }

                    // 4) Final todos
                    if !canonicalPlanTodos.isEmpty {
                        todosSection
                    }

                    // 5) Mermaid (if present)
                    if let firstMermaid = extractedMermaidBlocks.first {
                        MermaidDiagramView(
                            mermaidCode: firstMermaid,
                            accentColor: planColor
                        )
                    }

                    // 6) Final plan body (cause/approach), clean and deduplicated
                    planContentSection

                    // 7) Live activity (compact)
                    if !taskActivityStore.activities.isEmpty {
                        traceSection
                    }

                    // 8) Walkthrough (compact + expandable)
                    if let board = chatStore.planBoard(for: conversationId),
                       let wt = board.walkthroughMarkdown, !wt.isEmpty {
                        walkthroughSection(wt)
                    }

                    // 9) History (manual panel opening only)
                    if showHistorySection {
                        historySection
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
            buildHint = nil
            walkthroughExpanded = false
        }
        .onChange(of: conversationId) { _, _ in
            // New conversation => plan panel should immediately reflect the new context.
            planText = ""
            isEditing = false
            buildHint = nil
            walkthroughExpanded = false
            historySelectionVersion = 0
        }
        .onReceive(NotificationCenter.default.publisher(for: ChatPanelView.planBuildShortcutNotification)) { _ in
            performBuild()
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
                .help("Close (Shift+Tab)")
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
                if isPlanExecutionProviderIdAllowed(provider.id) {
                    Button {
                        planProviderId = provider.id
                    } label: {
                        HStack {
                            Text(provider.displayName)
                            if !provider.isAuthenticated() {
                                Text("Not Auth")
                                    .font(.system(size: 9, weight: .semibold))
                                    .foregroundStyle(.secondary)
                            } else if !ProviderSupport.isPlanBuildExecutionCapableProvider(
                                id: provider.id,
                                registry: providerRegistry
                            ) {
                                Text("Not executable")
                                    .font(.system(size: 9, weight: .semibold))
                                    .foregroundStyle(.orange)
                            }
                            if activeProviderId == provider.id {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                    .disabled(
                        !provider.isAuthenticated()
                            || !ProviderSupport.isPlanBuildExecutionCapableProvider(
                                id: provider.id,
                                registry: providerRegistry
                            )
                    )
                }
            }

            Divider()

            Button {
                planProviderId = nil
            } label: {
                HStack {
                    Text("Use default")
                    if planProviderId == nil {
                        Image(systemName: "checkmark")
                    }
                }
            }
        } label: {
            HStack(spacing: 6) {
                Text(activeProviderLabel)
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(.secondary)
                executionCapabilityBadge
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
        if let override = planProviderId,
           isPlanExecutionProviderIdAllowed(override),
           ProviderSupport.isPlanBuildExecutionCapableProvider(id: override, registry: providerRegistry),
           providerRegistry.provider(for: override)?.isAuthenticated() == true {
            return override
        }
        if let selected = providerRegistry.selectedProviderId,
           isPlanExecutionProviderIdAllowed(selected),
           ProviderSupport.isPlanBuildExecutionCapableProvider(id: selected, registry: providerRegistry),
           providerRegistry.provider(for: selected)?.isAuthenticated() == true {
            return selected
        }
        if let firstAuthenticated = providerRegistry.providers.first(where: {
            isPlanExecutionProviderIdAllowed($0.id)
                && ProviderSupport.isPlanBuildExecutionCapableProvider(id: $0.id, registry: providerRegistry)
                && $0.isAuthenticated()
        }) {
            return firstAuthenticated.id
        }
        return "codex-cli"
    }

    private var activeProviderLabel: String {
        let targetId = activeProviderId
        if let p = providerRegistry.providers.first(where: { $0.id == targetId }) {
            return p.displayName
        }
        return "Provider"
    }

    private var isActiveProviderExecutionCapable: Bool {
        guard isPlanExecutionProviderIdAllowed(activeProviderId) else { return false }
        guard providerRegistry.provider(for: activeProviderId)?.isAuthenticated() == true else {
            return false
        }
        return ProviderSupport.isPlanBuildExecutionCapableProvider(
            id: activeProviderId,
            registry: providerRegistry
        )
    }

    @ViewBuilder
    private var executionCapabilityBadge: some View {
        Text(isActiveProviderExecutionCapable ? "Execution-capable" : "Not executable")
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(isActiveProviderExecutionCapable ? .green : .orange)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill((isActiveProviderExecutionCapable ? Color.green : Color.orange).opacity(0.16))
            )
    }

    // MARK: - Build Button

    private var isPlanFullyBuilt: Bool {
        guard let board = chatStore.planBoard(for: conversationId), !board.steps.isEmpty else {
            return false
        }
        return board.steps.allSatisfy { $0.status == .done } && !isCurrentConversationLoading
    }

    private var isBuildEnabledByPhase: Bool {
        isPlanBuildEnabled(
            phase: planFlowPhase,
            hasBuildChoice: resolvedBuildChoice != nil,
            allowIdleRebuild: false
        )
    }

    private var buildDisabledReason: String? {
        planBuildDisabledReason(
            phase: planFlowPhase,
            hasBuildChoice: resolvedBuildChoice != nil,
            providerExecutionCapable: isActiveProviderExecutionCapable
        )
    }

    private var resolvedBuildChoice: (text: String, isFallback: Bool)? {
        resolveBuildChoice()
    }

    private var phaseHint: String? {
        switch planFlowPhase {
        case .idle:
            return buildHint ?? buildDisabledReason
        case .analyzing:
            return "Codebase analysis in progress…"
        case .questioning:
            return "Waiting for clarifications…"
        case .generating:
            return "Plan generation in progress…"
        case .proposalReady:
            if let reason = buildDisabledReason {
                return reason
            }
            return "Proposal ready: select/confirm an option and start Build."
        case .readyToBuild:
            if let reason = buildDisabledReason {
                return reason
            }
            return "Plan ready: you can start Build."
        case .building:
            return "Build in progress..."
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
                        Label("Run again", systemImage: "arrow.clockwise")
                    }
                    Button {
                        downloadCurrentPlan()
                    } label: {
                        Label("Download .md", systemImage: "arrow.down.doc")
                    }
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
                .help("Plan completed. Click to execute again (⌘⏎)")
                .disabled(!isBuildEnabledByPhase)
            } else {
                Button {
                    if isCurrentConversationLoading {
                        onStop()
                        buildHint = "Build interrupted"
                    } else {
                        performBuild()
                    }
                } label: {
                    HStack(spacing: 4) {
                        if isCurrentConversationLoading {
                            ProgressView()
                                .controlSize(.mini)
                                .tint(.white)
                        }
                        Text(isCurrentConversationLoading ? "Building…" : (resolvedBuildChoice?.isFallback == true ? "Build (fallback)" : "Build"))
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
                    .opacity(isCurrentConversationLoading ? 0.8 : 1)
                }
                .keyboardShortcut(.return, modifiers: [.command])
                .buttonStyle(PlanBuildButtonStyle())
                .help(isCurrentConversationLoading ? "Stop build (⌘⏎)" : (buildDisabledReason ?? "Run plan (⌘⏎)"))
                .disabled(!isBuildEnabledByPhase && !isCurrentConversationLoading)
            }
        }
    }

    private func performBuild() {
        guard isBuildEnabledByPhase else {
            buildHint = buildDisabledReason ?? phaseHint ?? "Build unavailable in this phase."
            return
        }
        guard let choice = resolvedBuildChoice?.text else {
            buildHint = "No executable option available."
            return
        }
        let hasRequiredTodoHeader = PlanOptionsParser.hasRequiredTodoHeader(choice)
        let extractedTodos = PlanOptionsParser.extractTodosFromOptionText(choice)
        guard hasRequiredTodoHeader, !extractedTodos.isEmpty else {
            buildHint = "Build blocked: selected plan must include an explicit `## Todo` section with checklist items."
            return
        }
        buildHint = "Build started..."
        onBuild(choice, planProviderId, false)
    }

    // MARK: - Bottom Bar

    private var bottomBar: some View {
        HStack(spacing: 6) {
            let total = canonicalPlanTodos.count
            let done = canonicalPlanTodos.filter { $0.status == .done }.count
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

    /// Live conversation content while streaming; otherwise planText (local edit buffer).
    /// During multi-turn plan phases, prefer planStreamingContent which is routed directly from the flow.
    private var displayPlanContent: String {
        if isEditing { return planText }

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

        // During active plan phases, show streaming content from the multi-turn flow.
        if [.analyzing, .questioning, .generating].contains(planFlowPhase), !planStreamingContent.isEmpty {
            return planStreamingContent
        }

        let hasBoard = chatStore.planBoard(for: conversationId) != nil
        let hasSelectedHistoryEntry = planHistoryStore.selectedEntryId != nil
        let hasContext = hasPlanContext(
            phase: planFlowPhase,
            planningState: planningState,
            hasPlanBoard: hasBoard,
            hasSelectedHistoryEntry: hasSelectedHistoryEntry
        )
        if shouldMirrorAssistantContentInPlanWorkspace(hasPlanContext: hasContext),
           let conv = chatStore.conversation(for: conversationId),
           let last = conv.messages.last(where: { $0.role == .assistant }),
           !last.content.isEmpty
        {
            return last.content
        }
        return planText
    }

    private var displayPlanBodyContent: String {
        PlanOptionsParser.extractFinalPlanBodyExcludingQuestionsOptionsTodos(displayPlanContent)
    }

    private var planContentSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Plan")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    if !isEditing {
                        planText = displayPlanContent
                    }
                    isEditing.toggle()
                } label: {
                    Text(isEditing ? "Done" : "Edit")
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
            } else if (planFlowPhase == .analyzing || planFlowPhase == .questioning || planFlowPhase == .generating) && isCurrentConversationLoading {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.regular)
                        .scaleEffect(0.8)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Analysis in progress")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.primary)
                        Text("The provider is exploring the codebase…")
                            .font(.system(size: 11, weight: .regular))
                            .foregroundStyle(.tertiary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 24)
                .padding(.horizontal, 12)
            } else if !displayPlanBodyContent.isEmpty {
                MarkdownContentView(
                    content: displayPlanBodyContent,
                    context: nil,
                    onFileClicked: { _ in },
                    textAlignment: .leading
                )
                .frame(maxWidth: .infinity, alignment: .leading)
                .id("workspace-\(planHistoryStore.selectedEntryId?.uuidString ?? "current")-\(historySelectionVersion)")
            } else {
                HStack(spacing: 8) {
                    Image(systemName: "doc.text")
                        .font(.system(size: 16))
                        .foregroundStyle(.quaternary)
                    Text("The final plan will appear here when ready.")
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
                if workspaceSource == .manualShortcut {
                    Text("manual")
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.55))
                        )
                }
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
                    .help("Delete all history")
                }
            }
            if items.isEmpty {
                Text("No saved plans for this context.")
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
                            if planHistoryStore.selectedEntryId == entry.id {
                                planHistoryStore.setSelectedEntry(id: nil)
                            }
                            planHistoryStore.setSelectedEntry(id: entry.id)
                            historySelectionVersion &+= 1
                            let choice = entry.chosenPath?.isEmpty == false
                                ? (entry.chosenPath ?? entry.markdown) : entry.markdown
                            if PlanOptionsParser.hasRequiredTodoHeader(choice),
                               !PlanOptionsParser.extractTodosFromOptionText(choice).isEmpty {
                                onHistoryEntrySelectedForBuild?()
                            }
                        }
                        .buttonStyle(.plain)
                        .font(.system(size: 10, weight: .medium))
                        Button {
                            guard isPlanBuildEnabled(
                                phase: planFlowPhase,
                                hasBuildChoice: true,
                                allowIdleRebuild: true
                            ) else {
                                buildHint = phaseHint ?? "Build unavailable in this phase."
                                return
                            }
                            planHistoryStore.setSelectedEntry(id: entry.id)
                            let choice = entry.chosenPath?.isEmpty == false
                                ? (entry.chosenPath ?? entry.markdown) : entry.markdown
                            let hasRequiredTodoHeader = PlanOptionsParser.hasRequiredTodoHeader(choice)
                            let extractedTodos = PlanOptionsParser.extractTodosFromOptionText(choice)
                            guard hasRequiredTodoHeader, !extractedTodos.isEmpty else {
                                buildHint = "Build blocked: selected plan must include an explicit `## Todo` section with checklist items."
                                return
                            }
                            onBuild(choice, planProviderId, true)
                            planHistoryStore.markRebuilt(id: entry.id)
                            historySelectionVersion &+= 1
                            buildHint = "Rebuild started..."
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
                            if planHistoryStore.selectedEntryId == entry.id {
                                historySelectionVersion &+= 1
                            }
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
        .alert("Delete all history?", isPresented: $showDeleteAllHistoryConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Delete all", role: .destructive) {
                planHistoryStore.deleteAllForContext(contextId: ctxId, contextFolderPath: ctxPath)
            }
        } message: {
            Text("All saved planning entries for this context will be permanently deleted.")
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

    // MARK: - Mermaid Blocks

    /// Extract mermaid diagram blocks from the current plan content.
    private var extractedMermaidBlocks: [String] {
        let content = displayPlanContent
        guard !content.isEmpty else { return [] }
        return PlanOptionsParser.extractMermaidBlocksForDisplay(content)
    }

    private var canonicalPlanTodos: [TodoItem] {
        let canonical = todoStore.todos.filter { $0.isPlanCanonical }
        return todoStore.sortedCanonicalFirstTodos(canonical)
    }

    private var todosSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "checklist")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(planColor)
                Text("Todo (Plan)")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                let total = canonicalPlanTodos.count
                let done = canonicalPlanTodos.filter { $0.status == .done }.count
                Text("\(done)/\(total)")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }

            ForEach(canonicalPlanTodos) { todo in
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
        CompactActivityTraceView(
            activities: taskActivityStore.activities,
            accentColor: planColor,
            title: "Activity"
        )
    }

    // MARK: - Walkthrough Section

    private func walkthroughSection(_ markdown: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeOut(duration: 0.18)) {
                    walkthroughExpanded.toggle()
                }
            } label: {
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
                        Text(walkthroughExpanded ? "Hide summary" : "Show summary")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.tertiary)
                    }
                    Spacer()
                    Image(systemName: walkthroughExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(planColor.opacity(0.04))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if walkthroughExpanded {
                Rectangle()
                    .fill(planColor.opacity(0.12))
                    .frame(height: 0.5)

                MarkdownContentView(
                    content: markdown,
                    context: nil,
                    onFileClicked: { _ in },
                    textAlignment: .leading
                )
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
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

    private func resolveBuildChoice() -> (text: String, isFallback: Bool)? {
        let workspaceText = planText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !workspaceText.isEmpty {
            return (workspaceText, false)
        }
        if let selected = planHistoryStore.findEntry(id: planHistoryStore.selectedEntryId) {
            if let chosen = selected.chosenPath?.trimmingCharacters(in: .whitespacesAndNewlines),
               !chosen.isEmpty {
                return (chosen, false)
            }
            return (selected.markdown, false)
        }
        if let board = chatStore.planBoard(for: conversationId) {
            if let chosen = board.chosenPath?.trimmingCharacters(in: .whitespacesAndNewlines),
               !chosen.isEmpty {
                return (chosen, false)
            }
            if let first = board.options.sorted(by: { $0.id < $1.id }).first {
                return (first.fullText, PlanOptionsParser.isFallbackOption(first))
            }
        }
        if case .awaitingChoice(_, let options) = planningState,
           let first = options.sorted(by: { $0.id < $1.id }).first {
            return (first.fullText, PlanOptionsParser.isFallbackOption(first))
        }
        return nil
    }

    private func selectedOptionId(in options: [PlanOption]) -> Int? {
        guard !options.isEmpty else { return nil }
        if let board = chatStore.planBoard(for: conversationId),
           let chosen = board.chosenPath?.trimmingCharacters(in: .whitespacesAndNewlines),
           !chosen.isEmpty,
           let match = options.first(where: { normalizedPlanText($0.fullText) == normalizedPlanText(chosen) })
        {
            return match.id
        }
        if let selected = planHistoryStore.findEntry(id: planHistoryStore.selectedEntryId),
           let chosen = selected.chosenPath?.trimmingCharacters(in: .whitespacesAndNewlines),
           !chosen.isEmpty,
           let match = options.first(where: { normalizedPlanText($0.fullText) == normalizedPlanText(chosen) })
        {
            return match.id
        }
        return nil
    }

    private func normalizedPlanText(_ text: String) -> String {
        text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
    }

    private func downloadCurrentPlan() {
        guard let board = chatStore.planBoard(for: conversationId) else { return }
        let content: String
        if let chosen = board.chosenPath?.trimmingCharacters(in: .whitespacesAndNewlines), !chosen.isEmpty {
            content = chosen
        } else if let first = board.options.sorted(by: { $0.id < $1.id }).first {
            content = first.fullText
        } else {
            content = "# \(board.goal)\n\n"
        }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = planFileName
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            try? content.write(to: url, atomically: true, encoding: .utf8)
        }
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

/// Horizontal 3-step phase progress indicator for the multi-turn plan flow.
struct PlanPhaseProgressView: View {
    let phase: PlanFlowPhase

    private let planColor = DesignSystem.Colors.planColor

    private struct PhaseStep {
        let label: String
        let isActive: Bool
        let isCompleted: Bool
    }

    private var steps: [PhaseStep] {
        let phaseOrder: [PlanFlowPhase] = [.analyzing, .questioning, .generating]
        guard let currentIndex = phaseOrder.firstIndex(of: phase) else {
            return [
                PhaseStep(label: "Analysis", isActive: false, isCompleted: true),
                PhaseStep(label: "Questions", isActive: false, isCompleted: true),
                PhaseStep(label: "Plan", isActive: false, isCompleted: true),
            ]
        }
        return [
            PhaseStep(
                label: "Analysis",
                isActive: currentIndex == 0,
                isCompleted: currentIndex > 0
            ),
            PhaseStep(
                label: "Questions",
                isActive: currentIndex == 1,
                isCompleted: currentIndex > 1
            ),
            PhaseStep(
                label: "Plan",
                isActive: currentIndex == 2,
                isCompleted: false
            ),
        ]
    }

    var body: some View {
        HStack(spacing: 4) {
            ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                if index > 0 {
                    Rectangle()
                        .fill(step.isCompleted || step.isActive
                              ? planColor.opacity(0.6)
                              : Color.secondary.opacity(0.2))
                        .frame(height: 2)
                        .frame(maxWidth: 24)
                }

                HStack(spacing: 4) {
                    if step.isCompleted {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundColor(planColor)
                    } else if step.isActive {
                        ProgressView()
                            .controlSize(.mini)
                            .scaleEffect(0.7)
                    } else {
                        Circle()
                            .fill(Color.secondary.opacity(0.3))
                            .frame(width: 10, height: 10)
                    }

                    Text(step.label)
                        .font(.system(size: 11, weight: step.isActive ? .semibold : .regular))
                        .foregroundColor(step.isActive ? planColor : .secondary)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.4))
        )
    }
}
