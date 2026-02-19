import SwiftUI

struct WebSearchLiveView: View {
    let activities: [TaskActivity]

    private var webActivities: [TaskActivity] {
        activities.filter {
            $0.type == "web_search" ||
            $0.type == "web_search_started" ||
            $0.type == "web_search_completed" ||
            $0.type == "web_search_failed"
        }
        .suffix(12)
        .map { $0 }
    }

    var body: some View {
        if !webActivities.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Web searches")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                ForEach(webActivities) { activity in
                    HStack(spacing: 8) {
                        Image(systemName: icon(for: activity))
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(color(for: activity))
                            .frame(width: 14)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(activity.payload["query"] ?? activity.title)
                                .font(.system(size: 11, weight: .medium))
                                .lineLimit(1)
                            HStack(spacing: 6) {
                                if let status = activity.payload["status"], !status.isEmpty {
                                    Text(status.capitalized)
                                        .font(.system(size: 10, weight: .semibold))
                                        .foregroundStyle(.tertiary)
                                }
                                if let count = activity.payload["resultCount"], !count.isEmpty {
                                    Text("\(count) risultati")
                                        .font(.system(size: 10))
                                        .foregroundStyle(.tertiary)
                                }
                                if let duration = activity.payload["duration_ms"], !duration.isEmpty {
                                    Text("\(duration) ms")
                                        .font(.system(size: 10, design: .monospaced))
                                        .foregroundStyle(.tertiary)
                                }
                            }
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(Color.black.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
                }
            }
        }
    }

    private func icon(for activity: TaskActivity) -> String {
        switch activity.type {
        case "web_search_failed": return "xmark.circle.fill"
        case "web_search_completed": return "checkmark.circle.fill"
        default: return "magnifyingglass.circle.fill"
        }
    }

    private func color(for activity: TaskActivity) -> Color {
        switch activity.type {
        case "web_search_failed": return DesignSystem.Colors.error
        case "web_search_completed": return DesignSystem.Colors.success
        default: return DesignSystem.Colors.info
        }
    }
}
