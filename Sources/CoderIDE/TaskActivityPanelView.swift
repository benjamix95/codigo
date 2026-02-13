import SwiftUI

struct TaskActivityPanelView: View {
    @ObservedObject var store: TaskActivityStore

    var body: some View {
        ScrollView(.vertical, showsIndicators: true) {
            LazyVStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
                ForEach(store.activities) { activity in
                    TaskActivityRow(activity: activity)
                }
            }
            .padding(DesignSystem.Spacing.sm)
        }
        .frame(maxHeight: 120)
        .liquidGlass(cornerRadius: DesignSystem.CornerRadius.medium, tint: DesignSystem.Colors.swarmColor, borderOpacity: 0.08)
        .overlay {
            Rectangle()
                .frame(height: 0.5)
                .foregroundStyle(DesignSystem.Colors.divider)
                .frame(maxHeight: .infinity, alignment: .bottom)
        }
    }
}

private struct TaskActivityRow: View {
    let activity: TaskActivity

    private var typeIcon: String {
        switch activity.type {
        case "edit", "file_change": return "doc.text.fill"
        case "bash", "command_execution": return "terminal.fill"
        case "search", "web_search": return "magnifyingglass"
        case "mcp_tool_call": return "wrench.and.screwdriver.fill"
        case "agent": return "ant.fill"
        default: return "circle.fill"
        }
    }

    private var typeColor: Color {
        switch activity.type {
        case "edit", "file_change": return DesignSystem.Colors.success
        case "bash", "command_execution": return DesignSystem.Colors.warning
        case "search", "web_search": return DesignSystem.Colors.info
        case "mcp_tool_call": return DesignSystem.Colors.ideColor
        case "agent": return DesignSystem.Colors.swarmColor
        default: return DesignSystem.Colors.textSecondary
        }
    }

    private var timeString: String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f.string(from: activity.timestamp)
    }

    var body: some View {
        HStack(alignment: .center, spacing: DesignSystem.Spacing.sm) {
            Image(systemName: typeIcon)
                .font(DesignSystem.Typography.caption)
                .foregroundStyle(typeColor)
                .frame(width: 20, alignment: .center)

            VStack(alignment: .leading, spacing: 2) {
                Text(activity.title)
                    .font(DesignSystem.Typography.captionMedium)
                    .foregroundStyle(DesignSystem.Colors.textPrimary)
                    .lineLimit(1)

                if let detail = activity.detail, !detail.isEmpty {
                    Text(detail)
                        .font(DesignSystem.Typography.caption2)
                        .foregroundStyle(DesignSystem.Colors.textTertiary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(timeString)
                .font(DesignSystem.Typography.caption2)
                .foregroundStyle(DesignSystem.Colors.textTertiary)
                .monospacedDigit()
        }
        .padding(.horizontal, DesignSystem.Spacing.sm)
        .padding(.vertical, DesignSystem.Spacing.xs)
    }
}
