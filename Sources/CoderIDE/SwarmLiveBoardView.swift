import SwiftUI

// MARK: - Swarm Live Board (Cursor-style Dashboard)

struct SwarmLiveBoardView: View {
    let activities: [TaskActivity]
    let isTaskRunning: Bool
    let maxEventsPerLane: Int

    @State private var expandedLaneIds: Set<String> = []
    @State private var expandedEventIds: Set<UUID> = []
    @State private var isFollowingLive = true
    @State private var hoveredLaneId: String?

    init(activities: [TaskActivity], isTaskRunning: Bool = false, maxEventsPerLane: Int = 120) {
        self.activities = activities
        self.isTaskRunning = isTaskRunning
        self.maxEventsPerLane = max(20, maxEventsPerLane)
    }

    private var laneStates: [SwarmLaneState] {
        TaskActivityStore.laneStates(from: activities, limitPerLane: maxEventsPerLane)
    }

    private var completedCount: Int {
        laneStates.filter { $0.status == .completed }.count
    }

    private var totalCount: Int {
        laneStates.count
    }

    private var hasErrors: Bool {
        laneStates.contains { $0.errorsCount > 0 }
    }

    var body: some View {
        if !laneStates.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                dashboardHeader
                    .padding(.horizontal, 14)
                    .padding(.top, 12)
                    .padding(.bottom, 8)

                Divider()
                    .opacity(0.4)

                ScrollViewReader { proxy in
                    ScrollView(.vertical, showsIndicators: false) {
                        LazyVStack(alignment: .leading, spacing: 6) {
                            ForEach(laneStates) { lane in
                                SwarmAgentCard(
                                    lane: lane,
                                    isExpanded: expandedLaneIds.contains(lane.id),
                                    isHovered: hoveredLaneId == lane.id,
                                    expandedEventIds: $expandedEventIds,
                                    onToggle: { toggleLane(lane.id) },
                                    onHover: { hovering in
                                        hoveredLaneId = hovering ? lane.id : nil
                                    }
                                )
                                .id("lane-\(lane.id)")
                            }
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                    }
                    .simultaneousGesture(
                        DragGesture(minimumDistance: 2).onChanged { _ in
                            isFollowingLive = false
                        }
                    )
                    .onChange(of: activities.count) { _, _ in
                        guard isFollowingLive, let last = laneStates.last?.id else { return }
                        withAnimation(.easeOut(duration: 0.2)) {
                            proxy.scrollTo("lane-\(last)", anchor: .bottom)
                        }
                    }
                }

                if !isFollowingLive && isTaskRunning {
                    jumpToLiveButton
                        .padding(.horizontal, 14)
                        .padding(.bottom, 8)
                }
            }
            .background(SwarmColors.panelBackground)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(SwarmColors.panelBorder, lineWidth: 0.5)
            )
        }
    }

    // MARK: - Dashboard Header

    private var dashboardHeader: some View {
        HStack(spacing: 10) {
            // Status indicator
            HStack(spacing: 6) {
                SwarmStatusDot(isRunning: isTaskRunning, hasErrors: hasErrors)

                Text("Swarm")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.primary)
            }

            // Progress pill
            if totalCount > 0 {
                HStack(spacing: 4) {
                    Text("\(completedCount)/\(totalCount)")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(SwarmColors.accentText)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(SwarmColors.accentBackground, in: Capsule())
            }

            Spacer()

            if isTaskRunning {
                LivePulse()
            }

            // Collapse/Expand all
            Button {
                if expandedLaneIds.count == laneStates.count {
                    expandedLaneIds.removeAll()
                } else {
                    expandedLaneIds = Set(laneStates.map(\.id))
                }
            } label: {
                Image(
                    systemName: expandedLaneIds.count == laneStates.count
                        ? "rectangle.compress.vertical"
                        : "rectangle.expand.vertical"
                )
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)
            .help(expandedLaneIds.count == laneStates.count ? "Collapse all" : "Expand all")
        }
    }

    // MARK: - Jump to Live

    private var jumpToLiveButton: some View {
        Button {
            isFollowingLive = true
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "arrow.down")
                    .font(.system(size: 9, weight: .bold))
                Text("Follow live")
                    .font(.system(size: 10, weight: .semibold))
            }
            .foregroundStyle(SwarmColors.accentText)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .frame(maxWidth: .infinity)
            .background(SwarmColors.accentBackground, in: Capsule())
        }
        .buttonStyle(.plain)
    }

    private func toggleLane(_ id: String) {
        withAnimation(.easeInOut(duration: 0.2)) {
            if expandedLaneIds.contains(id) {
                expandedLaneIds.remove(id)
            } else {
                expandedLaneIds.insert(id)
            }
        }
    }
}

