import CoderEngine
import SwiftUI

// MARK: - Task Control Bar (Fixed above composer)
/// Compact bar showing timer + pause/resume/stop controls.
/// Pinned between the messages scroll and the composer input.

struct TaskControlBar: View {
    @ObservedObject var chatStore: ChatStore
    @ObservedObject var taskActivityStore: TaskActivityStore
    @ObservedObject var executionController: ExecutionController

    let conversationId: UUID?
    let coderMode: CoderMode
    let isSummarizing: Bool
    let activeModeColor: Color
    let onInterrupt: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(DesignSystem.Colors.border)
                .frame(height: 0.5)

            if chatStore.isTaskActive(for: conversationId),
               let startDate = chatStore.taskStartDate(for: conversationId) {
                taskTimerBar(startDate: startDate)
            } else if isSummarizing {
                summarizingBanner
            }
        }
    }

    // MARK: - Timer Bar

    @ViewBuilder
    private func taskTimerBar(startDate: Date) -> some View {
        TimelineView(.periodic(from: startDate, by: 1.0)) { (context: TimelineViewDefaultContext) in
            let elapsed = Int(context.date.timeIntervalSince(startDate))
            HStack(spacing: 8) {
                // Pulsing dot
                Circle()
                    .fill(activeModeColor)
                    .frame(width: 6, height: 6)
                    .modifier(PulseModifier())

                Text(formatElapsed(elapsed))
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.primary)

                if let lastActivity = TaskActivityStore.lastConcreteVisibleActivity(
                    in: taskActivityStore.activities
                ) {
                    Text("•")
                        .font(.system(size: 9))
                        .foregroundStyle(.quaternary)
                    Image(systemName: phaseIcon(lastActivity.phase))
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(phaseColor(lastActivity.phase))
                    Text(lastActivity.title)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                if taskActivityStore.activeOperationsCount > 0 {
                    Text("(\(taskActivityStore.activeOperationsCount) op)")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.tertiary)
                }

                Spacer()

                taskControlButtons
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(DesignSystem.Colors.backgroundSecondary.opacity(0.45))
        }
    }

    // MARK: - Controls

    @ViewBuilder
    private var taskControlButtons: some View {
        let scope = executionScope

        HStack(spacing: 6) {
            if executionController.runState == .paused {
                Button {
                    executionController.resume(scope: scope)
                    taskActivityStore.markResumed()
                    taskActivityStore.addActivity(
                        TaskActivity(
                            type: "process_resumed",
                            title: "Process resumed",
                            detail: "Execution resumed by user",
                            payload: [:],
                            phase: .executing,
                            isRunning: true
                        )
                    )
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "play.fill")
                            .font(.system(size: 9))
                        Text("Resume")
                            .font(.system(size: 11, weight: .medium))
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            } else {
                Button {
                    executionController.pause(scope: scope)
                    taskActivityStore.markPaused()
                    taskActivityStore.addActivity(
                        TaskActivity(
                            type: "process_paused",
                            title: "Process paused",
                            detail: "Execution paused by user",
                            payload: [:],
                            phase: .planning,
                            isRunning: false
                        )
                    )
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "pause.fill")
                            .font(.system(size: 9))
                        Text("Pause")
                            .font(.system(size: 11, weight: .medium))
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            Button {
                onInterrupt()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "stop.fill")
                        .font(.system(size: 9))
                    Text("Stop")
                        .font(.system(size: 11, weight: .medium))
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
            .controlSize(.small)
        }
    }

    // MARK: - Summarizing

    private var summarizingBanner: some View {
        HStack(spacing: 8) {
            ProgressView().controlSize(.small)
            Text("Compressing context…")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.35))
    }

    // MARK: - Helpers

    private var executionScope: ExecutionScope {
        switch coderMode {
        case .agentSwarm: return .swarm
        case .codeReviewMultiSwarm: return .review
        case .plan: return .plan
        default: return .agent
        }
    }

    private func formatElapsed(_ s: Int) -> String {
        let m = s / 60
        let sec = s % 60
        return m > 0 ? String(format: "%d:%02d", m, sec) : "\(sec)s"
    }

    private func phaseIcon(_ phase: ActivityPhase) -> String {
        switch phase {
        case .executing: return "terminal"
        case .editing: return "pencil"
        case .searching: return "magnifyingglass"
        case .planning: return "list.bullet.rectangle"
        case .thinking: return "gearshape"
        }
    }

    private func phaseColor(_ phase: ActivityPhase) -> Color {
        switch phase {
        case .executing: return .secondary
        case .editing: return .secondary
        case .searching: return .secondary
        case .planning: return .secondary
        case .thinking: return .secondary
        }
    }
}

