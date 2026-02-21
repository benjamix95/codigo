import SwiftUI

private enum LiveTimelineFormatters {
    static let hms: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()
}

struct LiveActivityTimelineView: View {
    let activities: [TaskActivity]
    let maxVisible: Int

    @State private var expandedIds: Set<UUID> = []

    private var visibleActivities: [TaskActivity] {
        Array(activities.suffix(maxVisible))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(visibleActivities) { activity in
                row(activity)
            }
        }
        .padding(8)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.34), in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(DesignSystem.Colors.border.opacity(0.5), lineWidth: 0.6)
        )
    }

    private func row(_ activity: TaskActivity) -> some View {
        let expanded = expandedIds.contains(activity.id)
        return VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 7) {
                Image(systemName: icon(for: activity))
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(color(for: activity))
                    .frame(width: 14)
                Text(activity.title)
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(1)
                Spacer()
                Text(timestamp(activity.timestamp))
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.tertiary)
                Button {
                    if expanded { expandedIds.remove(activity.id) } else { expandedIds.insert(activity.id) }
                } label: {
                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 9, weight: .semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }

            if expanded {
                if let detail = activity.detail, !detail.isEmpty {
                    Text(detail)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
                if let command = activity.payload["command"], !command.isEmpty {
                    Text("$ \(command)")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.primary)
                        .textSelection(.enabled)
                }
                if let output = activity.payload["output"], !output.isEmpty {
                    Text(output)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(8)
                        .textSelection(.enabled)
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .background(Color.black.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
    }

    private func icon(for activity: TaskActivity) -> String {
        switch activity.phase {
        case .executing: return "terminal"
        case .editing: return "pencil"
        case .searching: return "magnifyingglass"
        case .planning: return "list.bullet.rectangle"
        case .thinking: return "brain"
        }
    }

    private func color(for activity: TaskActivity) -> Color {
        switch activity.phase {
        case .executing: return DesignSystem.Colors.warning
        case .editing: return DesignSystem.Colors.agentColor
        case .searching: return DesignSystem.Colors.info
        case .planning: return DesignSystem.Colors.planColor
        case .thinking: return .secondary
        }
    }

    private func timestamp(_ date: Date) -> String {
        LiveTimelineFormatters.hms.string(from: date)
    }
}
