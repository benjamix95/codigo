import SwiftUI
import CoderEngine

struct DebugPanelView: View {
    @ObservedObject var debugStore: DebugStore
    let taskActivities: [TaskActivity]
    @ObservedObject var todoStore: TodoStore
    let onClose: () -> Void
    let onSubmitQuestion: (String) -> Void
    let onStop: () -> Void
    let onProceed: () -> Void
    let onFixed: () -> Void

    @State private var userInput = ""
    @State private var expandedLogId: UUID?
    @State private var selectedTab: DebugTab = .logs
    @State private var expandedRuntimeLogId: String?
    @State private var isFilterExpanded = false
    @State private var hoveredPhase: DebugFlowPhase?
    @FocusState private var isChatInputFocused: Bool
    @State private var showPhaseDetail = false

    private let topInteractiveInset: CGFloat = 22
    private let accent = DesignSystem.Colors.debugColor

    enum DebugTab: String, CaseIterable {
        case logs = "Logs"
        case runtime = "Runtime"
        case hypotheses = "Hypotheses"
        case markers = "Markers"

        var icon: String {
            switch self {
            case .logs:       return "doc.text"
            case .runtime:    return "waveform.path.ecg"
            case .hypotheses: return "lightbulb"
            case .markers:    return "mappin"
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            Color.clear
                .frame(height: topInteractiveInset)
                .allowsHitTesting(false)

            header
            divider

            if debugStore.phase != .idle {
                phaseTimeline
                    .transition(.move(edge: .top).combined(with: .opacity))
                divider
            }

            tabStrip
            divider

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

            divider
            chatInput
        }
        .background(DesignSystem.Colors.chatPanelSolidBackground)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color(nsColor: .separatorColor).opacity(0.45), lineWidth: 0.5)
        )
        .frame(minWidth: 320, idealWidth: 380, maxWidth: 440)
        .animation(.smooth, value: debugStore.phase)
        .animation(.smooth, value: selectedTab)
    }

    // MARK: - Divider

    private var divider: some View {
        Rectangle()
            .fill(DesignSystem.Colors.borderSubtle)
            .frame(height: 0.5)
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 10) {
            HStack(spacing: 6) {
                ZStack {
                    Circle()
                        .fill(accent.opacity(0.12))
                        .frame(width: 24, height: 24)
                    Image(systemName: "ladybug.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(accent)
                }

                Text("Debug")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(DesignSystem.Colors.textPrimary)
            }

            if debugStore.phase.isActive {
                phaseChip(debugStore.phase)
                    .transition(.scale.combined(with: .opacity))
            }

            Spacer()

            headerBadges

            headerActions
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private var headerBadges: some View {
        HStack(spacing: 4) {
            if debugStore.errorCount > 0 {
                counterBadge(count: debugStore.errorCount, color: DesignSystem.Colors.error, icon: "xmark.circle.fill")
            }
            if debugStore.warningCount > 0 {
                counterBadge(count: debugStore.warningCount, color: DesignSystem.Colors.warning, icon: "exclamationmark.triangle.fill")
            }
        }
    }

    private func counterBadge(count: Int, color: Color, icon: String) -> some View {
        HStack(spacing: 3) {
            Image(systemName: icon)
                .font(.system(size: 8))
            Text("\(count)")
                .font(.system(size: 9, weight: .bold, design: .monospaced))
        }
        .foregroundStyle(color)
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(color.opacity(0.1), in: Capsule())
    }

    private var headerActions: some View {
        HStack(spacing: 2) {
            if debugStore.phase.isActive {
                headerButton(icon: "stop.fill", color: accent) {
                    onStop()
                }
                .help("Stop debug session")
            }

            headerButton(icon: "trash", color: .secondary) {
                debugStore.clearLogs()
            }
            .help("Clear logs")

            headerButton(icon: "xmark", color: .secondary) {
                onClose()
            }
            .help("Close (Cmd+Shift+D)")
        }
    }

    private func headerButton(icon: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(color)
                .frame(width: 24, height: 24)
                .background(color.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
    }

    private func phaseChip(_ phase: DebugFlowPhase) -> some View {
        Text(phase.label.uppercased())
            .font(.system(size: 9, weight: .bold, design: .monospaced))
            .foregroundStyle(accent)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(accent.opacity(0.1), in: Capsule())
    }

    // MARK: - Phase Timeline

    private var primaryPhases: [DebugFlowPhase] {
        [.describing, .reproducing, .fixing, .verifying, .resolved]
    }

    private var currentPrimaryPhase: DebugFlowPhase {
        debugStore.phase == .instrumenting ? .fixing : debugStore.phase
    }

    private var currentPrimaryIndex: Int {
        primaryPhases.firstIndex(of: currentPrimaryPhase) ?? 0
    }

    private var phaseTimeline: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 0) {
                ForEach(Array(primaryPhases.enumerated()), id: \.offset) { index, phase in
                    let isCompleted = index < currentPrimaryIndex || currentPrimaryPhase == .resolved
                    let isCurrent = index == currentPrimaryIndex && currentPrimaryPhase != .resolved
                    let isFuture = index > currentPrimaryIndex && currentPrimaryPhase != .resolved

                    phaseNode(phase, isCompleted: isCompleted, isCurrent: isCurrent, isFuture: isFuture)

                    if index < primaryPhases.count - 1 {
                        phaseConnector(isCompleted: isCompleted && !isCurrent)
                    }
                }
            }
            .padding(.horizontal, 4)

            if shouldShowFixSubpipeline {
                fixSubPipeline
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            if !phaseDetailLabel.isEmpty {
                HStack(spacing: 6) {
                    if debugStore.phase.isActive {
                        ProgressView()
                            .controlSize(.mini)
                            .tint(accent.opacity(0.6))
                    }
                    Text(phaseDetailLabel)
                        .font(.system(size: 10.5))
                        .foregroundStyle(
                            currentPrimaryPhase == .resolved
                            ? DesignSystem.Colors.success
                            : DesignSystem.Colors.textSecondary
                        )
                }
                .transition(.opacity)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            currentPrimaryPhase == .resolved
            ? DesignSystem.Colors.success.opacity(0.04)
            : accent.opacity(0.02)
        )
    }

    private func phaseNode(_ phase: DebugFlowPhase, isCompleted: Bool, isCurrent: Bool, isFuture: Bool) -> some View {
        let nodeColor: Color = {
            if isCompleted { return DesignSystem.Colors.success }
            if isCurrent { return accent }
            return DesignSystem.Colors.textTertiary.opacity(0.5)
        }()

        return VStack(spacing: 4) {
            ZStack {
                if isCurrent {
                    Circle()
                        .fill(accent.opacity(0.15))
                        .frame(width: 22, height: 22)

                    Circle()
                        .fill(accent.opacity(0.08))
                        .frame(width: 28, height: 28)
                        .modifier(PulseModifier())
                }

                Image(systemName: isCompleted ? "checkmark.circle.fill" : (isCurrent ? "circle.inset.filled" : "circle"))
                    .font(.system(size: isCurrent ? 13 : 11, weight: .medium))
                    .foregroundStyle(nodeColor)
            }
            .frame(width: 28, height: 28)

            Text(shortLabel(for: phase))
                .font(.system(size: 8.5, weight: isCurrent ? .bold : .medium, design: .monospaced))
                .foregroundStyle(nodeColor)
        }
        .onHover { hovering in
            hoveredPhase = hovering ? phase : nil
        }
    }

    private func phaseConnector(isCompleted: Bool) -> some View {
        VStack {
            Rectangle()
                .fill(
                    isCompleted
                    ? DesignSystem.Colors.success.opacity(0.5)
                    : DesignSystem.Colors.borderSubtle
                )
                .frame(height: 1.5)
                .frame(maxWidth: .infinity)
                .padding(.bottom, 16)
        }
    }

    private var shouldShowFixSubpipeline: Bool {
        debugStore.phase == .fixing
        || debugStore.phase == .instrumenting
        || debugStore.phase == .verifying
        || debugStore.phase == .resolved
        || !debugStore.hypotheses.isEmpty
        || !debugStore.instrumentationPoints.isEmpty
        || !debugStore.runtimeLogs.isEmpty
    }

    private var fixSubPipeline: some View {
        let hasHypothesis = !debugStore.hypotheses.isEmpty
        let hasInstrumentation = !debugStore.instrumentationPoints.isEmpty
        let hasObservation = !debugStore.runtimeLogs.isEmpty
        let fixCompleted = debugStore.phase == .verifying || debugStore.phase == .resolved

        return HStack(spacing: 6) {
            Image(systemName: "arrow.turn.down.right")
                .font(.system(size: 9))
                .foregroundStyle(DesignSystem.Colors.textTertiary)

            subPipelineStep(
                "Hypothesize",
                icon: "lightbulb",
                isCompleted: hasHypothesis || fixCompleted,
                isCurrent: debugStore.phase == .fixing && !hasHypothesis
            )

            Image(systemName: "chevron.right")
                .font(.system(size: 7, weight: .bold))
                .foregroundStyle(DesignSystem.Colors.textTertiary.opacity(0.5))

            subPipelineStep(
                "Instrument",
                icon: "wrench",
                isCompleted: hasInstrumentation || fixCompleted,
                isCurrent: debugStore.phase == .instrumenting || (debugStore.phase == .fixing && hasHypothesis && !hasInstrumentation)
            )

            Image(systemName: "chevron.right")
                .font(.system(size: 7, weight: .bold))
                .foregroundStyle(DesignSystem.Colors.textTertiary.opacity(0.5))

            subPipelineStep(
                "Observe",
                icon: "eye",
                isCompleted: hasObservation || fixCompleted,
                isCurrent: (debugStore.phase == .fixing || debugStore.phase == .instrumenting) && hasInstrumentation && !hasObservation
            )

            Spacer()

            if debugStore.fixLoopIteration > 0 {
                HStack(spacing: 3) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.system(size: 8))
                    Text("×\(debugStore.fixLoopIteration)")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                }
                .foregroundStyle(DesignSystem.Colors.warning)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(DesignSystem.Colors.warning.opacity(0.1), in: Capsule())
            }
        }
        .padding(.horizontal, 4)
    }

    private func subPipelineStep(_ label: String, icon: String, isCompleted: Bool, isCurrent: Bool) -> some View {
        let color: Color = isCompleted
        ? DesignSystem.Colors.success
        : (isCurrent ? accent : DesignSystem.Colors.textTertiary)

        return HStack(spacing: 4) {
            Image(systemName: isCompleted ? "checkmark.circle.fill" : icon)
                .font(.system(size: 8))
            Text(label.uppercased())
                .font(.system(size: 7.5, weight: isCurrent ? .bold : .semibold, design: .monospaced))
        }
        .foregroundStyle(color)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(color.opacity(isCurrent ? 0.12 : 0.06))
        )
    }

    private func shortLabel(for phase: DebugFlowPhase) -> String {
        switch phase {
        case .describing: return "ANALYZE"
        case .reproducing: return "REPRO"
        case .fixing, .instrumenting: return "FIX"
        case .verifying: return "VERIFY"
        case .resolved: return "DONE"
        case .idle: return ""
        }
    }

    private var phaseDetailLabel: String {
        switch debugStore.phase {
        case .idle:          return ""
        case .describing:    return "Analyzing the problem and gathering context…"
        case .reproducing:   return "Waiting for bug reproduction…"
        case .fixing:        return "Applying fix hypotheses…"
        case .instrumenting: return "Instrumenting code to observe behavior…"
        case .verifying:     return "Verifying the fix and running checks…"
        case .resolved:      return "Debug session resolved."
        }
    }

    // MARK: - Tab Strip

    private var tabStrip: some View {
        HStack(spacing: 0) {
            ForEach(DebugTab.allCases, id: \.self) { tab in
                tabButton(tab)
            }

            Spacer()

            filterToggle
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
    }

    private func tabButton(_ tab: DebugTab) -> some View {
        let isActive = selectedTab == tab
        let badgeCount = tabBadgeCount(tab)

        return Button {
            withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
                selectedTab = tab
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: tab.icon)
                    .font(.system(size: 9))
                Text(tab.rawValue)
                    .font(.system(size: 11, weight: isActive ? .semibold : .regular))

                if badgeCount > 0 {
                    Text("\(badgeCount)")
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .foregroundStyle(isActive ? accent : .secondary)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(
                            (isActive ? accent : Color.secondary).opacity(0.12),
                            in: Capsule()
                        )
                }
            }
            .foregroundStyle(isActive ? accent : DesignSystem.Colors.textSecondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isActive ? accent.opacity(0.08) : Color.clear)
            )
        }
        .buttonStyle(.plain)
    }

    private func tabBadgeCount(_ tab: DebugTab) -> Int {
        switch tab {
        case .logs: return debugStore.filteredLogs.count
        case .runtime:
            return debugStore.currentRunId == nil
                ? debugStore.runtimeLogs.count
                : debugStore.currentRunLogs.count
        case .hypotheses: return debugStore.hypotheses.count
        case .markers: return debugStore.debugMarkers.count + debugStore.instrumentationPoints.count
        }
    }

    private var filterToggle: some View {
        Button {
            withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
                isFilterExpanded.toggle()
            }
        } label: {
            Image(systemName: "line.3.horizontal.decrease.circle")
                .font(.system(size: 12))
                .foregroundStyle(
                    isFilterExpanded || debugStore.severityFilter.count < DebugEntrySeverity.allCases.count
                    ? accent
                    : DesignSystem.Colors.textTertiary
                )
                .frame(width: 28, height: 28)
                .background(
                    (isFilterExpanded ? accent.opacity(0.08) : Color.clear),
                    in: RoundedRectangle(cornerRadius: 6)
                )
        }
        .buttonStyle(.plain)
        .help("Filter severity")
    }

    // MARK: - Scroll Content

    private var scrollContent: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    if isFilterExpanded {
                        filterBar
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }

                    if !debugStore.debugFlowDiagram.isEmpty {
                        MermaidDiagramView(
                            mermaidCode: debugStore.debugFlowDiagram,
                            accentColor: accent
                        )
                    }

                    if !taskActivities.isEmpty {
                        CompactActivityTraceView(
                            activities: taskActivities,
                            accentColor: accent,
                            title: "Activity"
                        )
                    }

                    if !todoStore.todos.isEmpty {
                        todosCard
                    }

                    tabContent

                    Color.clear.frame(height: 1).id("debug-scroll-anchor")
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
            .onChange(of: debugStore.logs.count) {
                withAnimation(.easeOut(duration: 0.2)) {
                    proxy.scrollTo("debug-scroll-anchor", anchor: .bottom)
                }
            }
            .onChange(of: debugStore.runtimeLogs.count) {
                withAnimation(.easeOut(duration: 0.2)) {
                    proxy.scrollTo("debug-scroll-anchor", anchor: .bottom)
                }
            }
        }
    }

    // MARK: - Filter Bar

    private var filterBar: some View {
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

    private func severityFilterChip(_ severity: DebugEntrySeverity) -> some View {
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

    // MARK: - Tab Content

    @ViewBuilder
    private var tabContent: some View {
        switch selectedTab {
        case .logs:       logsContent
        case .runtime:    runtimeLogsContent
        case .hypotheses: hypothesesContent
        case .markers:    markersContent
        }
    }

    // MARK: - Todos Card

    private var todosCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "checklist")
                    .font(.system(size: 10))
                    .foregroundStyle(accent.opacity(0.7))
                Text("Tasks")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(DesignSystem.Colors.textSecondary)
                Spacer()
                let done = todoStore.todos.filter { $0.status == .done }.count
                Text("\(done)/\(todoStore.todos.count)")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(DesignSystem.Colors.textTertiary)
            }

            ForEach(todoStore.todos) { item in
                HStack(spacing: 6) {
                    Image(systemName: todoIcon(item.status))
                        .font(.system(size: 9))
                        .foregroundStyle(todoColor(item.status))
                    Text(item.title)
                        .font(.system(size: 10.5))
                        .foregroundStyle(item.status == .done ? DesignSystem.Colors.textTertiary : DesignSystem.Colors.textPrimary)
                        .lineLimit(1)
                        .strikethrough(item.status == .done)
                    Spacer()
                }
                .padding(.vertical, 2)
            }
        }
        .padding(10)
        .background(Color.primary.opacity(0.02), in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(DesignSystem.Colors.borderSubtle, lineWidth: 0.5)
        )
    }

    private func todoIcon(_ status: TodoStatus) -> String {
        switch status {
        case .pending:    return "circle"
        case .inProgress: return "circle.dotted"
        case .done:       return "checkmark.circle.fill"
        case .blocked:    return "exclamationmark.circle"
        }
    }

    private func todoColor(_ status: TodoStatus) -> Color {
        switch status {
        case .pending:    return .secondary
        case .inProgress: return accent
        case .done:       return DesignSystem.Colors.success
        case .blocked:    return DesignSystem.Colors.error
        }
    }

    // MARK: - Logs Content

    private var logsContent: some View {
        Group {
            if debugStore.filteredLogs.isEmpty {
                emptyState(
                    icon: "doc.text",
                    title: "No logs yet",
                    subtitle: "Debug logs will appear as the agent analyzes the issue"
                )
            } else {
                ForEach(debugStore.filteredLogs) { entry in
                    logRow(entry)
                }
            }
        }
    }

    private func logRow(_ entry: DebugLogEntry) -> some View {
        let isExpanded = expandedLogId == entry.id

        return VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.spring(response: 0.2, dampingFraction: 0.85)) {
                    expandedLogId = isExpanded ? nil : entry.id
                }
            } label: {
                HStack(alignment: .top, spacing: 8) {
                    Circle()
                        .fill(entry.severity.color)
                        .frame(width: 6, height: 6)
                        .padding(.top, 5)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(entry.message)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(DesignSystem.Colors.textPrimary)
                            .lineLimit(isExpanded ? nil : 2)
                            .multilineTextAlignment(.leading)

                        HStack(spacing: 6) {
                            Text(entry.source)
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundStyle(DesignSystem.Colors.textTertiary)

                            if let cat = entry.category {
                                Text(cat)
                                    .font(.system(size: 8, weight: .medium))
                                    .foregroundStyle(DesignSystem.Colors.textSecondary)
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 1)
                                    .background(Color.primary.opacity(0.04), in: Capsule())
                            }

                            Spacer()

                            Text(timeString(entry.timestamp))
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundStyle(DesignSystem.Colors.textQuaternary)
                        }
                    }
                }
                .padding(.vertical, 6)
                .padding(.horizontal, 6)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded, let detail = entry.detail {
                Text(detail)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(DesignSystem.Colors.textSecondary)
                    .padding(.leading, 22)
                    .padding(.vertical, 6)
                    .padding(.horizontal, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.primary.opacity(0.02), in: RoundedRectangle(cornerRadius: 6))
                    .padding(.bottom, 4)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            divider.opacity(0.5)
        }
    }

    // MARK: - Hypotheses Content

    private var hypothesesContent: some View {
        Group {
            if debugStore.hypotheses.isEmpty {
                emptyState(
                    icon: "lightbulb",
                    title: "No hypotheses yet",
                    subtitle: "The agent will form hypotheses during analysis"
                )
            } else {
                ForEach(debugStore.hypotheses) { h in
                    hypothesisCard(h)
                }
            }
        }
    }

    private func hypothesisCard(_ h: DebugHypothesis) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(h.status.color.opacity(0.12))
                        .frame(width: 26, height: 26)
                    Image(systemName: h.status.icon)
                        .font(.system(size: 11))
                        .foregroundStyle(h.status.color)
                }

                VStack(alignment: .leading, spacing: 1) {
                    Text(h.title)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(DesignSystem.Colors.textPrimary)
                        .lineLimit(2)
                    Text(h.status.rawValue.capitalized)
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundStyle(h.status.color)
                }

                Spacer()
            }

            Text(h.description)
                .font(.system(size: 11))
                .foregroundStyle(DesignSystem.Colors.textSecondary)
                .lineLimit(4)

            if !h.evidence.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Evidence")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(DesignSystem.Colors.textTertiary)
                        .textCase(.uppercase)
                        .tracking(0.5)

                    ForEach(h.evidence, id: \.self) { ev in
                        HStack(alignment: .top, spacing: 6) {
                            Image(systemName: "arrow.right")
                                .font(.system(size: 7, weight: .bold))
                                .foregroundStyle(h.status.color.opacity(0.6))
                                .padding(.top, 3)
                            Text(ev)
                                .font(.system(size: 10))
                                .foregroundStyle(DesignSystem.Colors.textSecondary)
                                .lineLimit(2)
                        }
                    }
                }
                .padding(.top, 2)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.primary.opacity(0.02))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(h.status.color.opacity(0.15), lineWidth: 0.5)
        )
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 1)
                .fill(h.status.color.opacity(0.4))
                .frame(width: 2.5)
                .padding(.vertical, 6)
        }
    }

    // MARK: - Runtime Logs

    private var runtimeLogsContent: some View {
        let runtimeEntries = debugStore.currentRunId == nil
            ? debugStore.runtimeLogs
            : debugStore.currentRunLogs

        return Group {
            if runtimeEntries.isEmpty {
                emptyState(
                    icon: "waveform.path.ecg",
                    title: "No runtime logs",
                    subtitle: "Runtime logs appear when the agent instruments code"
                )
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    if let runId = debugStore.currentRunId {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(accent)
                                .frame(width: 6, height: 6)
                            Text("Run \(runId.prefix(8))…")
                                .font(.system(size: 10, weight: .medium, design: .monospaced))
                                .foregroundStyle(DesignSystem.Colors.textSecondary)
                            Spacer()
                            Text("\(debugStore.currentRunLogs.count) entries")
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundStyle(DesignSystem.Colors.textTertiary)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(accent.opacity(0.04), in: RoundedRectangle(cornerRadius: 6))
                    }

                    ForEach(runtimeEntries) { entry in
                        runtimeLogRow(entry)
                    }
                }
            }
        }
    }

    private func runtimeLogRow(_ entry: RuntimeLogEntry) -> some View {
        let isExpanded = expandedRuntimeLogId == entry.id

        return VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.spring(response: 0.2, dampingFraction: 0.85)) {
                    expandedRuntimeLogId = isExpanded ? nil : entry.id
                }
            } label: {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "waveform")
                        .font(.system(size: 9))
                        .foregroundStyle(accent.opacity(0.6))
                        .frame(width: 14)
                        .padding(.top, 2)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(entry.message)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(DesignSystem.Colors.textPrimary)
                            .lineLimit(isExpanded ? nil : 2)

                        HStack(spacing: 6) {
                            Text(entry.location)
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundStyle(DesignSystem.Colors.textTertiary)

                            if let hid = entry.hypothesisId {
                                Text("H:\(hid.prefix(6))")
                                    .font(.system(size: 8, weight: .medium, design: .monospaced))
                                    .foregroundStyle(DesignSystem.Colors.warning)
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 1)
                                    .background(DesignSystem.Colors.warning.opacity(0.1), in: Capsule())
                            }

                            Spacer()

                            Text(timeString(entry.timestamp))
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundStyle(DesignSystem.Colors.textQuaternary)
                        }
                    }
                }
                .padding(.vertical, 5)
                .padding(.horizontal, 6)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded && !entry.data.isEmpty {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(entry.data.sorted(by: { $0.key < $1.key }), id: \.key) { key, value in
                        HStack(spacing: 4) {
                            Text(key)
                                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                                .foregroundStyle(accent)
                            Text("=")
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundStyle(DesignSystem.Colors.textTertiary)
                            Text(value)
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundStyle(DesignSystem.Colors.textSecondary)
                                .lineLimit(3)
                        }
                    }
                }
                .padding(.leading, 22)
                .padding(.vertical, 6)
                .padding(.horizontal, 8)
                .background(accent.opacity(0.03), in: RoundedRectangle(cornerRadius: 6))
                .padding(.bottom, 4)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }

            divider.opacity(0.5)
        }
    }

    // MARK: - Markers Content

    private var markersContent: some View {
        Group {
            if !debugStore.instrumentationPoints.isEmpty {
                instrumentationSection
            }

            if debugStore.debugMarkers.isEmpty && debugStore.instrumentationPoints.isEmpty {
                emptyState(
                    icon: "mappin.slash",
                    title: "No markers",
                    subtitle: "The agent inserts markers during the fix phase"
                )
            } else if !debugStore.debugMarkers.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("\(debugStore.debugMarkers.count) markers in \(debugStore.markedFileCount) files")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(DesignSystem.Colors.textSecondary)
                        Spacer()
                    }

                    ForEach(debugStore.debugMarkers) { marker in
                        markerRow(marker)
                    }
                }
            }
        }
    }

    private var instrumentationSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "wrench.and.screwdriver.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(DesignSystem.Colors.info)
                Text("Instrumentation")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(DesignSystem.Colors.textSecondary)
                Spacer()
                Text("\(debugStore.instrumentationPoints.count) in \(debugStore.instrumentedFileCount) files")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(DesignSystem.Colors.textTertiary)
            }

            ForEach(debugStore.instrumentationPoints) { point in
                instrumentationRow(point)
            }
        }
        .padding(10)
        .background(DesignSystem.Colors.info.opacity(0.03), in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(DesignSystem.Colors.info.opacity(0.1), lineWidth: 0.5)
        )
    }

    private func instrumentationRow(_ point: InstrumentationPoint) -> some View {
        HStack(spacing: 8) {
            Image(systemName: instrumentationIcon(point.type))
                .font(.system(size: 10))
                .foregroundStyle(instrumentationColor(point.type))

            VStack(alignment: .leading, spacing: 1) {
                Text((point.filePath as NSString).lastPathComponent)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(DesignSystem.Colors.textPrimary)
                HStack(spacing: 4) {
                    Text("L\(point.lineNumber)")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(DesignSystem.Colors.textSecondary)
                    Text(point.type.rawValue)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(instrumentationColor(point.type))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(instrumentationColor(point.type).opacity(0.1), in: Capsule())
                }
            }

            Spacer()

            Button {
                debugStore.removeInstrumentation(id: point.id)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9))
                    .foregroundStyle(DesignSystem.Colors.textTertiary)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 3)
        .padding(.horizontal, 4)
    }

    private func instrumentationIcon(_ type: InstrumentationPoint.InstrumentationType) -> String {
        switch type {
        case .logging:    return "text.quote"
        case .assertion:  return "exclamationmark.triangle"
        case .timing:     return "clock"
        case .variable:   return "curlybraces"
        }
    }

    private func instrumentationColor(_ type: InstrumentationPoint.InstrumentationType) -> Color {
        switch type {
        case .logging:    return DesignSystem.Colors.info
        case .assertion:  return DesignSystem.Colors.warning
        case .timing:     return .purple
        case .variable:   return .cyan
        }
    }

    private func markerRow(_ marker: DebugMarker) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "mappin.circle.fill")
                .font(.system(size: 10))
                .foregroundStyle(accent)

            VStack(alignment: .leading, spacing: 1) {
                Text((marker.filePath as NSString).lastPathComponent)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(DesignSystem.Colors.textPrimary)
                HStack(spacing: 4) {
                    Text("Line \(marker.lineNumber)")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(DesignSystem.Colors.textSecondary)
                    Text(marker.markerComment)
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(DesignSystem.Colors.textTertiary)
                        .lineLimit(1)
                }
            }

            Spacer()

            Button {
                debugStore.removeDebugMarker(id: marker.id)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9))
                    .foregroundStyle(DesignSystem.Colors.textTertiary)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 6)
        .background(Color.primary.opacity(0.02), in: RoundedRectangle(cornerRadius: 6))
    }

    // MARK: - Streaming Banner

    private var streamingBanner: some View {
        HStack(alignment: .top, spacing: 8) {
            ProgressView()
                .controlSize(.mini)
                .tint(accent)
                .padding(.top, 2)

            Text(debugStore.streamingContent)
                .font(.system(size: 11))
                .foregroundStyle(DesignSystem.Colors.textSecondary)
                .lineLimit(4)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(10)
        .background(accent.opacity(0.03))
    }

    // MARK: - Question Cards

    private var questionCards: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(accent.opacity(0.1))
                        .frame(width: 26, height: 26)
                    Image(systemName: "questionmark.bubble.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(accent)
                }

                VStack(alignment: .leading, spacing: 1) {
                    Text("Agent needs your input")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(DesignSystem.Colors.textPrimary)
                    Text(phaseClarificationSubtitle)
                        .font(.system(size: 10))
                        .foregroundStyle(DesignSystem.Colors.textTertiary)
                }
            }

            Text(debugStore.clarificationQuestions)
                .font(.system(size: 11.5))
                .foregroundStyle(DesignSystem.Colors.textPrimary)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.primary.opacity(0.03))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(accent.opacity(0.12), lineWidth: 0.5)
                )
        }
        .padding(12)
        .background(accent.opacity(0.03))
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    private var phaseClarificationSubtitle: String {
        switch debugStore.phase {
        case .describing:    return "Help the agent understand the issue"
        case .reproducing:   return "Steps to reproduce the bug"
        case .fixing:        return "Clarification about the fix approach"
        case .instrumenting: return "Details about code behavior"
        case .verifying:     return "Confirm verification results"
        default:             return "Please answer the question below"
        }
    }

    // MARK: - Phase Action Area

    @ViewBuilder
    private var phaseActionArea: some View {
        if debugStore.phase == .reproducing {
            divider
            reproduceAction
        }

        if debugStore.phase == .verifying {
            divider
            verifyAction
        }

        if debugStore.phase == .resolved {
            divider
            resolutionBanner
        }
    }

    private var reproduceAction: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(DesignSystem.Colors.warning.opacity(0.12))
                        .frame(width: 28, height: 28)
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.system(size: 12))
                        .foregroundStyle(DesignSystem.Colors.warning)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("Reproduce the bug")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(DesignSystem.Colors.textPrimary)
                    Text("Follow the steps above, then confirm")
                        .font(.system(size: 10.5))
                        .foregroundStyle(DesignSystem.Colors.textSecondary)
                }
            }

            Button(action: onProceed) {
                HStack(spacing: 6) {
                    Image(systemName: "play.fill")
                        .font(.system(size: 10))
                    Text("Proceed")
                        .font(.system(size: 12, weight: .semibold))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(accent, in: RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .background(DesignSystem.Colors.warning.opacity(0.04))
    }

    private var verifyAction: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(DesignSystem.Colors.success.opacity(0.12))
                        .frame(width: 28, height: 28)
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(DesignSystem.Colors.success)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("Verification")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(DesignSystem.Colors.textPrimary)
                    Text("Verify the fix, then mark as resolved")
                        .font(.system(size: 10.5))
                        .foregroundStyle(DesignSystem.Colors.textSecondary)
                }
            }

            HStack(spacing: 10) {
                Button(action: onFixed) {
                    HStack(spacing: 6) {
                        if debugStore.awaitingDebugClean {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Image(systemName: "checkmark.seal.fill")
                                .font(.system(size: 10))
                        }
                        Text(debugStore.awaitingDebugClean ? "Cleaning…" : "Mark Fixed")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(
                        debugStore.awaitingDebugClean
                        ? DesignSystem.Colors.warning
                        : DesignSystem.Colors.success,
                        in: RoundedRectangle(cornerRadius: 8)
                    )
                }
                .buttonStyle(.plain)
                .disabled(debugStore.awaitingDebugClean)
            }

            let totalFiles = Set(
                debugStore.debugMarkers.map(\.filePath)
                + debugStore.instrumentationPoints.map(\.filePath)
            ).count
            if totalFiles > 0 {
                HStack(spacing: 4) {
                    Image(systemName: "doc.badge.gearshape")
                        .font(.system(size: 9))
                    Text("Will clean \(totalFiles) file\(totalFiles == 1 ? "" : "s")")
                        .font(.system(size: 10))
                }
                .foregroundStyle(DesignSystem.Colors.textTertiary)
            }
        }
        .padding(14)
        .background(DesignSystem.Colors.success.opacity(0.04))
    }

    private var resolutionBanner: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(DesignSystem.Colors.success.opacity(0.15))
                        .frame(width: 30, height: 30)
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(DesignSystem.Colors.success)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("Resolved")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(DesignSystem.Colors.success)

                    if !debugStore.resolutionSummary.isEmpty {
                        Text(debugStore.resolutionSummary)
                            .font(.system(size: 11))
                            .foregroundStyle(DesignSystem.Colors.textSecondary)
                            .lineLimit(3)
                    }
                }

                Spacer()
            }
        }
        .padding(14)
        .background(DesignSystem.Colors.success.opacity(0.04))
    }

    // MARK: - Chat Input

    private var chatInput: some View {
        HStack(spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "text.bubble")
                    .font(.system(size: 10))
                    .foregroundStyle(DesignSystem.Colors.textTertiary)

                TextField("Ask about the bug…", text: $userInput)
                    .textFieldStyle(.plain)
                    .font(.system(size: 11.5))
                    .focused($isChatInputFocused)
                    .onSubmit { submitInput() }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(
                        isChatInputFocused ? accent.opacity(0.3) : Color.clear,
                        lineWidth: 1
                    )
            )

            Button(action: submitInput) {
                Image(systemName: "arrow.up")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 26, height: 26)
                    .background(
                        userInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        ? Color.secondary.opacity(0.3)
                        : accent,
                        in: RoundedRectangle(cornerRadius: 7)
                    )
            }
            .buttonStyle(.plain)
            .disabled(userInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private func submitInput() {
        guard !userInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        onSubmitQuestion(userInput)
        userInput = ""
    }

    // MARK: - Empty State

    private func emptyState(icon: String, title: String, subtitle: String) -> some View {
        VStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(Color.primary.opacity(0.03))
                    .frame(width: 48, height: 48)
                Image(systemName: icon)
                    .font(.system(size: 20))
                    .foregroundStyle(DesignSystem.Colors.textTertiary)
            }

            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(DesignSystem.Colors.textSecondary)

            Text(subtitle)
                .font(.system(size: 10.5))
                .foregroundStyle(DesignSystem.Colors.textTertiary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 200)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 36)
    }

    // MARK: - Helpers

    private func timeString(_ date: Date) -> String {
        DebugTimeFormatters.hms.string(from: date)
    }
}

private enum DebugTimeFormatters {
    static let hms: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()
}
