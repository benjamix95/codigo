import CoderEngine
import SwiftUI

/// Vista inline della timeline attività durante lo streaming dell'assistant.
/// Mostra la lista di step operativi (comandi, modifiche file, web search, ecc.)
/// che l'LLM invoca tramite lo stream. Ogni riga è espandibile per vedere i dettagli.
struct InlineActivityFeedView: View {
    let activities: [TaskActivity]
    let modeColor: Color
    let statusFromLLMOrActivity: String?
    let maxVisible: Int

    init(
        activities: [TaskActivity],
        modeColor: Color,
        statusFromLLMOrActivity: String? = nil,
        maxVisible: Int = 20
    ) {
        self.activities = activities
        self.modeColor = modeColor
        self.statusFromLLMOrActivity = statusFromLLMOrActivity
        self.maxVisible = maxVisible
    }

    @State private var expandedActivityIds: Set<UUID> = []

    private var visibleActivities: [TaskActivity] {
        activities
            .filter { TaskActivityStore.isConcreteVisibleEvent($0) }
            .suffix(maxVisible)
            .map { $0 }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if visibleActivities.isEmpty {
                statusPlaceholder
            } else {
                ForEach(visibleActivities) { activity in
                    let isExpanded = expandedActivityIds.contains(activity.id)
                    activityRow(activity, isExpanded: isExpanded)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                if isExpanded {
                                    expandedActivityIds.remove(activity.id)
                                } else {
                                    expandedActivityIds.insert(activity.id)
                                }
                            }
                        }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(maxWidth: 760, alignment: .leading)
    }

    // MARK: - Status Placeholder

