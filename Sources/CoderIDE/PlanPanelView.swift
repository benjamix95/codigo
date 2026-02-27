import AppKit
import SwiftUI
import CoderEngine
import UniformTypeIdentifiers

func isPlanBuildEnabled(
    phase: PlanFlowPhase,
    hasBuildChoice: Bool,
    allowIdleRebuild: Bool = false,
    providerExecutionCapable: Bool = true
) -> Bool {
    guard providerExecutionCapable else { return false }
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
    switch phase {
    case .idle:
        return "No plan"
    case .analyzing:
        return "Analyzing..."
    case .questioning:
        return "Answer questions first"
    case .generating:
        return "Generating..."
    case .building:
        return "Building..."
    case .proposalReady, .readyToBuild:
        break
    }
    if !hasBuildChoice {
        return "No option selected"
    }
    if !providerExecutionCapable {
        return "Auth required"
    }
    return nil
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
    /// Guards single-option auto-select so it fires only once per planningState.
    @State private var didAutoSelectSingleOption = false
    @State private var showDeleteAllHistoryConfirmation = false
    @State private var walkthroughExpanded = false
    @State private var historySelectionVersion = 0
    /// Override provider for plan execution (nil = use conversation/global default)
    @State private var planProviderId: String?
    /// Keeps top controls out of the macOS titlebar non-interactive zone.
    private let topInteractiveInset: CGFloat = 22

    private let planColor = DesignSystem.Colors.planColor

    private struct PlanRenderSnapshot {
        let planContent: String
        let planBodyContent: String
        let mermaidBlocks: [String]
        let canonicalTodos: [TodoItem]
    }

    var body: some View {
        let snapshot = makeRenderSnapshot()
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
                        if options.count == 1 {
                            Color.clear.frame(width: 0, height: 0).onAppear {
                                guard !didAutoSelectSingleOption else { return }
                                didAutoSelectSingleOption = true
                                onSelectOption(options[0], planProviderId)
                            }
                        } else {
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
                    }

                    // 4) Final todos
                    if shouldShowCanonicalTodos && !snapshot.canonicalTodos.isEmpty {
                        todosSection(canonicalTodos: snapshot.canonicalTodos)
                    }

                    if shouldShowPlanDetailsSection {
                        // 5) Mermaid (if present)
                        if let firstMermaid = snapshot.mermaidBlocks.first {
                            MermaidDiagramView(
                                mermaidCode: firstMermaid,
                                accentColor: planColor
                            )
                        }

                        // 6) Final plan body (cause/approach), clean and deduplicated
                        planContentSection(snapshot: snapshot)
                    }

                    // 7) Live activity (compact)
                    if !taskActivityStore.activities.isEmpty {
                        traceSection
                    }

                    if shouldShowPlanDetailsSection {
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
                }
                .padding(16)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            thinSeparator
            if shouldShowCanonicalTodos {
                bottomBar(canonicalTodos: snapshot.canonicalTodos)
            }
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
            planProviderId = nil
            didAutoSelectSingleOption = false
        }
        .onChange(of: conversationId) { _, _ in
            // New conversation => plan panel should immediately reflect the new context.
            planText = ""
            isEditing = false
            buildHint = nil
            walkthroughExpanded = false
            historySelectionVersion = 0
            planProviderId = nil
            didAutoSelectSingleOption = false
        }
        .onChange(of: planningState) { _, _ in
            // Reset single-option auto-select guard when planningState changes,
            // so a new awaitingChoice with a single option can fire again.
            didAutoSelectSingleOption = false
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
                .help("Close panel")
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
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: "_")
            .prefix(30)
        return "\(slug).plan.md"
    }

    // MARK: - Provider Picker

    private var providerPicker: some View {
        let allowedProviders = providerRegistry.providers.filter {
            isPlanExecutionProviderIdAllowed($0.id)
        }

        return Menu {
            if allowedProviders.isEmpty {
                Text("No providers available")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(Array(allowedProviders.enumerated()), id: \.offset) { _, provider in
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
        // Don't show "Built" during active building phase — wait until phase
        // transitions to readyToBuild/idle to avoid brief UI flicker.
        guard planFlowPhase != .building else { return false }
        let canonical = canonicalPlanTodos
        guard !canonical.isEmpty else {
            return false
        }
        return canonical.allSatisfy { $0.status == .done } && !isCurrentConversationLoading
    }

    private var isBuildEnabledByPhase: Bool {
        isPlanBuildEnabled(
            phase: planFlowPhase,
            hasBuildChoice: resolvedBuildChoice != nil,
            allowIdleRebuild: false,
            providerExecutionCapable: isActiveProviderExecutionCapable
        )
    }

    private var shouldShowCanonicalTodos: Bool {
        switch planFlowPhase {
        case .readyToBuild, .building:
            return true
        default:
            return false
        }
    }

    private var isPreBuildPlanState: Bool {
        if planningState != .idle {
            return true
        }
        switch planFlowPhase {
        case .analyzing, .questioning, .generating, .proposalReady:
            return true
        case .idle, .readyToBuild, .building:
            return false
        }
    }

    private var shouldShowPlanDetailsSection: Bool {
        !isPreBuildPlanState
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
            return "Analyzing..."
        case .questioning:
            return "Awaiting answers"
        case .generating:
            return "Generating..."
        case .proposalReady:
            return buildDisabledReason ?? "Select an option"
        case .readyToBuild:
            return buildDisabledReason ?? "Ready"
        case .building:
            return "Building..."
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
                    HStack(spacing: 3) {
                        Image(systemName: "checkmark")
                            .font(.system(size: 8, weight: .bold))
                        Text("Built")
                            .font(.system(size: 10, weight: .semibold))
                        Image(systemName: "chevron.down")
                            .font(.system(size: 6, weight: .bold))
                            .foregroundStyle(.white.opacity(0.7))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .background(
                        DesignSystem.Colors.planGradient,
                        in: RoundedRectangle(cornerRadius: 5, style: .continuous)
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
                    HStack(spacing: 3) {
                        if isCurrentConversationLoading {
                            ProgressView()
                                .controlSize(.mini)
                                .tint(.white)
                        }
                        Image(systemName: isCurrentConversationLoading ? "stop.fill" : "play.fill")
                            .font(.system(size: 8, weight: .bold))
                        Text(isCurrentConversationLoading ? "Stop" : "Build")
                            .font(.system(size: 10, weight: .semibold))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .background(
                        DesignSystem.Colors.planGradient,
                        in: RoundedRectangle(cornerRadius: 5, style: .continuous)
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
            buildHint = buildDisabledReason ?? phaseHint ?? "Build unavailable."
            return
        }
        guard let choice = resolvedBuildChoice?.text else {
            buildHint = "No option selected."
            return
        }
        let hasRequiredTodoHeader = PlanOptionsParser.hasRequiredTodoHeader(choice)
        let extractedTodos = PlanOptionsParser.extractTodosFromOptionText(choice)
        guard hasRequiredTodoHeader, !extractedTodos.isEmpty else {
            buildHint = "Build requires a todo checklist. Edit the plan or select a valid option."
            return
        }
        buildHint = "Build started..."
        onBuild(choice, planProviderId, false)
    }

    // MARK: - Bottom Bar

    private func bottomBar(canonicalTodos: [TodoItem]) -> some View {
        HStack(spacing: 8) {
            let total = canonicalTodos.count
            let done = canonicalTodos.filter { $0.status == .done }.count
            if total > 0 {
                HStack(spacing: 4) {
                    Image(systemName: "checklist")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(planColor.opacity(0.6))
                    Text("\(done)/\(total)")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.tertiary)
                }
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color.secondary.opacity(0.15))
                        RoundedRectangle(cornerRadius: 2)
                            .fill(planColor.opacity(0.5))
                            .frame(width: geo.size.width * CGFloat(done) / CGFloat(total))
                    }
                }
                .frame(maxWidth: 60, maxHeight: 3)
            }
            Spacer()
            if planFlowPhase == .building, isCurrentConversationLoading {
                HStack(spacing: 4) {
                    ProgressView()
                        .controlSize(.mini)
                        .scaleEffect(0.6)
                    Text("Building")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
    }

    // MARK: - Plan Content

    /// Live conversation content while streaming; otherwise planText (local edit buffer).
    /// During multi-turn plan phases, prefer planStreamingContent which is routed directly from the flow.
    private var displayPlanContent: String {
        if isEditing { return planText }

        if isPreBuildPlanState {
            if !planStreamingContent.isEmpty {
                return planStreamingContent
            }
            if case .awaitingClarification(let questions) = planningState {
                return questions
            }
            return ""
        }

        if let selected = latestPlanHistoryEntry() {
            if !selected.markdown.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return selected.markdown
            }
            if let chosen = selected.chosenPath?.trimmingCharacters(in: .whitespacesAndNewlines),
               !chosen.isEmpty {
                return chosen
            }
        }

        if let board = chatStore.planBoard(for: conversationId) {
            if let chosen = board.chosenPath?.trimmingCharacters(in: .whitespacesAndNewlines),
               !chosen.isEmpty {
                return chosen
            }
            if let first = firstOption(byId: board.options) {
                return first.fullText
            }
        }

        let hasBoard = chatStore.planBoard(for: conversationId) != nil
        let hasSelectedHistoryEntry = latestPlanHistoryEntry() != nil
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

    private func makeRenderSnapshot() -> PlanRenderSnapshot {
        let content = displayPlanContent
        let planBody = PlanOptionsParser.extractFinalPlanBodyExcludingQuestionsOptionsTodos(content)
        let mermaidBlocks = content.isEmpty ? [] : PlanOptionsParser.extractMermaidBlocksForDisplay(content)
        return PlanRenderSnapshot(
            planContent: content,
            planBodyContent: planBody,
            mermaidBlocks: mermaidBlocks,
            canonicalTodos: canonicalPlanTodos
        )
    }

    private func planContentSection(snapshot: PlanRenderSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Technical Plan")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    if !isEditing {
                        planText = snapshot.planContent
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
                        Text("Exploring codebase...")
                            .font(.system(size: 11, weight: .regular))
                            .foregroundStyle(.tertiary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 24)
                .padding(.horizontal, 12)
            } else if !snapshot.planBodyContent.isEmpty {
                MarkdownContentView(
                    content: snapshot.planBodyContent,
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
                    Text("Plan content will appear here.")
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
                    let selectedHistoryOptionId = selectedOptionIdForHistoryEntry(entry)
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
                        Button {
                            if planHistoryStore.selectedEntryId == entry.id {
                                planHistoryStore.setSelectedEntry(id: nil)
                            } else {
                                planHistoryStore.setSelectedEntry(id: entry.id)
                                let choice = resolvedBuildContent(for: entry) ?? ""
                                if PlanOptionsParser.hasRequiredTodoHeader(choice),
                                   !PlanOptionsParser.extractTodosFromOptionText(choice).isEmpty {
                                    onHistoryEntrySelectedForBuild?()
                                }
                            }
                            historySelectionVersion &+= 1
                        } label: {
                            let isActive = planHistoryStore.selectedEntryId == entry.id
                            Text(isActive ? "Hide" : "Preview")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(isActive ? planColor : .secondary)
                        }
                        .buttonStyle(.plain)
                        if !entry.options.isEmpty {
                            Menu {
                                ForEach(entry.options.sorted(by: { $0.id < $1.id })) { option in
                                    Button {
                                        planHistoryStore.updateChosenPath(id: entry.id, chosenPath: option.fullText)
                                        planHistoryStore.setSelectedEntry(id: entry.id)
                                        onHistoryEntrySelectedForBuild?()
                                        historySelectionVersion &+= 1
                                        buildHint = "Selected Option \(option.id)"
                                    } label: {
                                        HStack {
                                            Text("Option \(option.id): \(option.title)")
                                                .lineLimit(1)
                                            if selectedHistoryOptionId == option.id {
                                                Spacer()
                                                Image(systemName: "checkmark")
                                            }
                                        }
                                    }
                                }
                            } label: {
                                Image(systemName: "list.number")
                                    .font(.system(size: 11, weight: .semibold))
                            }
                            .help("Select option for rebuild")
                        }
                        Button {
                            guard isPlanBuildEnabled(
                                phase: planFlowPhase,
                                hasBuildChoice: true,
                                allowIdleRebuild: true,
                                providerExecutionCapable: isActiveProviderExecutionCapable
                            ) else {
                                buildHint = phaseHint ?? "Build unavailable in this phase."
                                return
                            }
                            planHistoryStore.setSelectedEntry(id: entry.id)
                            guard let choice = resolvedBuildContent(for: entry) else {
                                buildHint = "Select an option before rebuilding."
                                return
                            }
                            let hasRequiredTodoHeader = PlanOptionsParser.hasRequiredTodoHeader(choice)
                            let extractedTodos = PlanOptionsParser.extractTodosFromOptionText(choice)
                            guard hasRequiredTodoHeader, !extractedTodos.isEmpty else {
                                buildHint = "Build requires a todo checklist."
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

    // MARK: - Todos Section

    private var canonicalPlanTodos: [TodoItem] {
        let canonical = todoStore.todos.filter { $0.isPlanCanonical }
        return todoStore.sortedCanonicalFirstTodos(canonical)
    }

    private func todosSection(canonicalTodos: [TodoItem]) -> some View {
        let total = canonicalTodos.count
        let done = canonicalTodos.filter { $0.status == .done }.count
        let inProgress = canonicalTodos.filter { $0.status == .inProgress }.count
        let blocked = canonicalTodos.filter { $0.status == .blocked }.count
        let ratio = total > 0 ? Double(done) / Double(total) : 0.0

        return VStack(alignment: .leading, spacing: 8) {
            // Header
            HStack {
                Image(systemName: "checklist")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(planColor)
                Text("Todo (Plan)")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                if blocked > 0 {
                    Text("\(blocked) blocked")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(DesignSystem.Colors.error)
                }
                if inProgress > 0 {
                    Text("\(inProgress) running")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(planColor)
                }
                Text("\(done)/\(total)")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(done > 0 ? DesignSystem.Colors.success : DesignSystem.Colors.textTertiary)
                    .contentTransition(.numericText())
                Text("\(Int(ratio * 100))%")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(ratio >= 1.0 ? DesignSystem.Colors.success : .secondary)
                    .contentTransition(.numericText())
            }

            // Progress bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.secondary.opacity(0.12))
                    RoundedRectangle(cornerRadius: 2)
                        .fill(ratio >= 1.0 ? DesignSystem.Colors.success : planColor)
                        .frame(width: geo.size.width * CGFloat(ratio))
                        .animation(.easeInOut(duration: 0.4), value: ratio)
                }
            }
            .frame(height: 4)

            // Todo items
            ForEach(canonicalTodos) { todo in
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        Button {
                            let newStatus: TodoStatus = todo.status == .done ? .pending : .done
                            todoStore.setStatus(id: todo.id, status: newStatus)
                            if let conversationId {
                                let canonical = todoStore.todos.filter(\.isPlanCanonical)
                                chatStore.syncPlanStepsFromCanonicalTodos(canonical, in: conversationId)
                            }
                        } label: {
                            Image(systemName: todo.status.icon)
                                .font(.system(size: 13))
                                .foregroundStyle(todo.status.color)
                                .symbolEffect(.pulse, isActive: todo.status == .inProgress)
                        }
                        .buttonStyle(.plain)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(todo.title)
                                .font(.system(size: 12))
                                .strikethrough(todo.status == .done, color: .secondary)
                                .foregroundStyle(todo.status == .done ? .tertiary : .primary)
                                .lineLimit(2)
                            if todo.status == .inProgress, !todo.activeForm.isEmpty {
                                HStack(spacing: 4) {
                                    Circle()
                                        .fill(planColor)
                                        .frame(width: 5, height: 5)
                                    Text(todo.activeForm)
                                        .font(.system(size: 10, weight: .medium))
                                        .foregroundStyle(planColor.opacity(0.8))
                                        .lineLimit(1)
                                }
                            }
                        }
                    }

                    // Linked files
                    if !todo.linkedFiles.isEmpty {
                        HStack(spacing: 4) {
                            Image(systemName: "doc.text")
                                .font(.system(size: 8))
                                .foregroundStyle(.tertiary)
                            ForEach(todo.linkedFiles.prefix(2), id: \.self) { file in
                                Text((file as NSString).lastPathComponent)
                                    .font(.system(size: 9, design: .monospaced))
                                    .foregroundStyle(.tertiary)
                                    .lineLimit(1)
                            }
                            if todo.linkedFiles.count > 2 {
                                Text("+\(todo.linkedFiles.count - 2)")
                                    .font(.system(size: 9, design: .monospaced))
                                    .foregroundStyle(.quaternary)
                            }
                        }
                        .padding(.leading, 21)
                    }
                }
                .padding(.vertical, 2)
            }
            .animation(.easeInOut(duration: 0.25), value: canonicalTodos.map { "\($0.id)-\($0.status.rawValue)" })
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

    private func resolvedPreviewContent(for entry: PlanHistoryEntry) -> String {
        if !entry.markdown.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return entry.markdown
        }
        if let chosen = entry.chosenPath, !chosen.isEmpty {
            return chosen
        }
        // Both markdown and chosenPath are empty — return a descriptive fallback
        // so download/preview never produces blank content.
        return "# \(entry.title.isEmpty ? "Plan" : entry.title)\n\n(No plan content available.)"
    }

    private func selectedHistoryEntryForConversation() -> PlanHistoryEntry? {
        guard let conversationId else { return nil }
        guard let selected = planHistoryStore.findEntry(id: planHistoryStore.selectedEntryId) else { return nil }
        return selected.conversationId == conversationId ? selected : nil
    }

    private func latestPlanHistoryEntry() -> PlanHistoryEntry? {
        if let selected = selectedHistoryEntryForConversation() {
            return selected
        }
        guard let conversationId else { return nil }
        return planHistoryStore.findLatestEntry(for: conversationId)
    }

    private func resolvedBuildContent(for entry: PlanHistoryEntry) -> String? {
        let chosen = entry.chosenPath?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return chosen.isEmpty ? nil : chosen
    }

    private var thinSeparator: some View {
        Rectangle()
            .fill(DesignSystem.Colors.border.opacity(0.4))
            .frame(height: 0.5)
    }

    private func firstOption(byId options: [PlanOption]) -> PlanOption? {
        options.min(by: { $0.id < $1.id })
    }

    private func resolveBuildChoice() -> (text: String, isFallback: Bool)? {
        if let selected = selectedHistoryEntryForConversation() {
            if let chosen = resolvedBuildContent(for: selected) {
                return (chosen, false)
            }
            return nil
        }
        if let board = chatStore.planBoard(for: conversationId) {
            if let chosen = board.chosenPath?.trimmingCharacters(in: .whitespacesAndNewlines),
               !chosen.isEmpty {
                return (chosen, false)
            }
            return nil
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
        if let selected = selectedHistoryEntryForConversation(),
           let chosen = selected.chosenPath?.trimmingCharacters(in: .whitespacesAndNewlines),
           !chosen.isEmpty,
           let match = options.first(where: { normalizedPlanText($0.fullText) == normalizedPlanText(chosen) })
        {
            return match.id
        }
        return nil
    }

    private func selectedOptionIdForHistoryEntry(_ entry: PlanHistoryEntry) -> Int? {
        guard !entry.options.isEmpty else { return nil }
        guard let chosen = entry.chosenPath?.trimmingCharacters(in: .whitespacesAndNewlines),
              !chosen.isEmpty else { return nil }
        return entry.options.first(where: {
            normalizedPlanText($0.fullText) == normalizedPlanText(chosen)
        })?.id
    }

    private func normalizedPlanText(_ text: String) -> String {
        text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
    }

    private func downloadCurrentPlan() {
        if let entry = latestPlanHistoryEntry(),
           !resolvedPreviewContent(for: entry).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let content = resolvedPreviewContent(for: entry).trimmingCharacters(in: .whitespacesAndNewlines)
            savePlanToFile(content: content, suggestedName: planFileName)
            return
        }

        guard let board = chatStore.planBoard(for: conversationId) else { return }
        let content: String
        if let chosen = board.chosenPath?.trimmingCharacters(in: .whitespacesAndNewlines), !chosen.isEmpty {
            content = chosen
        } else if let first = firstOption(byId: board.options) {
            content = first.fullText
        } else {
            content = "# \(board.goal)\n\n"
        }
        savePlanToFile(content: content, suggestedName: planFileName)
    }

    private func downloadPlan(_ entry: PlanHistoryEntry) {
        let content = resolvedPreviewContent(for: entry)
        let baseName = entry.title.isEmpty ? "PLAN" : entry.title
        let safeName = baseName
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: "_")
        savePlanToFile(content: content, suggestedName: "\(safeName).md")
    }

    private func savePlanToFile(content: String, suggestedName: String) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = suggestedName
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            do {
                try content.write(to: url, atomically: true, encoding: .utf8)
            } catch {
                print("[PlanPanel] Failed to save plan: \(error.localizedDescription)")
            }
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
        switch phase {
        case .analyzing:
            return [
                PhaseStep(label: "Analysis", isActive: true, isCompleted: false),
                PhaseStep(label: "Questions", isActive: false, isCompleted: false),
                PhaseStep(label: "Plan", isActive: false, isCompleted: false),
            ]
        case .questioning:
            return [
                PhaseStep(label: "Analysis", isActive: false, isCompleted: true),
                PhaseStep(label: "Questions", isActive: true, isCompleted: false),
                PhaseStep(label: "Plan", isActive: false, isCompleted: false),
            ]
        case .generating:
            // Questions step shows as completed only if the phase was visited;
            // otherwise it's skipped (shown as completed to avoid confusion).
            return [
                PhaseStep(label: "Analysis", isActive: false, isCompleted: true),
                PhaseStep(label: "Questions", isActive: false, isCompleted: true),
                PhaseStep(label: "Plan", isActive: true, isCompleted: false),
            ]
        default:
            return [
                PhaseStep(label: "Analysis", isActive: false, isCompleted: true),
                PhaseStep(label: "Questions", isActive: false, isCompleted: true),
                PhaseStep(label: "Plan", isActive: false, isCompleted: true),
            ]
        }
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
                            .foregroundStyle(planColor)
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
                        .foregroundStyle(step.isActive ? planColor : .secondary)
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
