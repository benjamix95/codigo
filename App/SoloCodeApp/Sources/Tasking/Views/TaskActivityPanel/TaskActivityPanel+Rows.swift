import SwiftUI

struct TaskActivityRow: View {
    let activity: TaskActivity

    private var typeIcon: String {
        TaskActivityVisualStyle.icon(for: activity.type)
    }

    private var typeColor: Color {
        TaskActivityVisualStyle.color(for: activity.type)
    }

    private var timeString: String {
        TaskActivityPanelFormatters.timeFormatter.string(from: activity.timestamp)
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
                    .textShimmer(active: activity.isRunning)
                if let detail = activity.userFacingDetail, !detail.isEmpty {
                    Text(detail)
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .textShimmer(active: activity.isRunning)
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