// MARK: - Pulse Animation Modifier

struct PulseModifier: ViewModifier {
    @State private var isPulsing = false

    func body(content: Content) -> some View {
        content
            .opacity(isPulsing ? 0.3 : 1.0)
            .animation(
                .easeInOut(duration: 0.8).repeatForever(autoreverses: true),
                value: isPulsing
            )
            .onAppear { isPulsing = true }
    }
}

// MARK: - Task Activity Panel (Scrollable, expandable sections)
/// Shows live activities, terminals, grep results, etc. in the messages scroll area.
/// Each section is independently collapsible.

struct TaskActivityPanel: View {
    @ObservedObject var chatStore: ChatStore
    @ObservedObject var taskActivityStore: TaskActivityStore
    @ObservedObject var todoStore: TodoStore

    let conversationId: UUID?
    let coderMode: CoderMode
    let onOpenFile: (String) -> Void
    let effectivePrimaryPath: String?
    let showTodoSection: Bool

    @State private var selectedSwarmLaneId: String?
    @State private var isActivitiesExpanded = false
    @State private var isTerminalsExpanded = false
    @State private var isGrepExpanded = false
    @State private var isTodoExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if coderMode == .agentSwarm {
                swarmActivityContent
            } else {
                standardActivityContent
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .onChange(of: chatStore.activeTaskConversationIds) { oldSet, newSet in
            guard let cid = conversationId else { return }
            if oldSet.contains(cid) && !newSet.contains(cid) {
                isActivitiesExpanded = false
                isTerminalsExpanded = false
                isGrepExpanded = false
                isTodoExpanded = false
            }
        }
        .onAppear {
            if selectedSwarmLaneId == nil {
                selectedSwarmLaneId = taskActivityStore.swarmCardStates().first?.swarmId
            }
        }
        .onChange(of: taskActivityStore.activities.count) { _, _ in
            let laneStates = taskActivityStore.swarmCardStates()
            let valid = laneStates.contains { $0.swarmId == selectedSwarmLaneId }
            if !valid {
                selectedSwarmLaneId = laneStates.first?.swarmId
            }
            if selectedSwarmLaneId == nil {
                selectedSwarmLaneId =
                    laneStates.first(where: { $0.status == .running })?.swarmId
                    ?? laneStates.first?.swarmId
            }
        }
    }

    // MARK: - Standard Activity Content

