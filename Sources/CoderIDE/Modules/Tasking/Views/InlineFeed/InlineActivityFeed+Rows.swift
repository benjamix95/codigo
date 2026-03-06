import CoderEngine
import SwiftUI

extension InlineActivityFeedView {
    func activityRow(_ activity: TaskActivity, isExpanded: Bool) -> some View {
        let isRunning = activity.isRunning
        let phaseColor = phaseAccentColor(for: activity)

        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: icon(for: activity))
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(isRunning ? phaseColor : DesignSystem.Colors.textTertiary)
                    .frame(width: 16, alignment: .center)

                VStack(alignment: .leading, spacing: 2) {
                    Text(activity.title)
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(.primary)
                        .lineLimit(isExpanded ? 4 : 1)
                        .textShimmer(active: isRunning)
                    if !isExpanded, let detail = detailText(for: activity), !detail.isEmpty {
                        Text(detail)
                            .font(.system(size: 10.5))
                            .foregroundStyle(DesignSystem.Colors.textSecondary)
                            .lineLimit(1)
                            .textShimmer(active: isRunning)
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

            if isExpanded {
                expandedDetail(for: activity, phaseColor: phaseColor)
            }
        }
        .background(
            Rectangle()
                .fill(isExpanded
                      ? DesignSystem.Colors.backgroundSecondary
                      : DesignSystem.Colors.backgroundSecondary.opacity(0.4))
        )
        .overlay(alignment: .leading) {
            if isRunning {
                Rectangle()
                    .fill(phaseColor)
                    .frame(width: 2)
            }
        }
        .overlay {
            if isRunning, !isExpanded {
                ActivityShimmerTrail()
                    .allowsHitTesting(false)
                    .clipShape(Rectangle())
            }
        }
        .frame(maxWidth: 760)
    }

    func expandedDetail(for activity: TaskActivity, phaseColor: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
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
            if let swarmId = SwarmMetadata.swarmId(from: activity.payload)
            {
                detailField(label: "Sub-agent", value: swarmId, icon: "person.2", color: DesignSystem.Colors.swarmColor)
            }
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
        .padding(.leading, 24)
    }

    func detailField(label: String, value: String, icon: String, color: Color) -> some View {
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

    func detailText(for activity: TaskActivity) -> String? {
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

    func statusBadge(for activity: TaskActivity) -> some View {
        let status = statusText(for: activity)
        let color = statusColor(for: activity)
        return Text(status.uppercased())
            .font(.system(size: 8, weight: .bold, design: .monospaced))
            .foregroundStyle(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.12), in: Capsule())
    }

    func statusText(for activity: TaskActivity) -> String {
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

    func statusColor(for activity: TaskActivity) -> Color {
        switch statusText(for: activity) {
        case "running": return modeColor
        case "done": return DesignSystem.Colors.success
        case "failed": return DesignSystem.Colors.error
        default: return DesignSystem.Colors.textTertiary
        }
    }

    func statusDotColor(_ status: String) -> Color {
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

    func phaseAccentColor(for activity: TaskActivity) -> Color {
        switch activity.phase {
        case .executing: return DesignSystem.Colors.warning
        case .editing: return DesignSystem.Colors.info
        case .searching: return DesignSystem.Colors.swarmColor
        case .planning: return DesignSystem.Colors.planColor
        case .thinking: return modeColor
        }
    }

    func icon(for activity: TaskActivity) -> String {
        switch activity.type {
        case "turn_started": return "play.circle.fill"
        case "turn_completed": return "checkmark.circle.fill"
        case "command_execution", "bash": return "terminal.fill"
        case "file_change", "edit": return "pencil"
        case "mcp_tool_call": return "wrench.and.screwdriver.fill"
        case "web_search", "web_search_started", "web_search_completed", "web_search_failed":
            return "magnifyingglass"
        case "web_fetch", "web_fetch_started", "web_fetch_completed", "web_fetch_failed":
            return "globe"
        case "read_batch_started", "read_batch_completed":
            return "doc.on.doc"
        case "todo_write", "todo_read":
            return "checklist"
        case "debug_log": return "text.badge.plus"
        case "debug_query": return "text.magnifyingglass"
        case "debug_session": return "play.circle.fill"
        case "debug_hypothesize": return "ladybug.fill"
        case "debug_mark": return "mappin.and.ellipse"
        case "debug_clean": return "trash.fill"
        case "debug_context": return "ant.fill"
        case "debug_phase_update": return "arrow.triangle.turn.up.right.diamond.fill"
        case "debug_user_request": return "questionmark.bubble.fill"
        case "debug_resolved": return "checkmark.seal.fill"
        case "process_paused": return "pause.circle.fill"
        case "process_resumed": return "play.circle.fill"
        case "agent": return "person.circle.fill"
        default: return "gearshape.fill"
        }
    }
}
