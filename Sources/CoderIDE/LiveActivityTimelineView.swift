import SwiftUI

private enum LiveTimelineFormatters {
    static let hms: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()
}

// MARK: - Live Activity Timeline (Cursor-style Reasoning Trace)

struct LiveActivityTimelineView: View {
    let activities: [TaskActivity]
    let maxVisible: Int

    @State private var expandedIds: Set<UUID> = []
    @State private var isCollapsed = false
    @State private var hoveredId: UUID?

    private var visibleActivities: [TaskActivity] {
        Array(activities.suffix(maxVisible))
    }

    private var groupedActivities: [ActivityGroup] {
        groupByPhase(visibleActivities)
    }

    var body: some View {
        if !visibleActivities.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                // Header
                traceHeader
                    .padding(.horizontal, 12)
                    .padding(.top, 10)
                    .padding(.bottom, 8)

                if !isCollapsed {
                    Divider().opacity(0.3)

                    // Timeline
                    ScrollView(.vertical, showsIndicators: false) {
                        LazyVStack(alignment: .leading, spacing: 2) {
                            ForEach(groupedActivities) { group in
                                groupSection(group)
                            }
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                    }
                    .frame(maxHeight: 280)
                }
            }
            .background(TraceColors.panelBackground)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(TraceColors.panelBorder, lineWidth: 0.5)
            )
        }
    }

    // MARK: - Header

    private var traceHeader: some View {
        HStack(spacing: 8) {
            Image(systemName: "brain")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(TraceColors.headerAccent)

            Text("Reasoning Trace")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)

            // Phase summary pills
            let phases = phaseSummary()
            if !phases.isEmpty {
                HStack(spacing: 4) {
                    ForEach(phases, id: \.phase) { summary in
                        PhasePill(
                            icon: phaseIcon(summary.phase),
                            count: summary.count,
                            color: phaseColor(summary.phase)
                        )
                    }
                }
            }

            Spacer()

            Text("\(visibleActivities.count)")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(.quaternary)

            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isCollapsed.toggle()
                }
            } label: {
                Image(systemName: isCollapsed ? "chevron.down" : "chevron.up")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.quaternary)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Group Section

    @ViewBuilder
    private func groupSection(_ group: ActivityGroup) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // Group header (only if multiple events)
            if group.activities.count > 1 {
                HStack(spacing: 6) {
                    Image(systemName: phaseIcon(group.phase))
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(phaseColor(group.phase))
                        .frame(width: 14)

                    Text(phaseLabel(group.phase))
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(phaseColor(group.phase).opacity(0.8))
                        .tracking(0.3)

                    Rectangle()
                        .fill(phaseColor(group.phase).opacity(0.12))
                        .frame(height: 1)

                    Text("\(group.activities.count)")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundStyle(.quaternary)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
            }

            ForEach(group.activities) { activity in
                activityRow(activity)
            }
        }
    }

    // MARK: - Activity Row

    private func activityRow(_ activity: TaskActivity) -> some View {
        let isExpanded = expandedIds.contains(activity.id)
        let isHovered = hoveredId == activity.id
        let hasExpandable = hasExpandableContent(activity)

        return VStack(alignment: .leading, spacing: 0) {
            // Main row
            HStack(alignment: .top, spacing: 8) {
                // Timeline connector
                VStack(spacing: 0) {
                    Circle()
                        .fill(activityDotColor(activity))
                        .frame(width: 6, height: 6)
                        .padding(.top, 6)
                }
                .frame(width: 14)

                // Content
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Image(systemName: activityIcon(activity))
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(activityIconColor(activity))

                        Text(activity.title)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.primary)
                            .lineLimit(isExpanded ? nil : 1)

                        Spacer()

                        Text(timestamp(activity.timestamp))
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(.quaternary)

                        if hasExpandable {
                            Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundStyle(.quaternary)
                        }
                    }

                    // Detail line (compact)
                    if let detail = activity.detail, !detail.isEmpty, !isExpanded {
                        Text(detail)
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }

                    // Command preview
                    if let command = activity.payload["command"], !command.isEmpty, !isExpanded {
                        HStack(spacing: 4) {
                            Text("$")
                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                                .foregroundStyle(DesignSystem.Colors.warning.opacity(0.5))
                            Text(command)
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }

                    // File path
                    if let path = activity.payload["path"] ?? activity.payload["file"],
                        !path.isEmpty, !isExpanded
                    {
                        HStack(spacing: 4) {
                            Image(systemName: "doc.text")
                                .font(.system(size: 8))
                                .foregroundStyle(.quaternary)
                            Text(path)
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(isHovered ? TraceColors.rowHover : Color.clear)
            )
            .contentShape(Rectangle())
            .onTapGesture {
                guard hasExpandable else { return }
                withAnimation(.easeInOut(duration: 0.15)) {
                    if isExpanded {
                        expandedIds.remove(activity.id)
                    } else {
                        expandedIds.insert(activity.id)
                    }
                }
            }
            .onHover { hovering in
                hoveredId = hovering ? activity.id : nil
            }

            // Expanded content
            if isExpanded {
                expandedContent(activity)
                    .padding(.leading, 22)
                    .padding(.trailing, 8)
                    .padding(.bottom, 6)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    // MARK: - Expanded Content

    @ViewBuilder
    private func expandedContent(_ activity: TaskActivity) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if let detail = activity.detail, !detail.isEmpty {
                Text(detail)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .lineSpacing(2)
                    .textSelection(.enabled)
            }

            if let command = activity.payload["command"], !command.isEmpty {
                codeSnippet("$ \(command)")
            }

            if let output = activity.payload["output"], !output.isEmpty {
                codeSnippet(String(output.prefix(3000)))
            }

            if let stderr = activity.payload["stderr"], !stderr.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 4) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 9))
                            .foregroundStyle(DesignSystem.Colors.error)
                        Text("stderr")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(DesignSystem.Colors.error)
                    }
                    codeSnippet(String(stderr.prefix(2000)), isError: true)
                }
            }

            if let cwd = activity.payload["cwd"], !cwd.isEmpty {
                HStack(spacing: 4) {
                    Text("cwd:")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.tertiary)
                    Text(cwd)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            if let path = activity.payload["path"] ?? activity.payload["file"], !path.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "doc.text.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(DesignSystem.Colors.agentColor)
                    Text(path)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)

                    if let added = activity.payload["linesAdded"]
                        ?? activity.payload["lines_added"],
                        let removed = activity.payload["linesRemoved"]
                            ?? activity.payload["lines_removed"]
                    {
                        Spacer()
                        Text("+\(added)")
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .foregroundStyle(Color.green)
                        Text("-\(removed)")
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .foregroundStyle(Color.red)
                    }
                }
            }
        }
    }

    private func codeSnippet(_ text: String, isError: Bool = false) -> some View {
        ScrollView(.vertical, showsIndicators: true) {
            Text(text)
                .font(.system(size: 10.5, design: .monospaced))
                .foregroundStyle(isError ? DesignSystem.Colors.error.opacity(0.8) : Color.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
        }
        .frame(maxHeight: 160)
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(
                    isError ? DesignSystem.Colors.error.opacity(0.04) : TraceColors.codeBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(
                    isError ? DesignSystem.Colors.error.opacity(0.12) : TraceColors.codeBorder,
                    lineWidth: 0.5
                )
        )
    }

    // MARK: - Helpers

    private func hasExpandableContent(_ activity: TaskActivity) -> Bool {
        !(activity.payload["output"] ?? "").isEmpty
            || !(activity.payload["stderr"] ?? "").isEmpty
            || !(activity.payload["cwd"] ?? "").isEmpty
            || !(activity.payload["command"] ?? "").isEmpty
            || !(activity.detail ?? "").isEmpty
    }

    private func activityIcon(_ activity: TaskActivity) -> String {
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
        case "todo_write", "todo_read": return "checklist"
        default: return "circle.fill"
        }
    }

    private func activityIconColor(_ activity: TaskActivity) -> Color {
        switch activity.phase {
        case .executing: return DesignSystem.Colors.warning
        case .editing: return DesignSystem.Colors.agentColor
        case .searching: return DesignSystem.Colors.info
        case .planning: return DesignSystem.Colors.planColor
        case .thinking: return Color.secondary.opacity(0.6)
        }
    }

    private func activityDotColor(_ activity: TaskActivity) -> Color {
        if activity.isRunning { return DesignSystem.Colors.warning }
        let t = activity.type.lowercased()
        if t.contains("failed") || t.contains("error") { return DesignSystem.Colors.error }
        if t.contains("completed") || t.contains("resumed") { return DesignSystem.Colors.success }
        return Color.secondary.opacity(0.4)
    }

    private func timestamp(_ date: Date) -> String {
        LiveTimelineFormatters.hms.string(from: date)
    }

    // MARK: - Phase Helpers

    private func phaseIcon(_ phase: ActivityPhase) -> String {
        switch phase {
        case .thinking: return "brain"
        case .editing: return "pencil"
        case .executing: return "terminal"
        case .searching: return "magnifyingglass"
        case .planning: return "list.bullet.rectangle"
        }
    }

    private func phaseColor(_ phase: ActivityPhase) -> Color {
        switch phase {
        case .thinking: return Color.purple
        case .editing: return DesignSystem.Colors.agentColor
        case .executing: return DesignSystem.Colors.warning
        case .searching: return DesignSystem.Colors.info
        case .planning: return DesignSystem.Colors.planColor
        }
    }

    private func phaseLabel(_ phase: ActivityPhase) -> String {
        switch phase {
        case .thinking: return "THINKING"
        case .editing: return "EDITING"
        case .executing: return "EXECUTING"
        case .searching: return "SEARCHING"
        case .planning: return "PLANNING"
        }
    }

    // MARK: - Grouping

    private struct PhaseSummary {
        let phase: ActivityPhase
        let count: Int
    }

    private func phaseSummary() -> [PhaseSummary] {
        var counts: [ActivityPhase: Int] = [:]
        for activity in visibleActivities {
            counts[activity.phase, default: 0] += 1
        }
        return counts.map { PhaseSummary(phase: $0.key, count: $0.value) }
            .sorted { $0.count > $1.count }
    }

    private func groupByPhase(_ activities: [TaskActivity]) -> [ActivityGroup] {
        guard !activities.isEmpty else { return [] }

        var groups: [ActivityGroup] = []
        var currentPhase = activities[0].phase
        var currentBatch: [TaskActivity] = []

        for activity in activities {
            if activity.phase == currentPhase {
                currentBatch.append(activity)
            } else {
                if !currentBatch.isEmpty {
                    groups.append(
                        ActivityGroup(
                            phase: currentPhase,
                            activities: currentBatch
                        ))
                }
                currentPhase = activity.phase
                currentBatch = [activity]
            }
        }

        if !currentBatch.isEmpty {
            groups.append(
                ActivityGroup(
                    phase: currentPhase,
                    activities: currentBatch
                ))
        }

        return groups
    }
}

// MARK: - Activity Group

private struct ActivityGroup: Identifiable {
    let phase: ActivityPhase
    let activities: [TaskActivity]

    var id: String {
        "\(phase.rawValue)-\(activities.first?.id.uuidString ?? UUID().uuidString)"
    }
}

// MARK: - Phase Pill

private struct PhasePill: View {
    let icon: String
    let count: Int
    let color: Color

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: icon)
                .font(.system(size: 7, weight: .bold))
            Text("\(count)")
                .font(.system(size: 9, weight: .bold, design: .monospaced))
        }
        .foregroundStyle(color.opacity(0.7))
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(color.opacity(0.08), in: Capsule())
    }
}

// MARK: - Colors

private enum TraceColors {
    static let panelBackground = Color(nsColor: .controlBackgroundColor).opacity(0.35)
    static let panelBorder = Color(nsColor: .separatorColor).opacity(0.4)
    static let rowHover = Color.primary.opacity(0.03)
    static let codeBackground = Color.black.opacity(0.08)
    static let codeBorder = Color(nsColor: .separatorColor).opacity(0.25)
    static let headerAccent = Color.purple.opacity(0.7)
}
