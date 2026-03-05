import AppKit
import SwiftUI
import CoderEngine
import UniformTypeIdentifiers

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
    /// Whether the clarification questions phase was visited during this plan flow.
    let questionsWereVisited: Bool
    /// Increases whenever a clarification round is emitted, forcing wizard state reset.
    let clarificationIdentitySeed: Int
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

    @State var planText: String = ""
    @State var isEditing = false
    @State var buildHint: String?
    /// Guards single-option auto-select so it fires only once per planningState.
    @State var didAutoSelectSingleOption = false
    @State var showDeleteAllHistoryConfirmation = false
    @State var walkthroughExpanded = false
    @State var historySelectionVersion = 0
    @State var expandedHistoryEntryIds: Set<UUID> = []
    /// Override provider for plan execution (nil = use conversation/global default)
    @State var planProviderId: String?
    /// Cached auth per provider — populated async to avoid blocking main thread on isAuthenticated().
    @State var providerAuthCache: [String: Bool] = [:]
    /// Reference-type cache to avoid mutating @State during body evaluation.
    final class SnapshotCache {
        var key: String = ""
        var snapshot: PlanRenderSnapshot?
    }
    @State var snapshotCache = SnapshotCache()
    /// Keeps top controls out of the macOS titlebar non-interactive zone.
        let topInteractiveInset: CGFloat = 22

    let planColor = DesignSystem.Colors.planColor

    struct PlanRenderSnapshot {
        let planContent: String
        let planBodyContent: String
        let mermaidBlock: String?
        let mermaidBlocks: [String]
        let canonicalTodos: [TodoItem]
    }

    var planTraceActivities: [TaskActivity] {
        let recent = taskActivityStore.planRelevantRecentActivities(limit: 120)
        return filterPlanTraceActivitiesForConversation(recent, conversationId: conversationId)
    }

    var body: some View {
        let snapshot = resolveSnapshot()
        VStack(spacing: 0) {
            Color.clear
                .frame(height: topInteractiveInset)
                .allowsHitTesting(false)
            fixedToolbar
            thinSeparator

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 20) {
                    // 1) Progress (analyzing/questioning/generating)
                    if planFlowPhase == .analyzing || planFlowPhase == .questioning || planFlowPhase == .generating {
                        PlanPhaseProgressView(phase: planFlowPhase, questionsWereVisited: questionsWereVisited)
                    }

                    // 2) Clarification questions (only when truly waiting)
                    if case .awaitingClarification(let questions) = planningState {
                        if let questionnaire = PlanOptionsParser.parseClarificationQuestionnaire(from: questions) {
                            PlanClarificationWizardView(
                                questionnaire: questionnaire,
                                planColor: planColor,
                                onSubmit: onSubmitClarificationAnswers
                            )
                            .id(
                                clarificationWizardIdentityKey(
                                    for: questions,
                                    seed: clarificationIdentitySeed
                                )
                            )
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
                        // 5) Mermaid diagrams (all blocks)
                        ForEach(Array(snapshot.mermaidBlocks.enumerated()), id: \.offset) { _, block in
                            MermaidDiagramView(
                                mermaidCode: block,
                                accentColor: planColor
                            )
                        }

                        // 6) Final plan body (cause/approach), clean and deduplicated
                        planContentSection(snapshot: snapshot)
                    }

                    // 7) Live activity (compact)
                    if !planTraceActivities.isEmpty {
                        traceSection
                            .animation(.none, value: planTraceActivities.count)
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
        .background(DesignSystem.Colors.chatPanelSolidBackground)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color(nsColor: .separatorColor).opacity(0.45), lineWidth: 0.5)
        )
        .onAppear {
            planText = ""
            isEditing = false
            buildHint = nil
            walkthroughExpanded = false
            expandedHistoryEntryIds = []
            planProviderId = nil
            didAutoSelectSingleOption = false
            refreshProviderAuthCache()
        }
        .onChange(of: providerRegistry.selectedProviderId) { _, _ in refreshProviderAuthCache() }
        .onChange(of: planProviderId) { _, _ in refreshProviderAuthCache() }
        .onChange(of: conversationId) { _, _ in
            // New conversation => plan panel should immediately reflect the new context.
            planText = ""
            isEditing = false
            buildHint = nil
            walkthroughExpanded = false
            historySelectionVersion = 0
            expandedHistoryEntryIds = []
            planProviderId = nil
            didAutoSelectSingleOption = false
        }
        .onChange(of: planningState) { _, _ in
            didAutoSelectSingleOption = false
            walkthroughExpanded = false
            expandedHistoryEntryIds = []
        }
        .onReceive(NotificationCenter.default.publisher(for: ChatPanelView.planBuildShortcutNotification)) { _ in
            if isCurrentConversationLoading {
                onStop()
            } else {
                performBuild()
            }
        }
    }
}