// MARK: - Agent Card

private struct SwarmAgentCard: View {
    let lane: SwarmLaneState
    let isExpanded: Bool
    let isHovered: Bool
    @Binding var expandedEventIds: Set<UUID>
    let onToggle: () -> Void
    let onHover: (Bool) -> Void

    private let collapsedEventCount = 3
    private let maxRawChars = 4096

    private var visibleEvents: [TaskActivity] {
        isExpanded ? lane.events : Array(lane.events.suffix(collapsedEventCount))
    }

    private var statusColor: Color {
        switch lane.status {
        case .running: return SwarmColors.running
        case .failed: return SwarmColors.error
        case .completed: return SwarmColors.success
        case .idle: return SwarmColors.idle
        }
    }

    private var roleIcon: String {
        SwarmRoleIcons.icon(for: lane.swarmId)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Card header
            Button(action: onToggle) {
                cardHeader
            }
            .buttonStyle(.plain)

            if isExpanded {
                Divider()
                    .padding(.horizontal, 12)
                    .opacity(0.3)

                // Events timeline
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(visibleEvents) { activity in
                        SwarmEventRow(
                            activity: activity,
                            isExpanded: expandedEventIds.contains(activity.id),
                            maxRawChars: maxRawChars,
                            onToggle: {
                                if expandedEventIds.contains(activity.id) {
                                    expandedEventIds.remove(activity.id)
                                } else {
                                    expandedEventIds.insert(activity.id)
                                }
                            }
                        )
                    }

                    if lane.events.count > collapsedEventCount && !isExpanded {
                        Text("+ \(lane.events.count - collapsedEventCount) more events")
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 4)
                    }
                }
                .padding(.vertical, 6)
            }
        }
        .background(cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(
                    isHovered ? statusColor.opacity(0.35) : SwarmColors.cardBorder,
                    lineWidth: isHovered ? 1 : 0.5
                )
        )
        .shadow(color: isHovered ? statusColor.opacity(0.08) : .clear, radius: 8, y: 2)
        .animation(.easeOut(duration: 0.15), value: isHovered)
        .onHover { hovering in onHover(hovering) }
    }

    private var cardHeader: some View {
        HStack(spacing: 8) {
            // Role icon with status ring
            ZStack {
                Circle()
                    .fill(statusColor.opacity(0.12))
                    .frame(width: 28, height: 28)

                Image(systemName: roleIcon)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(statusColor)
            }

            // Agent info
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(SwarmRoleIcons.displayName(for: lane.swarmId))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.primary)

                    SwarmStatusBadge(status: lane.status)
                }

                Text(lane.currentActivityTitle)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            // Metrics
            HStack(spacing: 8) {
                if lane.activeOpsCount > 0 {
                    MetricPill(
                        icon: "bolt.fill",
                        value: "\(lane.activeOpsCount)",
                        color: SwarmColors.running
                    )
                }

                if lane.errorsCount > 0 {
                    MetricPill(
                        icon: "exclamationmark.triangle.fill",
                        value: "\(lane.errorsCount)",
                        color: SwarmColors.error
                    )
                }

                if let last = lane.lastEventAt {
                    Text(last.formatted(date: .omitted, time: .standard))
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(.quaternary)
                }
            }

            // Chevron
            Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.quaternary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var cardBackground: some View {
        if lane.status == .running {
            SwarmColors.cardBackgroundActive
        } else {
            SwarmColors.cardBackground
        }
    }
}

// MARK: - Event Row

private struct SwarmEventRow: View {
    let activity: TaskActivity
    let isExpanded: Bool
    let maxRawChars: Int
    let onToggle: () -> Void

    private var eventIcon: String {
        switch activity.type {
        case "edit", "file_change": return "doc.text.fill"
        case "read_batch_started", "read_batch_completed": return "doc.on.doc"
        case "bash", "command_execution": return "terminal.fill"
        case "search", "web_search", "instant_grep",
            "web_search_started", "web_search_completed", "web_search_failed":
            return "magnifyingglass"
        case "mcp_tool_call": return "wrench.fill"
        case "process_paused": return "pause.circle.fill"
        case "process_resumed": return "play.circle.fill"
        case "plan_step_update": return "list.bullet"
        case "agent": return "cpu"
        default: return "circle.fill"
        }
    }

