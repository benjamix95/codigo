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

            // 4-phase progress bar (Describe → Reproduce → Fix → Verify)
            if debugStore.phase != .idle {
                fourPhaseProgressBar
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

            // Resolution summary + Fixed button
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

    // MARK: - 4-Phase Progress Bar

    private var fourPhaseProgressBar: some View {
        VStack(spacing: 6) {
            // Phase steps
            HStack(spacing: 0) {
                ForEach(Array(DebugFlowPhase.mainPhases.enumerated()), id: \.offset) { index, mainPhase in
                    let currentIndex = debugStore.phase.phaseIndex
                    let isCompleted = debugStore.phase == .resolved || index < currentIndex
                    let isCurrent = index == currentIndex && debugStore.phase.isActive
                    let _ = index > currentIndex // isUpcoming — reserved for future styling

                    HStack(spacing: 4) {
                        // Step circle
                        ZStack {
                            if isCompleted {
                                Circle()
                                    .fill(DesignSystem.Colors.success)
                                    .frame(width: 16, height: 16)
                                Image(systemName: "checkmark")
                                    .font(.system(size: 8, weight: .bold))
                                    .foregroundStyle(.white)
                            } else if isCurrent {
                                Circle()
                                    .fill(debugColor)
                                    .frame(width: 16, height: 16)
                                if debugStore.phase == .instrumenting {
                                    Image(systemName: "wrench.fill")
                                        .font(.system(size: 7, weight: .bold))
                                        .foregroundStyle(.white)
                                } else {
                                    ProgressView()
                                        .scaleEffect(0.4)
                                        .tint(.white)
                                }
                            } else {
                                Circle()
                                    .strokeBorder(Color.secondary.opacity(0.3), lineWidth: 1)
                                    .frame(width: 16, height: 16)
                                Text("\(index + 1)")
                                    .font(.system(size: 8, weight: .medium))
                                    .foregroundStyle(.tertiary)
                            }
                        }

                        // Phase label
                        Text(mainPhase.label)
                            .font(.system(size: 9, weight: isCurrent ? .semibold : .regular))
                            .foregroundStyle(
                                isCompleted ? DesignSystem.Colors.success :
                                isCurrent ? debugColor :
                                Color.secondary.opacity(0.5)
                            )
                            .lineLimit(1)
                    }

                    if index < DebugFlowPhase.mainPhases.count - 1 {
                        Spacer(minLength: 2)
                        // Connector line
                        Rectangle()
                            .fill(isCompleted ? DesignSystem.Colors.success.opacity(0.5) : Color.secondary.opacity(0.15))
                            .frame(height: 1)
                            .frame(maxWidth: 20)
                        Spacer(minLength: 2)
                    }
                }
            }

            // Current phase detail
            if debugStore.phase.isActive || debugStore.phase == .resolved {
                HStack(spacing: 4) {
                    if debugStore.phase == .resolved {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(DesignSystem.Colors.success)
                    }
                    Text(phaseDetailLabel)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(debugStore.phase == .resolved ? DesignSystem.Colors.success : .secondary)
                    Spacer()
                    if debugStore.phase == .instrumenting {
                        Text("\(debugStore.instrumentationPoints.count) points")
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(DesignSystem.Colors.info)
                    }
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(debugStore.phase == .resolved ? DesignSystem.Colors.success.opacity(0.04) : debugColor.opacity(0.04))
    }

    private var phaseDetailLabel: String {
        switch debugStore.phase {
        case .idle:          return ""
        case .describing:    return "Analyzing errors and logs..."
        case .reproducing:   return "Reproduce the bug, then Proceed"
        case .fixing:        return "Hypothesizing and applying fix..."
        case .instrumenting: return "Inserting instrumentation..."
        case .verifying:     return "Verifying fix..."
        case .resolved:      return "Resolved"
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

    // MARK: - Resolution Section (Fixed button)

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

            HStack(spacing: 10) {
                Button {
                    onFixed()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 11))
                        Text("Mark Fixed")
                            .font(.system(size: 12, weight: .semibold))
                        let totalArtifacts = debugStore.debugMarkers.count + debugStore.instrumentationPoints.count
                        if totalArtifacts > 0 {
                            Text("(\(totalArtifacts) artifacts)")
                                .font(.system(size: 10))
                                .foregroundStyle(.white.opacity(0.7))
                        }
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(DesignSystem.Colors.success, in: RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
                .help("Mark as fixed — removes all debug markers and instrumentation from files")

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
