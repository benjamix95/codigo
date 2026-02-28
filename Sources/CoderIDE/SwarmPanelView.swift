import SwiftUI
import CoderEngine

/// Cursor-style sidebar panel for Subagent monitoring.
/// Shows overview of all subagents or detail for a specific subagent.
struct SwarmPanelView: View {
    @ObservedObject var taskActivityStore: TaskActivityStore
    @ObservedObject var swarmProgressStore: SwarmProgressStore
    @ObservedObject var todoStore: TodoStore
    @ObservedObject var chatStore: ChatStore

    let conversationId: UUID?
    let isTaskRunning: Bool
    @Binding var selectedSwarmId: String?
    @Binding var swarmOrchestrator: String
    @Binding var swarmWorkerBackend: String
    let onClose: () -> Void
    let onOpenFile: (String) -> Void
    let onSyncSwarmProvider: () -> Void

    @State private var expandedCardIds: Set<String> = []
    @State private var expandedEventIds: Set<UUID> = []
    @State private var isFollowingLive = true

    private let topInteractiveInset: CGFloat = 22
    private let swarmColor = DesignSystem.Colors.swarmColor

    // MARK: - Data

    /// Cached sorted cards — invalidated via swarmEventsReceivedCount.
    @State private var cachedCards: [SwarmLiveCardState] = []

    private var sortedCards: [SwarmLiveCardState] { cachedCards }

    private var runningCount: Int { cachedCards.filter { $0.status == .running }.count }
    private var failedCount: Int { cachedCards.filter { $0.status == .failed }.count }
    private var completedCount: Int { cachedCards.filter { $0.status == .completed }.count }

    /// Lightweight change counter — O(1) comparison instead of string diff.
    private var liveChangeCount: Int { taskActivityStore.swarmEventsReceivedCount }