    private var eventColor: Color {
        if activity.isRunning { return SwarmColors.running }
        let t = activity.type.lowercased()
        if t.contains("failed") || t.contains("error") { return SwarmColors.error }
        if t.contains("completed") || t.contains("resumed") { return SwarmColors.success }
        return .secondary
    }

    private var hasExpandableContent: Bool {
        !(activity.payload["output"] ?? "").isEmpty
            || !(activity.payload["stderr"] ?? "").isEmpty
            || !(activity.payload["cwd"] ?? "").isEmpty
            || !(activity.payload["diffPreview"] ?? "").isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .top, spacing: 8) {
                // Timeline dot
                VStack(spacing: 0) {
                    Circle()
                        .fill(eventColor.opacity(0.8))
                        .frame(width: 5, height: 5)
                        .padding(.top, 5)
                }
                .frame(width: 12)

                // Content
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Image(systemName: eventIcon)
                            .font(.system(size: 9))
                            .foregroundStyle(eventColor.opacity(0.8))

                        Text(activity.title)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.primary)
                            .lineLimit(isExpanded ? nil : 1)

                        Spacer()

                        Text(activity.timestamp.formatted(date: .omitted, time: .standard))
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(.quaternary)
                    }

                    if let detail = activity.detail, !detail.isEmpty {
                        Text(detail)
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                            .lineLimit(isExpanded ? nil : 1)
                    }

                    if let command = activity.payload["command"], !command.isEmpty {
                        HStack(spacing: 4) {
                            Text("$")
                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                                .foregroundStyle(SwarmColors.running.opacity(0.6))
                            Text(command)
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .lineLimit(isExpanded ? nil : 1)
                        }
                    } else if let path = activity.payload["path"] ?? activity.payload["file"],
                        !path.isEmpty
                    {
                        HStack(spacing: 4) {
                            Text(path)
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                            if let added = activity.payload["linesAdded"]
                                ?? activity.payload["lines_added"],
                                let removed = activity.payload["linesRemoved"]
                                    ?? activity.payload["lines_removed"]
                            {
                                Text("+\(added)")
                                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                                    .foregroundStyle(SwarmColors.success)
                                Text("-\(removed)")
                                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                                    .foregroundStyle(SwarmColors.error)
                            }
                        }
                    }

                    // Expandable raw content
                    if hasExpandableContent {
                        Button(action: onToggle) {
                            HStack(spacing: 3) {
                                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                                    .font(.system(size: 8, weight: .bold))
                                Text(isExpanded ? "Hide details" : "Show details")
                                    .font(.system(size: 10, weight: .medium))
                            }
                            .foregroundStyle(SwarmColors.accentText)
                        }
                        .buttonStyle(.plain)
                        .padding(.top, 2)
                    }

                    if isExpanded {
                        expandedContent
                    }
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var expandedContent: some View {
        VStack(alignment: .leading, spacing: 6) {
            let raw = rawDetail()
            if !raw.isEmpty {
                ScrollView(.vertical, showsIndicators: true) {
                    Text(raw)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
                .frame(maxHeight: 200)
                .padding(8)
                .background(
                    SwarmColors.codeBackground,
                    in: RoundedRectangle(cornerRadius: 6, style: .continuous)
                )
            }

            if let diff = activity.payload["diffPreview"], !diff.isEmpty {
                ScrollView(.vertical, showsIndicators: true) {
                    Text(String(diff.prefix(maxRawChars)))
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
                .frame(maxHeight: 200)
                .padding(8)
                .background(
                    SwarmColors.codeBackground,
                    in: RoundedRectangle(cornerRadius: 6, style: .continuous)
                )
            }
        }
        .padding(.top, 4)
    }

    private func rawDetail() -> String {
        var lines: [String] = []
        if let cwd = activity.payload["cwd"], !cwd.isEmpty {
            lines.append("cwd: \(cwd)")
        }
        if let output = activity.payload["output"], !output.isEmpty {
            lines.append(String(output.prefix(maxRawChars)))
        }
        if let stderr = activity.payload["stderr"], !stderr.isEmpty {
            lines.append("stderr:")
            lines.append(String(stderr.prefix(maxRawChars)))
        }
        return lines.joined(separator: "\n\n")
    }
}

// MARK: - Status Badge

private struct SwarmStatusBadge: View {
    let status: SwarmLaneStatus

    private var label: String {
        switch status {
        case .running: return "Running"
        case .failed: return "Failed"
        case .completed: return "Done"
        case .idle: return "Idle"
        }
    }

    private var color: Color {
        switch status {
        case .running: return SwarmColors.running
        case .failed: return SwarmColors.error
        case .completed: return SwarmColors.success
        case .idle: return SwarmColors.idle
        }
    }

    var body: some View {
        Text(label)
            .font(.system(size: 9, weight: .bold, design: .monospaced))
            .foregroundStyle(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.1), in: Capsule())
    }
}

