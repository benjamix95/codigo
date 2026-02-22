import CoderEngine
import SwiftUI

/// Vista inline della timeline attività durante lo streaming dell'assistant.
/// Mostra la lista di step operativi (comandi, modifiche file, web search, ecc.)
/// che l'LLM invoca tramite lo stream. Nessun label fabricato: si mostra solo
/// ciò che proviene dall'LLM o dagli eventi attività.
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

    private var visibleActivities: [TaskActivity] {
        activities
            .filter { TaskActivityStore.isConcreteVisibleEvent($0) }
            .suffix(maxVisible)
            .map { $0 }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if visibleActivities.isEmpty {
                statusPlaceholder
            } else {
                ForEach(visibleActivities) { activity in
                    activityRow(activity)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(maxWidth: 760, alignment: .leading)
    }

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

    private func activityRow(_ activity: TaskActivity) -> some View {
        let isRunning = activity.isRunning
        return HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon(for: activity))
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 16, alignment: .center)
            VStack(alignment: .leading, spacing: 2) {
                Text(activity.title)
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                if let detail = detailText(for: activity), !detail.isEmpty {
                    Text(detail)
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            Spacer(minLength: 0)
            statusBadge(for: activity)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.18))
        .overlay {
            if isRunning {
                ActivityShimmerTrail()
                .allowsHitTesting(false)
            }
        }
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(DesignSystem.Colors.border.opacity(0.3))
                .frame(height: 0.5)
        }
        .frame(maxWidth: 760)
    }

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

    private func statusBadge(for activity: TaskActivity) -> some View {
        let status = statusText(for: activity)
        let color = statusColor(for: activity)
        return Text(status)
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(color)
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
        case "running": return .secondary
        case "done": return Color(nsColor: .tertiaryLabelColor)
        case "failed": return DesignSystem.Colors.error
        default: return .secondary
        }
    }

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
        default: return "gearshape.fill"
        }
    }
}

// MARK: - Shimmer Trail (Cursor-style silver scia)

private struct ActivityShimmerTrail: View {
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
