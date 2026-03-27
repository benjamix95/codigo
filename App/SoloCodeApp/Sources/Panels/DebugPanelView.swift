import SwiftUI
import CoderEngine

struct DebugPanelView: View {
    @EnvironmentObject private var pipelineIntegrationService: PipelineIntegrationService
    @ObservedObject var debugStore: DebugStore
    let taskActivities: [TaskActivity]
    @ObservedObject var todoStore: TodoStore
    let conversationId: UUID?
    let onClose: () -> Void
    let onStop: () -> Void
    let onProceed: () -> Void
    let onFixed: () -> Void
    let onSubmitDebugClarification: (DebugClarificationSubmission) -> Void

    @State var clarificationSelectedLetter: String?
    @State var clarificationCustomNotes: String = ""

    @State var expandedLogId: UUID?
    @State var expandedRuntimeLogId: String?
    @State var isFilterExpanded = false
    @State var hoveredPhase: DebugFlowPhase?
    @State var showPhaseDetail = false

    let topInteractiveInset: CGFloat = 22
    let accent = DesignSystem.Colors.debugColor

    var body: some View {
        VStack(spacing: 0) {
            Color.clear
                .frame(height: topInteractiveInset)
                .allowsHitTesting(false)

            suppressedDebugProjectionBufferBanner(integration: pipelineIntegrationService)

            header
            divider

            if debugStore.phase != .idle {
                phaseTimeline
                    .transition(.move(edge: .top).combined(with: .opacity))
                divider
            }

            scrollContent

            if debugStore.phase != .idle && debugStore.phase != .resolved {
                if !debugStore.streamingContent.isEmpty {
                    divider
                    streamingBanner
                }
                if !debugStore.clarificationQuestions.isEmpty {
                    divider
                    questionCards
                }
            }

            phaseActionArea
        }
        .background(DesignSystem.Colors.chatPanelSolidBackground)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color(nsColor: .separatorColor).opacity(0.45), lineWidth: 0.5)
        )
        .frame(minWidth: 420, idealWidth: 500, maxWidth: 560)
        .animation(.smooth, value: debugStore.phase)
        .onChange(of: debugStore.clarificationQuestions) { _ in
            clarificationSelectedLetter = nil
            clarificationCustomNotes = ""
        }
        .onChange(of: debugStore.isAwaitingUserClarification) { waiting in
            if !waiting {
                clarificationSelectedLetter = nil
                clarificationCustomNotes = ""
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .soloCodeDebugEventBufferDropped)) { note in
            guard let cid = note.userInfo?[DebugPipelineBufferNotificationUserInfoKey.conversationId] as? UUID,
                  cid == conversationId
            else { return }
            let dropped = note.userInfo?[DebugPipelineBufferNotificationUserInfoKey.dropped] as? Int ?? 0
            debugStore.addLog(
                severity: .error,
                source: "debug_pipeline",
                message: "Coda eventi debug pipeline: eliminati \(dropped) eventi (buffer al cap)",
                category: "system"
            )
        }
    }

    // MARK: - Scroll Content

    var scrollContent: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    debugPipelineStatusCard
                    todoSection

                    if !taskActivities.isEmpty {
                        CompactActivityTraceView(
                            activities: taskActivities,
                            accentColor: accent,
                            title: "Activity"
                        )
                    }

                    if !debugStore.debugFlowDiagram.isEmpty {
                        MermaidDiagramView(
                            mermaidCode: debugStore.debugFlowDiagram,
                            accentColor: accent
                        )
                    }

                    if !debugStore.lastTraceAnalysis.isEmpty
                        || !debugStore.lastSnapshotReport.isEmpty
                        || !debugStore.lastTimelineReport.isEmpty
                        || !debugStore.lastTestCheckReport.isEmpty
                        || !debugStore.lastSessionExport.isEmpty {
                        sectionHeader(
                            "Analysis",
                            icon: "waveform.path.ecg",
                            count: 0
                        )
                        analysisContent
                    }

                    sectionHeader(
                        "Hypotheses",
                        icon: "lightbulb",
                        count: debugStore.hypotheses.count
                    )
                    hypothesesContent

                    sectionHeader(
                        "Logs",
                        icon: "doc.text",
                        count: debugStore.filteredLogs.count
                    )
                    if isFilterExpanded {
                        filterBar
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }
                    logsContent
                    runtimeLogsContent

                    streamLogsSection

                    sectionHeader(
                        "Markers",
                        icon: "mappin",
                        count: debugStore.debugMarkers.count + debugStore.instrumentationPoints.count
                    )
                    markersContent

                    Color.clear.frame(height: 1).id("debug-scroll-anchor")
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
            .onChange(of: debugStore.logs.count) { _ in
                withAnimation(.easeOut(duration: 0.2)) {
                    proxy.scrollTo("debug-scroll-anchor", anchor: .bottom)
                }
            }
            .onChange(of: debugStore.runtimeLogs.count) { _ in
                withAnimation(.easeOut(duration: 0.2)) {
                    proxy.scrollTo("debug-scroll-anchor", anchor: .bottom)
                }
            }
            .onChange(of: debugStore.streamLogs.count) { _ in
                withAnimation(.easeOut(duration: 0.2)) {
                    proxy.scrollTo("debug-scroll-anchor", anchor: .bottom)
                }
            }
        }
    }

    // MARK: - Todo Section

    @ViewBuilder
    var todoSection: some View {
        let todos = todoStore.displayTodosForChat(for: conversationId)
        if !todos.isEmpty {
            debugTodoCard(todos)
        }
    }

    // MARK: - Filter Bar

    var filterBar: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                ForEach(DebugEntrySeverity.allCases, id: \.self) { severity in
                    severityFilterChip(severity)
                }
                Spacer()

                if debugStore.severityFilter.count < DebugEntrySeverity.allCases.count {
                    Button {
                        withAnimation(.quick) {
                            debugStore.severityFilter = Set(DebugEntrySeverity.allCases)
                        }
                    } label: {
                        Text("Reset")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(accent)
                    }
                    .buttonStyle(.plain)
                }
            }

            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 10))
                    .foregroundStyle(DesignSystem.Colors.textTertiary)
                TextField("Search logs…", text: $debugStore.searchQuery)
                    .textFieldStyle(.plain)
                    .font(.system(size: 11))

                if !debugStore.searchQuery.isEmpty {
                    Button {
                        debugStore.searchQuery = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(DesignSystem.Colors.textTertiary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 6))
        }
        .padding(10)
        .background(DesignSystem.Colors.backgroundSecondary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
    }

    func severityFilterChip(_ severity: DebugEntrySeverity) -> some View {
        let isActive = debugStore.severityFilter.contains(severity)
        return Button {
            withAnimation(.quick) {
                if isActive {
                    debugStore.severityFilter.remove(severity)
                } else {
                    debugStore.severityFilter.insert(severity)
                }
            }
        } label: {
            HStack(spacing: 3) {
                Image(systemName: severity.icon)
                    .font(.system(size: 8))
                Text(severity.rawValue.capitalized)
                    .font(.system(size: 9, weight: .medium))
            }
            .foregroundStyle(isActive ? severity.color : DesignSystem.Colors.textTertiary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 5)
                    .fill(isActive ? severity.color.opacity(0.1) : Color.primary.opacity(0.03))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 5)
                    .strokeBorder(
                        isActive ? severity.color.opacity(0.2) : Color.clear,
                        lineWidth: 0.5
                    )
            )
        }
        .buttonStyle(.plain)
    }
}
