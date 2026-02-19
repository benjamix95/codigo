import SwiftUI

struct TaskActivityPanelView: View {
    @ObservedObject var store: TaskActivityStore

    var body: some View {
        ScrollView(.vertical, showsIndicators: true) {
            LazyVStack(alignment: .leading, spacing: 4) {
                ForEach(store.activities) { activity in
                    TaskActivityRow(activity: activity)
                }
            }
            .padding(8)
        }
        .frame(maxHeight: 120)
        .background(Color(nsColor: .controlBackgroundColor))
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
        case "edit", "file_change": return .green
        case "bash", "command_execution": return .orange
        case "search", "web_search": return .blue
        case "mcp_tool_call": return .purple
        case "agent": return .cyan
        default: return .secondary
        }
    }

    private var timeString: String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f.string(from: activity.timestamp)
    }

    var body: some View {
        HStack(alignment: .center, spacing: 6) {
            Image(systemName: typeIcon)
                .font(.caption)
                .foregroundStyle(typeColor)
                .frame(width: 18, alignment: .center)

            VStack(alignment: .leading, spacing: 1) {
                Text(activity.title)
                    .font(.caption.weight(.medium))
                    .lineLimit(1)
                if let detail = activity.detail, !detail.isEmpty {
                    Text(detail)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(timeString)
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .monospacedDigit()
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
    }
}