    private var recentOverviewActivities: [TaskActivity] {
        Array(taskActivityStore.concreteRecentActivities(limit: 12).reversed())
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            Color.clear
                .frame(height: topInteractiveInset)
                .allowsHitTesting(false)
            topBar
            Rectangle().fill(swarmColor.opacity(0.3)).frame(height: 1)

            if !sortedCards.isEmpty {
                swarmSelector
                Rectangle().fill(Color(nsColor: .separatorColor).opacity(0.3)).frame(height: 0.5)
            }

            mainContent

            Rectangle().fill(Color(nsColor: .separatorColor).opacity(0.3)).frame(height: 0.5)
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
            refreshCachedCards()
            if selectedSwarmId == nil {
                selectedSwarmId = cachedCards.first(where: { $0.status == .running })?.swarmId
            }
        }
        .onChange(of: liveChangeCount) { _, _ in
            refreshCachedCards()
            if let selectedSwarmId,
               !cachedCards.contains(where: { $0.swarmId == selectedSwarmId }) {
                self.selectedSwarmId = nil
            }
            if selectedSwarmId == nil,
               let firstRunning = cachedCards.first(where: { $0.status == .running }) {
                selectedSwarmId = firstRunning.swarmId
            }
        }
    }

    private func refreshCachedCards() {
        cachedCards = SwarmLiveReducer.sorted(states: taskActivityStore.swarmCardStates())
            .filter { $0.swarmId != "orchestrator" }
    }

    // MARK: - Top Bar

    private var topBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "ant.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(swarmColor)

            Text("Subagent")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.primary)

            if runningCount > 0 {
                statusBadge("\(runningCount) running", color: swarmColor)
            }
            if failedCount > 0 {
                statusBadge("\(failedCount) failed", color: DesignSystem.Colors.error)
            }
            if completedCount > 0 {
                statusBadge("\(completedCount) done", color: DesignSystem.Colors.success)
            }

            Spacer()

            if isTaskRunning {
                ProgressView()
                    .controlSize(.mini)
            }

            Button {
                onClose()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 20, height: 20)
                    .background(Color.primary.opacity(0.06), in: Circle())
            }
            .buttonStyle(.plain)
            .help("Close Subagent panel")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    // MARK: - Status Badge

    private func statusBadge(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.12), in: Capsule())
    }

    // MARK: - Swarm Selector

    private var swarmSelector: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                selectorButton("Overview", isSelected: selectedSwarmId == nil) {
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
                        selectedSwarmId = nil
                    }
                }

                ForEach(sortedCards) { card in
                    selectorButton(
                        card.swarmId,
                        statusColor: cardStatusColor(card),
                        isSelected: selectedSwarmId == card.swarmId
                    ) {
                        withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
                            selectedSwarmId = card.swarmId
                        }
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
        }
    }

    @ViewBuilder
    private func selectorButton(
        _ title: String,
        statusColor: Color? = nil,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if let statusColor {
                    Circle()
                        .fill(statusColor)
                        .frame(width: 6, height: 6)
                }
                Text(title)
                    .font(.system(size: 10, weight: isSelected ? .semibold : .regular))
                    .lineLimit(1)
            }
            .foregroundStyle(isSelected ? swarmColor : .secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(isSelected ? swarmColor.opacity(0.14) : Color.clear)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Main Content

    @ViewBuilder
    private var mainContent: some View {
        if sortedCards.isEmpty {
            emptyState
        } else if let swarmId = selectedSwarmId, let card = sortedCards.first(where: { $0.swarmId == swarmId }) {
            detailView(for: card)
        } else {
            overviewList
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "ant.fill")
                .font(.system(size: 28))
                .foregroundStyle(.quaternary)
            Text("No subagent activity")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
            Text("Subagents will appear here when running")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(20)
    }

    // MARK: - Overview List

    private var overviewList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    // Progress steps
                    if !swarmProgressStore.steps.isEmpty {
                        progressSection
                    }

                    if !recentOverviewActivities.isEmpty {
                        overviewActivitySection
                    }

                    ForEach(sortedCards) { card in
                        overviewCard(card)
                            .id("swarm-card-\(card.swarmId)")
                    }
                }
                .padding(12)
            }
            .simultaneousGesture(DragGesture(minimumDistance: 2).onChanged { _ in
                isFollowingLive = false
            })
            .onChange(of: liveChangeCount) { _, _ in
                guard isFollowingLive else { return }
                if let firstRunning = cachedCards.first(where: { $0.status == .running }) {
                    withAnimation(.easeOut(duration: 0.2)) {
                        proxy.scrollTo("swarm-card-\(firstRunning.swarmId)", anchor: .top)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Progress Section

    private var progressSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 5) {
                Image(systemName: "checklist")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(swarmColor)
                Text("\(swarmProgressStore.steps.count) steps")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.tertiary)
                    .tracking(0.5)
            }

            ForEach(swarmProgressStore.steps) { step in
                HStack(alignment: .center, spacing: 6) {
                    Image(systemName: stepIcon(step))
                        .font(.system(size: 10))
                        .foregroundStyle(stepColor(step))
                    Text(step.name)
                        .font(.system(size: 11, weight: step.status == .inProgress ? .medium : .regular))
                        .foregroundStyle(step.status == .completed ? .tertiary : .primary)
                        .strikethrough(step.status == .completed)
                        .lineLimit(1)
                }
                .padding(.vertical, 1)
            }
        }
        .padding(10)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.2), in: RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Overview Activity Section

    private var overviewActivitySection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                Image(systemName: "waveform.path.ecg")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(swarmColor)
                Text("Subagent Activity")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(recentOverviewActivities.count)")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.tertiary)
            }

            ForEach(recentOverviewActivities) { activity in
                HStack(spacing: 5) {
                    Circle()
                        .fill(eventStatusColor(activity))
                        .frame(width: 5, height: 5)

                    Text(activity.title)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    if let swarmId = SwarmMetadata.swarmId(from: activity.payload)
                    {
                        Text(swarmId)
                            .font(.system(size: 8, weight: .semibold, design: .monospaced))
                            .foregroundStyle(swarmColor)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(swarmColor.opacity(0.12), in: Capsule())
                    }

                    Spacer()

                    Text(activity.timestamp.formatted(date: .omitted, time: .standard))
                        .font(.system(size: 8, design: .monospaced))
                        .foregroundStyle(.quaternary)
                }
            }
        }
        .padding(10)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.2), in: RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Overview Card

    @ViewBuilder
    private func overviewCard(_ card: SwarmLiveCardState) -> some View {
        let isExpanded = expandedCardIds.contains(card.swarmId)

        VStack(alignment: .leading, spacing: 6) {
            // Header row
            HStack(spacing: 6) {
                if card.status == .running {
                    Circle()
                        .fill(swarmColor)
                        .frame(width: 7, height: 7)
                        .modifier(PulseModifier())
                } else {
                    Circle()
                        .fill(cardStatusColor(card))
                        .frame(width: 7, height: 7)
                }

                Text(card.swarmId)
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .lineLimit(1)

                Text(card.status.rawValue)
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(cardStatusColor(card))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(cardStatusColor(card).opacity(0.12), in: Capsule())

                Spacer()

                if card.activeOpsCount > 0 {
                    Text("\(card.activeOpsCount) ops")
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundStyle(.tertiary)
                }

                if card.errorCount > 0 {
                    Text("\(card.errorCount) err")
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundStyle(DesignSystem.Colors.error)
                }
            }

            // Current step
            Text(card.currentStepTitle)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(isExpanded ? 4 : 1)

            // Expanded: show recent events
            if isExpanded {
                expandedCardEvents(card)
            }

            // Expand/detail controls
            HStack(spacing: 8) {
                Button(isExpanded ? "Collapse" : "Expand") {
                    withAnimation(.spring(response: 0.2, dampingFraction: 0.9)) {
                        if isExpanded {
                            expandedCardIds.remove(card.swarmId)
                        } else {
                            expandedCardIds.insert(card.swarmId)
                            taskActivityStore.setSwarmCardCollapsed(card.swarmId, collapsed: false)
                        }
                    }
                }
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)

                Button("View Detail") {
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
                        selectedSwarmId = card.swarmId
                    }
                }
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(swarmColor)

                Spacer()

                if let completedAt = card.completedAt {
                    Text(completedAt.formatted(date: .omitted, time: .standard))
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(.tertiary)
                } else if let lastEvent = card.lastEventAt {
                    Text(lastEvent.formatted(date: .omitted, time: .standard))
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(10)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.22), in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(cardStatusColor(card).opacity(0.2), lineWidth: 0.8)
        )
        .contentShape(RoundedRectangle(cornerRadius: 10))
        .onTapGesture {
            withAnimation(.spring(response: 0.2, dampingFraction: 0.9)) {
                if expandedCardIds.contains(card.swarmId) {
                    expandedCardIds.remove(card.swarmId)
                } else {
                    expandedCardIds.insert(card.swarmId)
                    taskActivityStore.setSwarmCardCollapsed(card.swarmId, collapsed: false)
                }
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Expanded Card Events (compact)

    @ViewBuilder
    private func expandedCardEvents(_ card: SwarmLiveCardState) -> some View {
        let events = card.recentEvents
            .filter { TaskActivityStore.isConcreteVisibleEvent($0) }
            .suffix(8)

        VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(events)) { activity in
                HStack(spacing: 5) {
                    Circle()
                        .fill(eventStatusColor(activity))
                        .frame(width: 5, height: 5)
                    Text(activity.title)
                        .font(.system(size: 10))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Spacer()
                    Text(activity.timestamp.formatted(date: .omitted, time: .standard))
                        .font(.system(size: 8, design: .monospaced))
                        .foregroundStyle(.quaternary)
                }
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Detail View

    private func detailView(for card: SwarmLiveCardState) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    // Back button
                    Button {
                        withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
                            selectedSwarmId = nil
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 9, weight: .semibold))
                            Text("All Subagents")
                                .font(.system(size: 11, weight: .medium))
                        }
                        .foregroundStyle(swarmColor)
                    }
                    .buttonStyle(.plain)

                    // Card header
                    detailHeader(card)

                    // Current step detail
                    if !card.currentDetail.isEmpty {
                        Text(card.currentDetail)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color(nsColor: .controlBackgroundColor).opacity(0.2), in: RoundedRectangle(cornerRadius: 8))
                    }

                    // Full event timeline
                    let events = card.recentEvents.filter { TaskActivityStore.isConcreteVisibleEvent($0) }
                    if !events.isEmpty {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                Text("Events")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text("\(events.count)")
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundStyle(.tertiary)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 1)
                                    .background(Color.primary.opacity(0.06), in: Capsule())
                            }

                            LazyVStack(alignment: .leading, spacing: 2) {
                                ForEach(events) { activity in
                                    detailEventRow(activity)
                                        .id("detail-event-\(activity.id)")
                                }
                            }
                        }
                    }

                    // Summary
                    if let summary = card.summary {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Summary")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.secondary)
                            Text(summary)
                                .font(.system(size: 11))
                                .foregroundStyle(.primary)
                        }
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(nsColor: .controlBackgroundColor).opacity(0.2), in: RoundedRectangle(cornerRadius: 8))
                    }
                }
                .padding(14)
            }
            .onChange(of: card.recentEvents.count) { _, _ in
                if isFollowingLive, let last = card.recentEvents.last {
                    withAnimation(.easeOut(duration: 0.2)) {
                        proxy.scrollTo("detail-event-\(last.id)", anchor: .bottom)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Detail Header

    private func detailHeader(_ card: SwarmLiveCardState) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                if card.status == .running {
                    Circle()
                        .fill(swarmColor)
                        .frame(width: 8, height: 8)
                        .modifier(PulseModifier())
                } else {
                    Circle()
                        .fill(cardStatusColor(card))
                        .frame(width: 8, height: 8)
                }

                Text(card.swarmId)
                    .font(.system(size: 13, weight: .bold, design: .monospaced))

                Text(card.status.rawValue)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(cardStatusColor(card))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(cardStatusColor(card).opacity(0.12), in: Capsule())

                Spacer()

                if card.activeOpsCount > 0 {
                    Text("\(card.activeOpsCount) ops")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(.tertiary)
                }
                if card.errorCount > 0 {
                    Text("\(card.errorCount) errors")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(DesignSystem.Colors.error)
                }
            }

            Text(card.currentStepTitle)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)

            if let started = card.startedAt {
                HStack(spacing: 12) {
                    Text("Started \(started.formatted(date: .omitted, time: .standard))")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                    if let completed = card.completedAt {
                        Text("Completed \(completed.formatted(date: .omitted, time: .standard))")
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                    }
                }
            }
        }
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.2), in: RoundedRectangle(cornerRadius: 10))
    }

    // MARK: - Detail Event Row

    @ViewBuilder
    private func detailEventRow(_ activity: TaskActivity) -> some View {
        let isExpanded = expandedEventIds.contains(activity.id)

        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Circle()
                    .fill(eventStatusColor(activity))
                    .frame(width: 6, height: 6)
                Text(activity.title)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(isExpanded ? nil : 2)
                Spacer()
                Text(activity.timestamp.formatted(date: .omitted, time: .standard))
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }

            if let detail = activity.detail, !detail.isEmpty {
                Text(detail)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(isExpanded ? nil : 2)
            }

            if let command = activity.payload["command"], !command.isEmpty {
                Text("$ \(command)")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(isExpanded ? nil : 2)
            } else if let path = activity.payload["path"] ?? activity.payload["file"], !path.isEmpty {
                Text(path)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            // Expandable raw output
            if hasRawDetail(activity) {
                Button(isExpanded ? "Hide details" : "Show details") {
                    if isExpanded {
                        expandedEventIds.remove(activity.id)
                    } else {
                        expandedEventIds.insert(activity.id)
                    }
                }
                .buttonStyle(.plain)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
            }

            if isExpanded {
                let raw = rawDetail(for: activity)
                if !raw.isEmpty {
                    Text(raw)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            Color(nsColor: .controlBackgroundColor).opacity(0.35),
                            in: RoundedRectangle(cornerRadius: 8)
                        )
                        .textSelection(.enabled)
                }
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 2)
    }

    // MARK: - Bottom Bar

    private var bottomBar: some View {
        VStack(spacing: 4) {
            HStack(spacing: 8) {
                Text("\(sortedCards.count) subagents")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.tertiary)

                if isTaskRunning {
                    Text("•")
                        .foregroundStyle(.quaternary)
                    let totalOps = sortedCards.reduce(0) { $0 + $1.activeOpsCount }
                    if totalOps > 0 {
                        Text("\(totalOps) active ops")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(swarmColor)
                    }
                }

                Spacer()

                if !isFollowingLive && isTaskRunning {
                    Button("Follow Live") {
                        isFollowingLive = true
                    }
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(swarmColor)
                    .buttonStyle(.plain)
                }
            }

            // Orchestrator & Worker config
            HStack(spacing: 6) {
                orchestratorPicker
                workerPicker
                Spacer()
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    // MARK: - Orchestrator Picker

    private var orchestratorLabel: String {
        switch swarmOrchestrator {
        case "auto": return "Auto"
        case "codex": return "Codex"
        case "claude": return "Claude"
        case "gemini": return "Gemini"
        case "anthropic-api": return "Anthropic"
        case "google-api": return "Google"
        case "openrouter-api": return "OpenRouter"
        case "minimax-api": return "MiniMax"
        case "grok-api": return "Grok"
        default: return "OpenAI"
        }
    }

    private var orchestratorPicker: some View {
        Menu {
            orchButton("auto", "Auto (same as Agent)")
            Divider()
            Section("API") {
                orchButton("openai", "OpenAI API")
                orchButton("anthropic-api", "Anthropic API")
                orchButton("google-api", "Google API")
                orchButton("openrouter-api", "OpenRouter")
                orchButton("minimax-api", "MiniMax API")
                orchButton("grok-api", "Grok API")
            }
            Section("CLI") {
                orchButton("codex", "Codex CLI")
                orchButton("claude", "Claude Code")
                orchButton("gemini", "Gemini CLI")
            }
        } label: {
            HStack(spacing: 3) {
                Image(systemName: "ant.fill").font(.system(size: 8))
                Text("Orch: \(orchestratorLabel)").font(.system(size: 10))
                Image(systemName: "chevron.down").font(.system(size: 7, weight: .bold))
            }
            .foregroundStyle(.secondary)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    private func orchButton(_ id: String, _ label: String) -> some View {
        Button {
            swarmOrchestrator = id
            onSyncSwarmProvider()
        } label: {
            HStack {
                Text(label)
                if swarmOrchestrator == id { Image(systemName: "checkmark") }
            }
        }
    }

    // MARK: - Worker Picker

    private var workerPicker: some View {
        Menu {
            workerButton("auto", "Auto (same as Agent)")
            Divider()
            Section("API") {
                workerButton("openai-api", "OpenAI API")
                workerButton("anthropic-api", "Anthropic API")
                workerButton("google-api", "Google API")
                workerButton("openrouter-api", "OpenRouter")
                workerButton("minimax-api", "MiniMax API")
                workerButton("grok-api", "Grok API")
            }
            Section("CLI") {
                workerButton("codex", "Codex CLI")
                workerButton("claude", "Claude Code")
                workerButton("gemini", "Gemini CLI")
            }
        } label: {
            HStack(spacing: 3) {
                Text("Worker: \(workerLabel)")
                    .font(.system(size: 10))
                Image(systemName: "chevron.down").font(.system(size: 7, weight: .bold))
            }
            .foregroundStyle(.secondary)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    private func workerButton(_ id: String, _ label: String) -> some View {
        Button {
            swarmWorkerBackend = id
            onSyncSwarmProvider()
        } label: {
            HStack {
                Text(label)
                if swarmWorkerBackend == id { Image(systemName: "checkmark") }
            }
        }
    }

    private var workerLabel: String {
        switch swarmWorkerBackend {
        case "auto": return "Auto"
        case "claude": return "Claude"
        case "gemini": return "Gemini"
        case "openai-api", "openai": return "OpenAI"
        case "anthropic-api": return "Anthropic"
        case "google-api": return "Google"
        case "openrouter-api", "openrouter": return "OpenRouter"
        case "minimax-api": return "MiniMax"
        case "grok-api": return "Grok"
        default: return "Codex"
        }
    }

    // MARK: - Helpers

    private func cardStatusColor(_ card: SwarmLiveCardState) -> Color {
        switch card.status {
        case .running: return swarmColor
        case .failed: return DesignSystem.Colors.error
        case .completed: return DesignSystem.Colors.success
        case .idle: return .secondary
        }
    }

    private func eventStatusColor(_ activity: TaskActivity) -> Color {
        if activity.isRunning { return swarmColor }
        let t = activity.type.lowercased()
        if t.contains("failed") || t.contains("error") { return DesignSystem.Colors.error }
        return .secondary
    }

    private func stepIcon(_ step: SwarmStep) -> String {
        switch step.status {
        case .completed: return "checkmark.circle.fill"
        case .inProgress: return "arrow.right.circle.fill"
        case .pending: return "circle"
        }
    }

    private func stepColor(_ step: SwarmStep) -> Color {
        switch step.status {
        case .completed: return DesignSystem.Colors.success
        case .inProgress: return DesignSystem.Colors.warning
        case .pending: return DesignSystem.Colors.borderAccent
        }
    }

    private func hasRawDetail(_ activity: TaskActivity) -> Bool {
        !(activity.payload["output"] ?? "").isEmpty ||
        !(activity.payload["stderr"] ?? "").isEmpty ||
        !(activity.payload["cwd"] ?? "").isEmpty ||
        !(activity.payload["diffPreview"] ?? "").isEmpty
    }

    private func rawDetail(for activity: TaskActivity) -> String {
        var lines: [String] = []
        if let cwd = activity.payload["cwd"], !cwd.isEmpty {
            lines.append("cwd: \(cwd)")
        }
        if let output = activity.payload["output"], !output.isEmpty {
            lines.append(String(output.prefix(4096)))
        }
        if let stderr = activity.payload["stderr"], !stderr.isEmpty {
            lines.append("stderr:")
            lines.append(String(stderr.prefix(4096)))
        }
        if let diff = activity.payload["diffPreview"], !diff.isEmpty {
            lines.append("diff:")
            lines.append(String(diff.prefix(2048)))
        }
        return lines.joined(separator: "\n\n")
    }
}