    @ViewBuilder
    private var standardActivityContent: some View {
        let concreteActivities = taskActivityStore.activities.filter {
            TaskActivityStore.isConcreteVisibleEvent($0)
        }
        if chatStore.isTaskActive(for: conversationId) {
            liveModeBanner
        }

        // Plan trace
        if coderMode == .plan {
            PlanLiveTraceView(
                activities: taskActivityStore.planRelevantRecentActivities(limit: 60),
                workspaceHints: effectivePrimaryPath.map { [$0] } ?? [],
                onOpenFile: onOpenFile
            )
        }

        // Live activity (expandable)
        if !concreteActivities.isEmpty {
            expandableSection(
                title: "Live activity",
                count: concreteActivities.count,
                icon: "list.bullet.rectangle",
                color: .secondary,
                isExpanded: $isActivitiesExpanded
            ) {
                LiveActivityTimelineView(
                    activities: concreteActivities,
                    maxVisible: 20,
                    workspaceHints: effectivePrimaryPath.map { [$0] } ?? [],
                    onOpenFile: onOpenFile
                )
            }
        }

        // Web Search
        let webActivities = taskActivityStore.activities.filter {
            $0.type.hasPrefix("web_search")
        }
        if !webActivities.isEmpty {
            WebSearchLiveView(activities: taskActivityStore.activities)
        }

        // Terminals (expandable)
        let terminalActivities = taskActivityStore.activities.filter {
            $0.type == "command_execution" || $0.type == "bash"
                || ($0.type == "mcp_tool_call"
                    && ($0.payload["tool"] == "bash" || $0.payload["command"] != nil))
        }
        if !terminalActivities.isEmpty {
            expandableSection(
                title: "Terminals",
                count: terminalActivities.count,
                icon: "terminal",
                color: .secondary,
                isExpanded: $isTerminalsExpanded
            ) {
                ChatTerminalSessionsView(activities: taskActivityStore.activities)
            }
        }

        // Instant Grep (expandable)
        if !taskActivityStore.instantGreps.isEmpty {
            expandableSection(
                title: "Instant Grep",
                count: taskActivityStore.instantGreps.count,
                icon: "magnifyingglass",
                color: .secondary,
                isExpanded: $isGrepExpanded
            ) {
                InstantGrepCardsView(results: taskActivityStore.instantGreps) { match in
                    let fullPath: String
                    if (match.file as NSString).isAbsolutePath {
                        fullPath = match.file
                    } else {
                        let basePath = effectivePrimaryPath ?? ""
                        fullPath = (basePath as NSString).appendingPathComponent(match.file)
                    }
                    onOpenFile(fullPath)
                }
            }
        }

        // Todo
        if showTodoSection, !todoStore.todos.isEmpty {
            expandableSection(
                title: "Todo",
                count: todoStore.todos.count,
                icon: "checklist",
                color: .secondary,
                isExpanded: $isTodoExpanded
            ) {
                TodoLiveInlineCard(
                    store: todoStore,
                    onOpenFile: onOpenFile
                )
            }
        }

        // Remaining task activities (non-terminal, non-bash)
        let otherActivities = concreteActivities
            .filter {
                $0.type != "command_execution"
                    && $0.type != "bash"
                    && !$0.type.hasPrefix("web_search")
                    && $0.type != "todo_write"
                    && $0.type != "todo_read"
                    && $0.type != "plan_step_update"
            }
            .suffix(8)
        if !otherActivities.isEmpty {
            ForEach(Array(otherActivities)) { activity in
                TaskActivityRow(activity: activity)
            }
        }
    }

    // MARK: - Swarm Activity Content

    @ViewBuilder
    private var swarmActivityContent: some View {
        if chatStore.isTaskActive(for: conversationId) {
            liveModeBanner
        }

        let cards = taskActivityStore.swarmCardStates()
        let effectiveSwarmId = selectedSwarmLaneId ?? cards.first?.swarmId
        let selectedCard = cards.first(where: { $0.swarmId == effectiveSwarmId })
        let selectedLaneActivities = (selectedCard?.recentEvents ?? []).filter {
            TaskActivityStore.isConcreteVisibleEvent($0)
        }

        if let swarmId = effectiveSwarmId, !selectedLaneActivities.isEmpty {
            HStack {
                Text("Live details • Swarm \(swarmId)")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.top, 6)

            expandableSection(
                title: "Live activity",
                count: selectedLaneActivities.count,
                icon: "list.bullet.rectangle",
                color: .secondary,
                isExpanded: $isActivitiesExpanded
            ) {
                LiveActivityTimelineView(
                    activities: selectedLaneActivities,
                    maxVisible: 24,
                    workspaceHints: effectivePrimaryPath.map { [$0] } ?? [],
                    onOpenFile: onOpenFile
                )
            }

            let swarmTerminals = selectedLaneActivities.filter {
                $0.type == "command_execution" || $0.type == "bash"
                    || ($0.type == "mcp_tool_call"
                        && ($0.payload["tool"] == "bash" || $0.payload["command"] != nil))
            }
            if !swarmTerminals.isEmpty {
                expandableSection(
                    title: "Terminals",
                    count: swarmTerminals.count,
                    icon: "terminal",
                    color: .secondary,
                    isExpanded: $isTerminalsExpanded
                ) {
                    ChatTerminalSessionsView(activities: selectedLaneActivities)
                }
            }

            WebSearchLiveView(activities: selectedLaneActivities)
        }
    }