    private var statusPlaceholder: some View {
        HStack(spacing: 8) {
            StreamingDots(color: modeColor)
            if let status = statusFromLLMOrActivity, !status.isEmpty {
                Text(status)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .overlay {
            if statusFromLLMOrActivity != nil, !(statusFromLLMOrActivity ?? "").isEmpty {
                ActivityShimmerTrail()
                    .allowsHitTesting(false)
            }
        }
    }

    // MARK: - Activity Row (Expandable)

    private func activityRow(_ activity: TaskActivity, isExpanded: Bool) -> some View {
        let isRunning = activity.isRunning
        let phaseColor = phaseAccentColor(for: activity)

        return VStack(alignment: .leading, spacing: 0) {
            // Header row
            HStack(alignment: .top, spacing: 8) {
                // Phase-colored icon
                Image(systemName: icon(for: activity))
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(isRunning ? phaseColor : DesignSystem.Colors.textTertiary)
                    .frame(width: 16, alignment: .center)

                VStack(alignment: .leading, spacing: 2) {
                    Text(activity.title)
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(.primary)
                        .lineLimit(isExpanded ? 4 : 1)
                    if !isExpanded, let detail = detailText(for: activity), !detail.isEmpty {
                        Text(detail)
                            .font(.system(size: 10.5))
                            .foregroundStyle(DesignSystem.Colors.textSecondary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
                HStack(spacing: 6) {
                    statusBadge(for: activity)
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(DesignSystem.Colors.textQuaternary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            // Expanded detail section
            if isExpanded {
                expandedDetail(for: activity, phaseColor: phaseColor)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isExpanded
                      ? DesignSystem.Colors.backgroundSecondary
                      : DesignSystem.Colors.backgroundSecondary.opacity(0.4))
        )
        .overlay(alignment: .leading) {
            if isRunning {
                RoundedRectangle(cornerRadius: 8)
                    .fill(phaseColor)
                    .frame(width: 2)
            }
        }
        .overlay {
            if isRunning, !isExpanded {
                ActivityShimmerTrail()
                    .allowsHitTesting(false)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
        }
        .frame(maxWidth: 760)
    }

    // MARK: - Expanded Detail

    private func expandedDetail(for activity: TaskActivity, phaseColor: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            // Show all available detail fields
            if let command = activity.payload["command"]?.trimmingCharacters(in: .whitespacesAndNewlines),
               !command.isEmpty
            {
                detailField(label: "Command", value: command, icon: "terminal", color: phaseColor)
            }
            if let path = activity.payload["path"]?.trimmingCharacters(in: .whitespacesAndNewlines),
               !path.isEmpty, path != activity.title
            {
                detailField(label: "Path", value: path, icon: "folder", color: phaseColor)
            }
            if let query = activity.payload["query"]?.trimmingCharacters(in: .whitespacesAndNewlines),
               !query.isEmpty
            {
                detailField(label: "Query", value: query, icon: "magnifyingglass", color: phaseColor)
            }
            if let tool = activity.payload["tool"]?.trimmingCharacters(in: .whitespacesAndNewlines),
               !tool.isEmpty, tool != activity.title
            {
                detailField(label: "Tool", value: tool, icon: "wrench", color: phaseColor)
            }
            if let output = activity.payload["output"]?.trimmingCharacters(in: .whitespacesAndNewlines),
               !output.isEmpty
            {
                detailField(label: "Output", value: String(output.prefix(500)), icon: "text.alignleft", color: phaseColor)
            }
            if let detail = activity.detail?.trimmingCharacters(in: .whitespacesAndNewlines),
               !detail.isEmpty, detail != activity.title
            {
                detailField(label: "Detail", value: detail, icon: "info.circle", color: phaseColor)
            }
            // Swarm / sub-agent info
            if let swarmId = activity.payload["swarm_id"]?.trimmingCharacters(in: .whitespacesAndNewlines),
               !swarmId.isEmpty
            {
                detailField(label: "Sub-agent", value: swarmId, icon: "person.2", color: DesignSystem.Colors.swarmColor)
            }
            // Status info
            if let status = activity.payload["status"]?.trimmingCharacters(in: .whitespacesAndNewlines),
               !status.isEmpty
            {
                HStack(spacing: 6) {
                    Circle()
                        .fill(statusDotColor(status))
                        .frame(width: 6, height: 6)
                    Text(status.capitalized)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(DesignSystem.Colors.textSecondary)
                }
                .padding(.top, 2)
            }
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 10)
        .padding(.leading, 24) // Align with text after icon
    }

    private func detailField(label: String, value: String, icon: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(color.opacity(0.7))
                Text(label)
                    .font(.system(size: 9.5, weight: .semibold))
                    .foregroundStyle(DesignSystem.Colors.textTertiary)
            }
            Text(value)
                .font(.system(size: 10.5, design: .monospaced))
                .foregroundStyle(DesignSystem.Colors.textSecondary)
                .lineLimit(6)
                .textSelection(.enabled)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(DesignSystem.Colors.backgroundTertiary.opacity(0.6))
                )
        }
    }

    // MARK: - Detail Text (collapsed summary)

    private func detailText(for activity: TaskActivity) -> String? {
        let candidates = [
            activity.detail,
            activity.payload["command"],
            activity.payload["path"],
            activity.payload["query"],
            activity.payload["output"],
            activity.payload["tool"],
        ]
        for value in candidates {
            let text = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !text.isEmpty, text != activity.title {
                return String(text.prefix(180))
            }
        }
        return nil
    }

    // MARK: - Status Badge

    private func statusBadge(for activity: TaskActivity) -> some View {
        let status = statusText(for: activity)
        let color = statusColor(for: activity)
        return Text(status.uppercased())
            .font(.system(size: 8, weight: .bold, design: .monospaced))
            .foregroundStyle(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.12), in: Capsule())
    }

    private func statusText(for activity: TaskActivity) -> String {
        let raw = (activity.payload["status"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !raw.isEmpty {
            switch raw {
            case "started", "in_progress", "running": return "running"
            case "completed", "done", "success": return "done"
            case "failed", "error": return "failed"
            default: return raw
            }
        }
        return activity.isRunning ? "running" : "done"
    }

    private func statusColor(for activity: TaskActivity) -> Color {
        switch statusText(for: activity) {
        case "running": return modeColor
        case "done": return DesignSystem.Colors.success
        case "failed": return DesignSystem.Colors.error
        default: return DesignSystem.Colors.textTertiary
        }
    }

    private func statusDotColor(_ status: String) -> Color {
        let lower = status.lowercased()
        if lower.contains("running") || lower.contains("started") || lower.contains("in_progress") {
            return modeColor
        }
        if lower.contains("done") || lower.contains("completed") || lower.contains("success") {
            return DesignSystem.Colors.success
        }
        if lower.contains("failed") || lower.contains("error") {
            return DesignSystem.Colors.error
        }
        return DesignSystem.Colors.textTertiary
    }

    // MARK: - Phase Accent Color

    /// Returns a color based on the activity's phase/type for visual differentiation.
    private func phaseAccentColor(for activity: TaskActivity) -> Color {
        switch activity.phase {
        case .executing: return DesignSystem.Colors.warning
        case .editing: return DesignSystem.Colors.info
        case .searching: return DesignSystem.Colors.swarmColor
        case .planning: return DesignSystem.Colors.planColor
        case .thinking: return modeColor
        }
    }

    // MARK: - Icons

    private func icon(for activity: TaskActivity) -> String {
        switch activity.type {
        case "turn_started": return "play.circle.fill"
        case "turn_completed": return "checkmark.circle.fill"
        case "command_execution", "bash": return "terminal.fill"
        case "file_change", "edit": return "pencil"
        case "mcp_tool_call": return "wrench.and.screwdriver.fill"
        case "web_search", "web_search_started", "web_search_completed", "web_search_failed":
            return "magnifyingglass"
        case "read_batch_started", "read_batch_completed":
            return "doc.on.doc"
        case "todo_write", "todo_read":
            return "checklist"
        case "process_paused": return "pause.circle.fill"
        case "process_resumed": return "play.circle.fill"
        case "agent": return "person.circle.fill"
        default: return "gearshape.fill"
        }
    }
}

// MARK: - Shimmer Trail (Cursor-style silver scia)

struct ActivityShimmerTrail: View {
    @State private var phase: CGFloat = 0

    private let trailWidth: CGFloat = 120
    private let silverColor = Color.white.opacity(0.35)

    var body: some View {
        GeometryReader { geo in
            LinearGradient(
                colors: [
                    Color.clear,
                    silverColor.opacity(0.4),
                    silverColor,
                    silverColor.opacity(0.4),
                    Color.clear,
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(width: trailWidth)
            .offset(x: phase * (geo.size.width + trailWidth * 2) - trailWidth)
            .blendMode(.plusLighter)
        }
        .onAppear {
            withAnimation(
                .linear(duration: 2.2)
                .repeatForever(autoreverses: false)
            ) { phase = 1 }
        }
    }
}
