import SwiftUI
import CoderEngine

/// Debug panel — Cursor-style side panel for debugging sessions.
/// Shows debug logs, hypotheses, breakpoints, activity trace, and agent analysis.
struct DebugPanelView: View {
    @ObservedObject var debugStore: DebugStore
    @ObservedObject var taskActivityStore: TaskActivityStore
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

    private let topInteractiveInset: CGFloat = 22
    private let debugColor = DesignSystem.Colors.debugColor

    enum DebugTab: String, CaseIterable {
        case logs = "Logs"
        case runtime = "Runtime"
        case hypotheses = "Hypotheses"
        case markers = "Markers"
    }

    var body: some View {
        VStack(spacing: 0) {
            Color.clear
                .frame(height: topInteractiveInset)
                .allowsHitTesting(false)

            topBar
            Rectangle().fill(debugColor.opacity(0.3)).frame(height: 1)

            // Linear debug pipeline (Describe → Reproduce → Fix → Verify → Resolve)
            if debugStore.phase != .idle {
                linearProgressBar
            }

            // Tab bar
            tabBar
            Rectangle().fill(Color(nsColor: .separatorColor).opacity(0.3)).frame(height: 0.5)

            // Main scrollable content
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        // Mermaid debug flow diagram (collapsible)
                        if !debugStore.debugFlowDiagram.isEmpty {
                            MermaidDiagramView(
                                mermaidCode: debugStore.debugFlowDiagram,
                                accentColor: debugColor
                            )
                        }

                        // Compact activity trace (always visible when activities exist)
                        if !taskActivityStore.activities.isEmpty {
                            CompactActivityTraceView(
                                activities: taskActivityStore.activities,
                                accentColor: debugColor,
                                title: "Activity"
                            )
                        }

                        // Fix loop iteration badge
                        if debugStore.fixLoopIteration > 0 {
                            fixLoopBadge
                        }

                        // Todos section (compact)
                        if !todoStore.todos.isEmpty {
                            todosSection
                        }

                        // Tab content
                        switch selectedTab {
                        case .logs:
                            logsContent
                        case .runtime:
                            runtimeLogsContent
                        case .hypotheses:
                            hypothesesContent
                        case .markers:
                            markersContent
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                }
            }

            // Streaming content (when agent is working)
            if !debugStore.streamingContent.isEmpty && debugStore.phase != .idle && debugStore.phase != .resolved {
                Rectangle().fill(Color(nsColor: .separatorColor).opacity(0.3)).frame(height: 0.5)
                streamingSection
            }

            // Clarification questions + input (shown during describe phase)
            if !debugStore.clarificationQuestions.isEmpty && debugStore.phase == .describing {
                Rectangle().fill(Color(nsColor: .separatorColor).opacity(0.3)).frame(height: 0.5)
                questionSection
            }

            // Reproduce phase — Proceed button
            if debugStore.phase == .reproducing {
                Rectangle().fill(Color(nsColor: .separatorColor).opacity(0.3)).frame(height: 0.5)
                reproduceSection
            }

            // Verify cleanup + Mark Fixed action
            if debugStore.phase == .verifying {
                Rectangle().fill(Color(nsColor: .separatorColor).opacity(0.3)).frame(height: 0.5)
                verifyCleanupSection
            }

            // Resolution summary
            if debugStore.phase == .resolved {
                Rectangle().fill(Color(nsColor: .separatorColor).opacity(0.3)).frame(height: 0.5)
                resolutionSection
            }

            // Bottom input bar
            Rectangle().fill(Color(nsColor: .separatorColor).opacity(0.3)).frame(height: 0.5)
            bottomBar
        }
        .background(DesignSystem.Colors.backgroundDeep)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(debugColor.opacity(0.25), lineWidth: 1)
        )
        .shadow(color: debugColor.opacity(0.08), radius: 8, y: 2)
        .frame(minWidth: 320, idealWidth: 380, maxWidth: 440)
    }

    // MARK: - Top Bar

    private var topBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "ladybug.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(debugColor)

            Text("Debug")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.primary)

            if debugStore.errorCount > 0 {
                badgeChip(icon: "xmark.circle.fill", count: debugStore.errorCount, color: DesignSystem.Colors.error)
            }
            if debugStore.warningCount > 0 {
                badgeChip(icon: "exclamationmark.triangle.fill", count: debugStore.warningCount, color: DesignSystem.Colors.warning)
            }
            if !debugStore.debugMarkers.isEmpty {
                badgeChip(icon: "mappin.circle.fill", count: debugStore.debugMarkers.count, color: debugColor)
            }
            if !debugStore.instrumentationPoints.isEmpty {
                badgeChip(icon: "wrench.and.screwdriver.fill", count: debugStore.instrumentationPoints.count, color: DesignSystem.Colors.info)
            }

            Spacer()

            if debugStore.phase != .idle && debugStore.phase != .resolved {
                Button { onStop() } label: {
                    Image(systemName: "stop.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(debugColor)
                        .padding(4)
                        .background(debugColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 4))
                }
                .buttonStyle(.plain)
                .help("Stop debug session")
            }

            Button { debugStore.clearLogs() } label: {
                Image(systemName: "trash")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Clear logs")

            Button { onClose() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .padding(4)
                    .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 4))
            }
            .buttonStyle(.plain)
            .help("Close (Cmd+Shift+D)")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private func badgeChip(icon: String, count: Int, color: Color) -> some View {
        HStack(spacing: 2) {
            Image(systemName: icon)
                .font(.system(size: 9))
            Text("\(count)")
                .font(.system(size: 10, weight: .bold))
        }
        .foregroundStyle(color)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(color.opacity(0.12), in: Capsule())
    }

    // MARK: - Linear Debug Progress

    private var primaryPhases: [DebugFlowPhase] {
        [.describing, .reproducing, .fixing, .verifying, .resolved]
    }

    private var currentPrimaryPhase: DebugFlowPhase {
        switch debugStore.phase {
        case .instrumenting:
            return .fixing
        default:
            return debugStore.phase
        }
    }

    private var currentPrimaryIndex: Int {
        primaryPhases.firstIndex(of: currentPrimaryPhase) ?? 0
    }

    private var linearProgressBar: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 6) {
                ForEach(Array(primaryPhases.enumerated()), id: \.offset) { index, phase in
                    let isCompleted = index < currentPrimaryIndex || currentPrimaryPhase == .resolved
                    let isCurrent = index == currentPrimaryIndex && currentPrimaryPhase != .resolved
                    let stepColor: Color = isCompleted
                        ? DesignSystem.Colors.success
                        : (isCurrent ? debugColor : .secondary.opacity(0.45))

                    HStack(spacing: 4) {
                        phaseBullet(isCompleted: isCompleted, isCurrent: isCurrent, color: stepColor)

                        Text(shortLabel(for: phase))
                            .font(.system(size: 9, weight: isCurrent ? .semibold : .medium, design: .monospaced))
                            .foregroundStyle(stepColor)
                    }

                    if index < primaryPhases.count - 1 {
                        Text("→")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundStyle(
                                isCompleted
                                    ? DesignSystem.Colors.success.opacity(0.7)
                                    : DesignSystem.Colors.textTertiary
                            )
                    }
                }
            }

            if shouldShowFixSubpipeline {
                fixSubpipeline
            }

            Text(phaseDetailLabel)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(currentPrimaryPhase == .resolved ? DesignSystem.Colors.success : .secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(currentPrimaryPhase == .resolved ? DesignSystem.Colors.success.opacity(0.06) : debugColor.opacity(0.04))
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

    private var fixSubpipeline: some View {
        let hasHypothesis = !debugStore.hypotheses.isEmpty
        let hasInstrumentation = !debugStore.instrumentationPoints.isEmpty
        let hasObservation = !debugStore.runtimeLogs.isEmpty
        let fixCompleted = debugStore.phase == .verifying || debugStore.phase == .resolved

        return HStack(spacing: 5) {
            subStep(label: "HYPOTHESIZE", isCompleted: hasHypothesis || fixCompleted, isCurrent: debugStore.phase == .fixing && !hasHypothesis)
            Text("→").font(.system(size: 8, weight: .bold, design: .monospaced)).foregroundStyle(.tertiary)
            subStep(label: "INSTRUMENT", isCompleted: hasInstrumentation || fixCompleted, isCurrent: debugStore.phase == .instrumenting || (debugStore.phase == .fixing && hasHypothesis && !hasInstrumentation))
            Text("→").font(.system(size: 8, weight: .bold, design: .monospaced)).foregroundStyle(.tertiary)
            subStep(label: "OBSERVE", isCompleted: hasObservation || fixCompleted, isCurrent: (debugStore.phase == .fixing || debugStore.phase == .instrumenting) && hasInstrumentation && !hasObservation)
            Spacer()
        }
        .padding(.horizontal, 2)
    }

    private func subStep(label: String, isCompleted: Bool, isCurrent: Bool) -> some View {
        let color: Color = isCompleted
            ? DesignSystem.Colors.success
            : (isCurrent ? debugColor : DesignSystem.Colors.textTertiary)
        return Text(label)
            .font(.system(size: 8, weight: isCurrent ? .semibold : .medium, design: .monospaced))
            .foregroundStyle(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(isCurrent ? 0.14 : 0.08), in: Capsule())
    }

    @ViewBuilder
    private func phaseBullet(isCompleted: Bool, isCurrent: Bool, color: Color) -> some View {
        let base = Image(systemName: isCompleted ? "checkmark.circle.fill" : "circle.fill")
            .font(.system(size: isCurrent ? 9.5 : 8.5, weight: .semibold))
            .foregroundStyle(color)
        if isCurrent {
            base.modifier(PulseModifier())
        } else {
            base
        }
    }

    private func shortLabel(for phase: DebugFlowPhase) -> String {
        switch phase {
        case .describing: return "DESCRIBE"
        case .reproducing: return "REPRODUCE"
        case .fixing, .instrumenting: return "FIX"
        case .verifying: return "VERIFY"
        case .resolved: return "RESOLVE"
        case .idle: return "IDLE"
        }
    }

    private var phaseDetailLabel: String {
        switch debugStore.phase {
        case .idle:          return ""
        case .describing:    return "Descrizione del problema e raccolta contesto."
        case .reproducing:   return "Riproduci il bug o chiedi riproduzione utente."
        case .fixing:        return "Fix in corso con ipotesi mirate."
        case .instrumenting: return "Strumentazione attiva per osservare il comportamento."
        case .verifying:     return "Verifica finale e cleanup debug."
        case .resolved:      return "Debug risolto."
        }
    }

    // MARK: - Fix Loop Badge

    private var fixLoopBadge: some View {
        HStack(spacing: 6) {
            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.system(size: 10))
                .foregroundStyle(DesignSystem.Colors.warning)
            Text("Fix loop iteration \(debugStore.fixLoopIteration)")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(DesignSystem.Colors.warning)
            Spacer()
            Text("Verify failed — re-instrumenting")
                .font(.system(size: 9))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(DesignSystem.Colors.warning.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))
    }

    // MARK: - Tab Bar

    private var tabBar: some View {
        HStack(spacing: 0) {
            ForEach(DebugTab.allCases, id: \.self) { tab in
                Button {
                    withAnimation(.easeOut(duration: 0.15)) { selectedTab = tab }
                } label: {
                    Text(tab.rawValue)
                        .font(.system(size: 11, weight: selectedTab == tab ? .semibold : .regular))
                        .foregroundStyle(selectedTab == tab ? debugColor : .secondary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(
                            selectedTab == tab ? debugColor.opacity(0.1) : Color.clear,
                            in: RoundedRectangle(cornerRadius: 6)
                        )
                }
                .buttonStyle(.plain)
            }
            Spacer()

            HStack(spacing: 4) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                TextField("Filter...", text: $debugStore.searchQuery)
                    .textFieldStyle(.plain)
                    .font(.system(size: 11))
                    .frame(width: 80)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 4))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
    }

    // MARK: - Todos Section

    private var todosSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 5) {
                Image(systemName: "checklist")
                    .font(.system(size: 10))
                    .foregroundStyle(debugColor.opacity(0.7))
                Text("Tasks")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                let done = todoStore.todos.filter { $0.status == .done }.count
                Text("\(done)/\(todoStore.todos.count)")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 4)

            ForEach(todoStore.todos) { item in
                HStack(spacing: 6) {
                    Image(systemName: todoIcon(item.status))
                        .font(.system(size: 9))
                        .foregroundStyle(todoColor(item.status))
                    Text(item.title)
                        .font(.system(size: 10))
                        .foregroundStyle(item.status == .done ? .tertiary : .primary)
                        .lineLimit(1)
                        .strikethrough(item.status == .done)
                    Spacer()
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
            }
        }
        .padding(8)
        .background(Color.primary.opacity(0.02), in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(debugColor.opacity(0.1), lineWidth: 0.5)
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
        case .inProgress: return debugColor
        case .done:       return DesignSystem.Colors.success
        case .blocked:    return DesignSystem.Colors.error
        }
    }

    // MARK: - Logs Content

    private var logsContent: some View {
        ForEach(debugStore.filteredLogs) { entry in
            logEntryRow(entry)
        }
    }

    private func logEntryRow(_ entry: DebugLogEntry) -> some View {
        let isExpanded = expandedLogId == entry.id
        return VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeOut(duration: 0.12)) {
                    expandedLogId = isExpanded ? nil : entry.id
                }
            } label: {
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: entry.severity.icon)
                        .font(.system(size: 9))
                        .foregroundStyle(entry.severity.color)
                        .frame(width: 12)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(entry.message)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.primary)
                            .lineLimit(isExpanded ? nil : 2)
                            .multilineTextAlignment(.leading)

                        HStack(spacing: 6) {
                            Text(entry.source)
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundStyle(.tertiary)

                            if let cat = entry.category {
                                Text(cat)
                                    .font(.system(size: 9, weight: .medium))
                                    .foregroundStyle(Color.secondary.opacity(0.6))
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 1)
                                    .background(Color.primary.opacity(0.04), in: Capsule())
                            }

                            Spacer()

                            Text(timeString(entry.timestamp))
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundStyle(Color.secondary.opacity(0.4))
                        }
                    }
                }
                .padding(.vertical, 4)
                .padding(.horizontal, 4)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded, let detail = entry.detail {
                Text(detail)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .padding(.leading, 18)
                    .padding(.vertical, 4)
                    .padding(.horizontal, 4)
                    .background(Color.primary.opacity(0.03), in: RoundedRectangle(cornerRadius: 4))
                    .padding(.bottom, 4)
            }

            Rectangle().fill(Color(nsColor: .separatorColor).opacity(0.15)).frame(height: 0.5)
        }
    }

    // MARK: - Hypotheses Content

    private var hypothesesContent: some View {
        Group {
            if debugStore.hypotheses.isEmpty {
                emptyState(icon: "lightbulb", title: "No hypotheses yet", subtitle: "The agent will form hypotheses during debug analysis")
            } else {
                ForEach(debugStore.hypotheses) { hypothesis in
                    hypothesisRow(hypothesis)
                }
            }
        }
    }

    private func hypothesisRow(_ h: DebugHypothesis) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: h.status.icon)
                    .font(.system(size: 11))
                    .foregroundStyle(h.status.color)
                Text(h.title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.primary)
                Spacer()
                Text(h.status.rawValue.capitalized)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(h.status.color)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(h.status.color.opacity(0.12), in: Capsule())
            }

            Text(h.description)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(3)

            if !h.evidence.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Evidence:")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.tertiary)
                    ForEach(h.evidence, id: \.self) { ev in
                        HStack(spacing: 4) {
                            Circle().fill(.tertiary).frame(width: 3, height: 3)
                            Text(ev)
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                    }
                }
                .padding(.leading, 4)
            }
        }
        .padding(10)
        .background(Color.primary.opacity(0.03), in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(h.status.color.opacity(0.15), lineWidth: 0.5)
        )
        .padding(.vertical, 2)
    }

    // MARK: - Runtime Logs Content

    private var runtimeLogsContent: some View {
        Group {
            if debugStore.runtimeLogs.isEmpty {
                emptyState(
                    icon: "waveform.path.ecg",
                    title: "No runtime logs yet",
                    subtitle: "Runtime logs appear when the agent instruments code and the user reproduces the bug"
                )
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    // Run header
                    if let runId = debugStore.currentRunId {
                        HStack(spacing: 6) {
                            Image(systemName: "play.circle.fill")
                                .font(.system(size: 10))
                                .foregroundStyle(debugColor)
                            Text("Run: \(runId.prefix(8))...")
                                .font(.system(size: 10, weight: .medium, design: .monospaced))
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text("\(debugStore.currentRunLogs.count) entries")
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 4)
                        .background(debugColor.opacity(0.04), in: RoundedRectangle(cornerRadius: 4))
                    }

                    ForEach(debugStore.runtimeLogs) { entry in
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
                withAnimation(.easeOut(duration: 0.12)) {
                    expandedRuntimeLogId = isExpanded ? nil : entry.id
                }
            } label: {
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "waveform")
                        .font(.system(size: 9))
                        .foregroundStyle(debugColor.opacity(0.7))
                        .frame(width: 12)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(entry.message)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.primary)
                            .lineLimit(isExpanded ? nil : 2)

                        HStack(spacing: 6) {
                            Text(entry.location)
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundStyle(.tertiary)

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
                                .foregroundStyle(Color.secondary.opacity(0.4))
                        }
                    }
                }
                .padding(.vertical, 4)
                .padding(.horizontal, 4)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // Expanded: show data key-value pairs
            if isExpanded && !entry.data.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(entry.data.sorted(by: { $0.key < $1.key }), id: \.key) { key, value in
                        HStack(spacing: 4) {
                            Text(key)
                                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                                .foregroundStyle(debugColor)
                            Text("=")
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundStyle(.tertiary)
                            Text(value)
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .lineLimit(3)
                        }
                    }
                }
                .padding(.leading, 18)
                .padding(.vertical, 4)
                .padding(.horizontal, 4)
                .background(debugColor.opacity(0.03), in: RoundedRectangle(cornerRadius: 4))
                .padding(.bottom, 4)
            }

            Rectangle().fill(Color(nsColor: .separatorColor).opacity(0.15)).frame(height: 0.5)
        }
    }

    // MARK: - Markers Content

    private var markersContent: some View {
        Group {
            // Instrumentation points section
            if !debugStore.instrumentationPoints.isEmpty {
                instrumentationSection
            }

            if debugStore.debugMarkers.isEmpty && debugStore.instrumentationPoints.isEmpty {
                emptyState(icon: "mappin.slash", title: "No markers or instrumentation", subtitle: "The agent will insert debug markers and instrumentation during the fix phase")
            } else if !debugStore.debugMarkers.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("\(debugStore.debugMarkers.count) markers in \(debugStore.markedFileCount) files")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)
                        Spacer()
                    }

                    ForEach(debugStore.debugMarkers) { marker in
                        markerRow(marker)
                    }
                }
            }
        }
    }

    // MARK: - Instrumentation Section

    private var instrumentationSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "wrench.and.screwdriver.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(DesignSystem.Colors.info)
                Text("Instrumentation")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(debugStore.instrumentationPoints.count) in \(debugStore.instrumentedFileCount) files")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }

            ForEach(debugStore.instrumentationPoints) { point in
                instrumentationRow(point)
            }
        }
        .padding(8)
        .background(DesignSystem.Colors.info.opacity(0.03), in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(DesignSystem.Colors.info.opacity(0.12), lineWidth: 0.5)
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
                    .foregroundStyle(.primary)
                HStack(spacing: 4) {
                    Text("L\(point.lineNumber)")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)
                    Text(point.type.rawValue)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(instrumentationColor(point.type))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(instrumentationColor(point.type).opacity(0.1), in: Capsule())
                    if let hid = point.hypothesisId {
                        Text("H:\(hid.prefix(6))")
                            .font(.system(size: 8, design: .monospaced))
                            .foregroundStyle(DesignSystem.Colors.warning.opacity(0.7))
                    }
                }
            }

            Spacer()

            Button {
                debugStore.removeInstrumentation(id: point.id)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 3)
        .padding(.horizontal, 6)
    }

    private func instrumentationIcon(_ type: InstrumentationPoint.InstrumentationType) -> String {
        switch type {
        case .logging:   return "text.quote"
        case .assertion:  return "exclamationmark.triangle"
        case .timing:     return "clock"
        case .variable:   return "curlybraces"
        }
    }

    private func instrumentationColor(_ type: InstrumentationPoint.InstrumentationType) -> Color {
        switch type {
        case .logging:   return DesignSystem.Colors.info
        case .assertion:  return DesignSystem.Colors.warning
        case .timing:     return .purple
        case .variable:   return .cyan
        }
    }

    private func markerRow(_ marker: DebugMarker) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "mappin.circle.fill")
                .font(.system(size: 10))
                .foregroundStyle(debugColor)

            VStack(alignment: .leading, spacing: 1) {
                Text((marker.filePath as NSString).lastPathComponent)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(.primary)
                HStack(spacing: 4) {
                    Text("Line \(marker.lineNumber)")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)
                    Text(marker.markerComment)
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }

            Spacer()

            Button {
                debugStore.removeDebugMarker(id: marker.id)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 6)
        .background(Color.primary.opacity(0.02), in: RoundedRectangle(cornerRadius: 6))
    }

    // MARK: - Streaming Section

    private var streamingSection: some View {
        ScrollView {
            Text(debugStore.streamingContent)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
        }
        .frame(maxHeight: 120)
        .background(DesignSystem.Colors.backgroundSecondary)
    }

    // MARK: - Question Section

    private var questionSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "questionmark.circle.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(debugColor)
                Text("Agent needs info")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.primary)
            }
            Text(debugStore.clarificationQuestions)
                .font(.system(size: 11))
                .foregroundStyle(.primary)
        }
        .padding(10)
        .background(debugColor.opacity(0.04))
    }

    // MARK: - Reproduce Section (Proceed button)

    private var reproduceSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.system(size: 12))
                    .foregroundStyle(DesignSystem.Colors.warning)
                Text("Reproduce the bug")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.primary)
            }
            Text("Follow the steps above to reproduce the issue. When you've confirmed the bug, tap Proceed.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

            Button {
                onProceed()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "play.fill")
                        .font(.system(size: 11))
                    Text("Proceed")
                        .font(.system(size: 12, weight: .semibold))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(debugColor, in: RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .background(DesignSystem.Colors.warning.opacity(0.06))
    }

    // MARK: - Verify Cleanup Section

    private var verifyCleanupSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "checkmark.seal")
                    .foregroundStyle(DesignSystem.Colors.success)
                Text("Verification complete")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.primary)
            }

            Text("Run debug cleanup, verify success, then resolve the session.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

            HStack(spacing: 10) {
                Button {
                    onFixed()
                } label: {
                    HStack(spacing: 6) {
                        if debugStore.awaitingDebugClean {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Image(systemName: "checkmark.seal.fill")
                                .font(.system(size: 11))
                        }
                        Text(debugStore.awaitingDebugClean ? "Waiting for debug_clean" : "Mark Fixed")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(
                        debugStore.awaitingDebugClean ? DesignSystem.Colors.warning : DesignSystem.Colors.success,
                        in: RoundedRectangle(cornerRadius: 8)
                    )
                }
                .buttonStyle(.plain)
                .disabled(debugStore.awaitingDebugClean)
                .help("Run debug_clean and resolve after success")

                let totalFiles = Set(
                    debugStore.debugMarkers.map(\.filePath)
                    + debugStore.instrumentationPoints.map(\.filePath)
                ).count
                if totalFiles > 0 {
                    Text("Will clean \(totalFiles) files")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(12)
        .background(DesignSystem.Colors.success.opacity(0.06))
    }

    // MARK: - Resolution Section

    private var resolutionSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(DesignSystem.Colors.success)
                Text("Resolved")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(DesignSystem.Colors.success)
            }
            if !debugStore.resolutionSummary.isEmpty {
                Text(debugStore.resolutionSummary)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .background(DesignSystem.Colors.success.opacity(0.06))
    }

    // MARK: - Bottom Bar

    private var bottomBar: some View {
        HStack(spacing: 8) {
            // Severity filter chips
            HStack(spacing: 2) {
                severityChip(.error)
                severityChip(.warning)
                severityChip(.info)
            }

            Spacer()

            // Quick input for debug questions
            HStack(spacing: 4) {
                TextField("Ask about the bug...", text: $userInput)
                    .textFieldStyle(.plain)
                    .font(.system(size: 11))
                    .onSubmit { submitInput() }

                Button { submitInput() } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(
                            userInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                ? Color.secondary.opacity(0.5) : debugColor
                        )
                }
                .buttonStyle(.plain)
                .disabled(userInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }

    private func submitInput() {
        guard !userInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        onSubmitQuestion(userInput)
        userInput = ""
    }

    private func severityChip(_ severity: DebugEntrySeverity) -> some View {
        let isActive = debugStore.severityFilter.contains(severity)
        return Button {
            if isActive {
                debugStore.severityFilter.remove(severity)
            } else {
                debugStore.severityFilter.insert(severity)
            }
        } label: {
            Image(systemName: severity.icon)
                .font(.system(size: 9))
                .foregroundStyle(isActive ? severity.color : Color.secondary.opacity(0.4))
                .padding(3)
                .background(isActive ? severity.color.opacity(0.12) : Color.clear, in: Circle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Helpers

    private func emptyState(icon: String, title: String, subtitle: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 24))
                .foregroundStyle(.tertiary)
            Text(title)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            Text(subtitle)
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

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
