import SwiftUI

/// Compact/expanded activity trace view used in both Plan and Debug panels.
/// Default: compact mode showing last few running activities with auto-scroll.
/// Tap to expand and see all activities; tap again to collapse.
struct CompactActivityTraceView: View {
    let activities: [TaskActivity]
    let accentColor: Color
    let title: String

    @State private var isExpanded = false
    @State private var autoScrollId: UUID?

    /// How many items to show in compact mode
    private let compactLimit = 4

    private var hasRunningActivity: Bool {
        activities.contains(where: \.isRunning)
    }

    private var compactCompletedSummary: String? {
        guard !activities.isEmpty, !hasRunningActivity, !isExpanded else { return nil }
        guard let last = activities.last else { return nil }
        return "\(last.title) • \(activities.count) eventi"
    }

    private var displayActivities: [TaskActivity] {
        if isExpanded {
            return activities
        }
        // In compact: show only the last N activities, prioritizing running ones
        let running = activities.filter(\.isRunning)
        if !running.isEmpty {
            return Array(running.suffix(compactLimit))
        }
        return Array(activities.suffix(compactLimit))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header with expand/collapse
            Button {
                withAnimation(.easeOut(duration: 0.2)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "chart.bar.doc.horizontal")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(accentColor.opacity(0.7))

                    Text(title)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)

                    Spacer()

                    Text("\(activities.count)")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(accentColor)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(accentColor.opacity(0.1), in: Capsule())

                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // Activity list / compact completed summary
            if let summary = compactCompletedSummary {
                Rectangle().fill(Color(nsColor: .separatorColor).opacity(0.15)).frame(height: 0.5)
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary.opacity(0.8))
                    Text(summary)
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Spacer()
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
            } else if !displayActivities.isEmpty {
                Rectangle().fill(Color(nsColor: .separatorColor).opacity(0.15)).frame(height: 0.5)

                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 1) {
                            ForEach(displayActivities) { activity in
                                compactRow(activity)
                                    .id(activity.id)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .frame(maxHeight: isExpanded ? 300 : 140)
                    .onChange(of: activities.count) { _, _ in
                        // Auto-scroll to latest
                        if let last = displayActivities.last {
                            withAnimation(.easeOut(duration: 0.15)) {
                                proxy.scrollTo(last.id, anchor: .bottom)
                            }
                        }
                    }
                    .onAppear {
                        if let last = displayActivities.last {
                            proxy.scrollTo(last.id, anchor: .bottom)
                        }
                    }
                }

                if !isExpanded && activities.count > compactLimit {
                    HStack {
                        Spacer()
                        Text("\(activities.count - compactLimit) more...")
                            .font(.system(size: 9))
                            .foregroundStyle(.tertiary)
                        Spacer()
                    }
                    .padding(.vertical, 3)
                }
            }
        }
        .background(Color.primary.opacity(0.02), in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(accentColor.opacity(0.12), lineWidth: 0.5)
        )
    }

    // MARK: - Compact Row

    private func compactRow(_ activity: TaskActivity) -> some View {
        HStack(spacing: 6) {
            // Running indicator
            if activity.isRunning {
                Circle()
                    .fill(accentColor)
                    .frame(width: 5, height: 5)
            } else {
                Circle()
                    .fill(Color.secondary.opacity(0.3))
                    .frame(width: 5, height: 5)
            }

            Image(systemName: iconForType(activity.type))
                .font(.system(size: 9))
                .foregroundStyle(activity.isRunning ? accentColor : Color.secondary.opacity(0.5))
                .frame(width: 12)

            Text(activity.title)
                .font(.system(size: 10, weight: activity.isRunning ? .medium : .regular))
                .foregroundStyle(activity.isRunning ? .primary : .secondary)
                .lineLimit(1)

            Spacer()

            Text(timeString(activity.timestamp))
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(.quaternary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 3)
        .background(activity.isRunning ? accentColor.opacity(0.04) : Color.clear)
    }

    private func iconForType(_ type: String) -> String {
        switch type {
        case "command_execution", "bash": return "terminal.fill"
        case "read_batch_started", "read_batch_completed": return "doc.on.doc"
        case "mcp_tool_call": return "wrench.and.screwdriver.fill"
        case "web_search", "web_search_started", "web_search_completed", "web_search_failed": return "magnifyingglass"
        case "process_paused": return "pause.circle.fill"
        case "process_resumed": return "play.circle.fill"
        case "plan_step_update": return "list.bullet.rectangle"
        case "debug_panel", "debug_panel_update": return "ladybug.fill"
        case "file_change", "edit": return "doc.text.fill"
        default: return "circle.fill"
        }
    }

    private func timeString(_ date: Date) -> String {
        CompactTraceFormatters.hms.string(from: date)
    }
}

private enum CompactTraceFormatters {
    static let hms: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()
}