    @ViewBuilder
    private var liveModeBanner: some View {
        let isPaused = taskActivityStore.activities.last?.type == "process_paused"
        let phaseLabel: String = {
            if isPaused { return "Paused" }
            switch coderMode {
            case .plan: return "Plan"
            case .codeReviewMultiSwarm: return "Review"
            case .agentSwarm: return "Swarm"
            default: return "Agent"
            }
        }()
        let text: String = {
            if isPaused {
                return "Execution paused"
            }
            switch coderMode {
            case .plan:
                let hasStepUpdate = taskActivityStore.activities.contains { $0.type == "plan_step_update" }
                let hasExecutionSignal = taskActivityStore.activities.contains {
                    $0.type == "command_execution" || $0.type == "file_change"
                }
                if hasExecutionSignal || hasStepUpdate {
                    return "Plan: executing plan"
                }
                return "Plan: analyzing options"
            case .codeReviewMultiSwarm:
                let hasExecutionSignal = taskActivityStore.activities.contains {
                    $0.type == "command_execution" || $0.type == "file_change"
                }
                if hasExecutionSignal {
                    return "Code Review: Phase 2 (applying fixes)"
                }
                return "Code Review: Phase 1 (multi-swarm analysis)"
            case .agentSwarm:
                return "Swarm: orchestrating agents"
            default:
                return "Agent: task running"
            }
        }()
        let hint: String? = {
            guard !isPaused else { return "Press Resume to continue execution." }
            if coderMode == .codeReviewMultiSwarm {
                let hasExecutionSignal = taskActivityStore.activities.contains {
                    $0.type == "command_execution" || $0.type == "file_change"
                }
                if !hasExecutionSignal {
                    return "To apply fixes: send \"proceed with corrections\" or enable yolo."
                }
            }
            if coderMode == .plan {
                let hasStepUpdate = taskActivityStore.activities.contains { $0.type == "plan_step_update" }
                if !hasStepUpdate {
                    return "When the plan is ready, choose an option to start the implementation."
                }
            }
            return nil
        }()
        let accent: Color = .secondary

        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                if isPaused {
                    Image(systemName: "pause.circle.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(DesignSystem.Colors.error)
                } else {
                    ProgressView()
                        .controlSize(.small)
                }
                Text(phaseLabel)
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(accent)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color(nsColor: .controlBackgroundColor), in: Capsule())
                Text(text)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
            }
            if let hint {
                Text(hint)
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                    .lineLimit(2)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.4), in: RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Expandable Section

    @ViewBuilder
    private func expandableSection<Content: View>(
        title: String,
        count: Int,
        icon: String,
        color: Color,
        isExpanded: Binding<Bool>,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeOut(duration: 0.2)) {
                    isExpanded.wrappedValue.toggle()
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: isExpanded.wrappedValue ? "chevron.down" : "chevron.right")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.tertiary)
                        .frame(width: 12)
                    Image(systemName: icon)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(color)
                    Text(title)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                    if count > 0 {
                        Text("\(count)")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Color(nsColor: .controlBackgroundColor), in: Capsule())
                    }
                    Spacer()
                }
                .padding(.vertical, 6)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded.wrappedValue {
                content()
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(8)
        .background(
            Color(nsColor: .controlBackgroundColor).opacity(0.3),
            in: RoundedRectangle(cornerRadius: 10)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(DesignSystem.Colors.border.opacity(0.5), lineWidth: 0.5)
        )
    }
}