// MARK: - Metric Pill

private struct MetricPill: View {
    let icon: String
    let value: String
    let color: Color

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: icon)
                .font(.system(size: 8))
            Text(value)
                .font(.system(size: 9, weight: .bold, design: .monospaced))
        }
        .foregroundStyle(color)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(color.opacity(0.08), in: Capsule())
    }
}

// MARK: - Status Dot (animated)

private struct SwarmStatusDot: View {
    let isRunning: Bool
    let hasErrors: Bool
    @State private var isPulsing = false

    private var color: Color {
        if hasErrors { return SwarmColors.error }
        if isRunning { return SwarmColors.running }
        return SwarmColors.success
    }

    var body: some View {
        ZStack {
            if isRunning {
                Circle()
                    .fill(color.opacity(0.3))
                    .frame(width: 10, height: 10)
                    .scaleEffect(isPulsing ? 1.6 : 1.0)
                    .opacity(isPulsing ? 0.0 : 0.6)
                    .animation(
                        .easeInOut(duration: 1.2).repeatForever(autoreverses: false),
                        value: isPulsing
                    )
                    .onAppear { isPulsing = true }
            }
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
        }
    }
}

// MARK: - Live Pulse indicator

private struct LivePulse: View {
    @State private var isAnimating = false

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(SwarmColors.running)
                .frame(width: 5, height: 5)
                .opacity(isAnimating ? 1.0 : 0.3)

            Text("LIVE")
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundStyle(SwarmColors.running)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                isAnimating = true
            }
        }
    }
}

// MARK: - Role Icons & Names

enum SwarmRoleIcons {
    static func icon(for swarmId: String) -> String {
        switch swarmId.lowercased() {
        case "planner": return "map.fill"
        case "coder": return "chevron.left.forwardslash.chevron.right"
        case "debugger": return "ladybug.fill"
        case "reviewer": return "eye.fill"
        case "docwriter": return "doc.text.fill"
        case "securityauditor": return "lock.shield.fill"
        case "testwriter": return "checkmark.diamond.fill"
        case "orchestrator": return "cpu"
        default: return "ant.fill"
        }
    }

    static func displayName(for swarmId: String) -> String {
        switch swarmId.lowercased() {
        case "planner": return "Planner"
        case "coder": return "Coder"
        case "debugger": return "Debugger"
        case "reviewer": return "Reviewer"
        case "docwriter": return "Doc Writer"
        case "securityauditor": return "Security Auditor"
        case "testwriter": return "Test Writer"
        case "orchestrator": return "Orchestrator"
        default: return swarmId.capitalized
        }
    }
}

// MARK: - Color System (Cursor-inspired)

enum SwarmColors {
    // Panel
    static let panelBackground = Color(nsColor: .controlBackgroundColor).opacity(0.4)
    static let panelBorder = Color(nsColor: .separatorColor).opacity(0.5)

    // Cards
    static let cardBackground = Color(nsColor: .controlBackgroundColor).opacity(0.3)
    static let cardBackgroundActive = Color(nsColor: .controlBackgroundColor).opacity(0.5)
    static let cardBorder = Color(nsColor: .separatorColor).opacity(0.3)

    // Code blocks
    static let codeBackground = Color.black.opacity(0.15)

    // Semantic
    static let running = Color.orange
    static let success = Color.green
    static let error = Color.red
    static let idle = Color.gray

    // Accent (used for interactive elements)
    static let accentText = Color.accentColor
    static let accentBackground = Color.accentColor.opacity(0.1)
}
