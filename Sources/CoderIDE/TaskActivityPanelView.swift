import SwiftUI

struct TaskActivityPanelView: View {
    @ObservedObject var store: TaskActivityStore

    var body: some View {
        ScrollView(.vertical, showsIndicators: true) {
            LazyVStack(alignment: .leading, spacing: 3) {
                ForEach(store.activities) { activity in
                    TaskActivityRow(activity: activity)
                }
            }
            .padding(8)
        }
        .frame(maxHeight: 120)
        .background(DesignSystem.Colors.backgroundSecondary.opacity(0.5))
        .overlay(alignment: .bottom) {
            Rectangle().fill(DesignSystem.Colors.border).frame(height: 0.5)
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
        case "edit", "file_change": return DesignSystem.Colors.agentColor
        case "bash", "command_execution": return DesignSystem.Colors.warning
        case "search", "web_search": return DesignSystem.Colors.info
        case "mcp_tool_call": return DesignSystem.Colors.ideColor
        case "agent": return DesignSystem.Colors.swarmColor
        default: return .secondary
        }
    }

    private var timeString: String {
        let f = DateFormatter(); f.dateFormat = "HH:mm:ss"; return f.string(from: activity.timestamp)
    }

    var body: some View {
        HStack(alignment: .center, spacing: 6) {
            Image(systemName: typeIcon)
                .font(.system(size: 10))
                .foregroundStyle(typeColor)
                .frame(width: 16, alignment: .center)

            VStack(alignment: .leading, spacing: 1) {
                Text(activity.title)
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(1)
                if let detail = activity.detail, !detail.isEmpty {
                    Text(detail)
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(timeString)
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(.quaternary)
        }
        .padding(.horizontal, 6).padding(.vertical, 2)
    }
}