// MARK: - Changed Files Summary Card (Expandable with chevron)

struct ChangedFilesSummaryCard: View {
    @ObservedObject var gitPanelStore: GitPanelStore
    let onOpenFile: (String) -> Void
    let onUndoAll: () -> Void

    @State private var isExpanded = false

    var body: some View {
        if !gitPanelStore.changedFiles.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                // Header row - always visible, tappable
                Button {
                    withAnimation(.easeOut(duration: 0.2)) {
                        isExpanded.toggle()
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(
                            systemName: isExpanded ? "chevron.down" : "chevron.right"
                        )
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.tertiary)
                        .frame(width: 12)

                        Image(systemName: "doc.badge.gearshape")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(DesignSystem.Colors.agentColor)

                        Text("\(gitPanelStore.changedFiles.count) files changed")
                            .font(.system(size: 12, weight: .semibold))

                        Text("+\(gitPanelStore.totalAdded)")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(DesignSystem.Colors.success)
                        Text("-\(gitPanelStore.totalRemoved)")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(DesignSystem.Colors.error)

                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                // Expanded file list
                if isExpanded {
                    Rectangle()
                        .fill(DesignSystem.Colors.border.opacity(0.5))
                        .frame(height: 0.5)
                        .padding(.horizontal, 8)

                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(gitPanelStore.changedFiles) { file in
                            HStack(spacing: 8) {
                                Button {
                                    onOpenFile(file.path)
                                } label: {
                                    HStack(spacing: 6) {
                                        Image(systemName: fileIcon(for: file.path))
                                            .font(.system(size: 10))
                                            .foregroundStyle(.tertiary)
                                            .frame(width: 14)
                                        Text(file.path)
                                            .font(.system(size: 11.5, weight: .medium))
                                            .lineLimit(1)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                    }
                                }
                                .buttonStyle(.plain)

                                Text("+\(file.added)")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(DesignSystem.Colors.success)
                                Text("-\(file.removed)")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(DesignSystem.Colors.error)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 4)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(Color.primary.opacity(0.02))
                            )
                        }

                        // Undo button
                        HStack {
                            Spacer()
                            Button {
                                onUndoAll()
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: "arrow.uturn.backward")
                                        .font(.system(size: 10))
                                    Text("Undo all changes")
                                        .font(.system(size: 11, weight: .medium))
                                }
                                .foregroundStyle(DesignSystem.Colors.error)
                            }
                            .buttonStyle(.plain)
                            .disabled(gitPanelStore.changedFiles.isEmpty)
                        }
                        .padding(.top, 4)
                    }
                    .padding(.horizontal, 4)
                    .padding(.vertical, 8)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(nsColor: .controlBackgroundColor).opacity(0.55))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(DesignSystem.Colors.border, lineWidth: 0.6)
            )
        }
    }

    private func fileIcon(for path: String) -> String {
        let ext = (path as NSString).pathExtension.lowercased()
        switch ext {
        case "swift": return "swift"
        case "js", "ts", "jsx", "tsx": return "chevron.left.forwardslash.chevron.right"
        case "py": return "chevron.left.forwardslash.chevron.right"
        case "json", "yaml", "yml", "toml": return "doc.badge.gearshape"
        case "md", "txt": return "doc.text"
        case "css", "scss": return "paintbrush"
        case "html": return "globe"
        case "png", "jpg", "jpeg", "gif", "svg": return "photo"
        default: return "doc"
        }
    }
}
