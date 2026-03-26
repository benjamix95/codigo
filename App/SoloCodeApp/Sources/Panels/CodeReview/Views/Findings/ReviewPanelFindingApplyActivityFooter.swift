import CoderEngine
import SwiftUI

/// Timer durante apply patch e feed compatto delle attività di review per sessione / conversazione.
struct ReviewPanelFindingApplyActivityFooter: View {
    @ObservedObject var store: CodeReviewPanelStore
    let findingId: String

    var body: some View {
        let sessionId = store.selectedSessionId
        let all = store.taskActivityStore.activities
        let convScoped = scopedTaskActivitiesForConversation(all, conversationId: store.conversationId)
        let sessionScoped = scopedReviewActivitiesForSession(convScoped, sessionId: sessionId)
        let rows = Array(sessionScoped.suffix(24))

        VStack(alignment: .leading, spacing: 8) {
            Text("ATTIVITÀ")
                .font(.system(size: 8.5, weight: .bold))
                .foregroundStyle(.tertiary)
                .tracking(0.8)

            if store.applyingPatchFindingId == findingId, let start = store.applyPatchPhaseStartedAt {
                TimelineView(.periodic(from: start, by: 0.25)) { context in
                    applyTimerRow(elapsed: context.date.timeIntervalSince(start))
                }
            }

            if rows.isEmpty {
                Text("Nessuna attività recente per questa sessione.")
                    .font(.system(size: 9))
                    .foregroundStyle(.quaternary)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 5) {
                        ForEach(rows.reversed()) { activity in
                            activityRow(activity)
                        }
                    }
                }
                .frame(maxHeight: 112)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            Color(nsColor: .windowBackgroundColor).opacity(0.92),
            in: Rectangle()
        )
        .overlay(alignment: .top) {
            Divider().opacity(0.22)
        }
    }

    private func applyTimerRow(elapsed: TimeInterval) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "timer")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(store.accent)
            Text("Apply patch in corso")
                .font(.system(size: 10, weight: .semibold))
            Spacer(minLength: 8)
            Text(formatElapsed(elapsed))
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(store.accent)
        }
        .padding(8)
        .background(store.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func activityRow(_ activity: TaskActivity) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Circle()
                    .fill(activity.isRunning ? DesignSystem.Colors.warning : Color.secondary.opacity(0.35))
                    .frame(width: 6, height: 6)
                Text(activity.title)
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                Spacer(minLength: 4)
                Text(activity.timestamp, style: .time)
                    .font(.system(size: 8, weight: .medium, design: .monospaced))
                    .foregroundStyle(.quaternary)
            }
            if let detail = activity.detail?.trimmingCharacters(in: .whitespacesAndNewlines), !detail.isEmpty {
                Text(detail)
                    .font(.system(size: 8.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 4)
    }

    private func formatElapsed(_ interval: TimeInterval) -> String {
        let s = max(0, Int(interval.rounded(.down)))
        let m = s / 60
        let r = s % 60
        return String(format: "%d:%02d", m, r)
    }
}
