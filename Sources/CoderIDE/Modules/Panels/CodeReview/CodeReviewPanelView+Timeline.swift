import SwiftUI
import CoderEngine

extension CodeReviewPanelView {
    // MARK: - Timeline View

    @ViewBuilder
    func timelineView(_ events: [CodeReviewSessionEvent]) -> some View {
        if events.isEmpty {
            emptyTimelinePlaceholder
        } else {
            timelineContent(events)
        }
    }

    // MARK: - Empty Placeholder

    private var emptyTimelinePlaceholder: some View {
        VStack(spacing: 8) {
            Image(systemName: "clock")
                .font(.system(size: 24))
                .foregroundStyle(.tertiary)
            Text("No events yet")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    // MARK: - Timeline Content

    private func timelineContent(_ events: [CodeReviewSessionEvent]) -> some View {
        ScrollView(.vertical, showsIndicators: true) {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(events.reversed(), id: \.id) { event in
                    timelineRow(event)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
        }
    }

    // MARK: - Timeline Row

    private func timelineRow(_ event: CodeReviewSessionEvent) -> some View {
        HStack(alignment: .top, spacing: 8) {
            // Timeline connector
            VStack(spacing: 0) {
                Circle()
                    .fill(timelineEventColor(event.type))
                    .frame(width: 6, height: 6)
                    .padding(.top, 4)
                Rectangle()
                    .fill(Color.primary.opacity(0.08))
                    .frame(width: 1)
            }
            .frame(width: 6)

            // Event content
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Image(systemName: timelineEventIcon(event.type))
                        .font(.system(size: 9))
                        .foregroundStyle(timelineEventColor(event.type))

                    Text(timelineEventLabel(event.type))
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.primary.opacity(0.85))

                    Spacer()

                    Text(event.timestamp, style: .relative)
                        .font(.system(size: 8, design: .monospaced))
                        .foregroundStyle(.quaternary)
                }

                if let detail = event.detail, !detail.isEmpty {
                    Text(detail)
                        .font(.system(size: 10))
                        .foregroundStyle(.primary.opacity(0.7))
                        .lineLimit(2)
                }
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: - Event Visual Helpers

    private func timelineEventColor(
        _ type: CodeReviewSessionEvent.EventType
    ) -> Color {
        switch type {
        case .sessionStarted, .sessionCompleted:
            return accent
        case .analysisStarted, .analysisCompleted:
            return DesignSystem.Colors.info
        case .findingAdded:
            return DesignSystem.Colors.warning
        case .findingFixApplied:
            return DesignSystem.Colors.success
        case .findingDismissed:
            return .secondary
        case .findingCommented:
            return accent
        case .roundStarted, .roundCompleted:
            return DesignSystem.Colors.info
        case .workerSpawned, .workerCompleted:
            return .secondary
        case .testsPassed:
            return DesignSystem.Colors.success
        case .testsFailed:
            return DesignSystem.Colors.error
        case .configUpdated:
            return .secondary
        case .error:
            return DesignSystem.Colors.error
        }
    }

    private func timelineEventIcon(
        _ type: CodeReviewSessionEvent.EventType
    ) -> String {
        switch type {
        case .sessionStarted: return "play.circle.fill"
        case .sessionCompleted: return "checkmark.circle.fill"
        case .analysisStarted: return "magnifyingglass"
        case .analysisCompleted: return "magnifyingglass.circle.fill"
        case .findingAdded: return "exclamationmark.triangle"
        case .findingFixApplied: return "wrench.and.screwdriver"
        case .findingDismissed: return "xmark.circle"
        case .findingCommented: return "bubble.left"
        case .roundStarted: return "arrow.clockwise"
        case .roundCompleted: return "arrow.clockwise.circle.fill"
        case .workerSpawned: return "person.badge.plus"
        case .workerCompleted: return "person.badge.checkmark"
        case .testsPassed: return "checkmark.diamond.fill"
        case .testsFailed: return "xmark.diamond.fill"
        case .configUpdated: return "gearshape"
        case .error: return "exclamationmark.octagon.fill"
        }
    }

    private func timelineEventLabel(
        _ type: CodeReviewSessionEvent.EventType
    ) -> String {
        switch type {
        case .sessionStarted: return "Review Started"
        case .sessionCompleted: return "Review Completed"
        case .analysisStarted: return "Analysis Started"
        case .analysisCompleted: return "Analysis Completed"
        case .findingAdded: return "Finding Added"
        case .findingFixApplied: return "Fix Applied"
        case .findingDismissed: return "Finding Dismissed"
        case .findingCommented: return "Comment Added"
        case .roundStarted: return "Round Started"
        case .roundCompleted: return "Round Completed"
        case .workerSpawned: return "Worker Spawned"
        case .workerCompleted: return "Worker Completed"
        case .testsPassed: return "Tests Passed"
        case .testsFailed: return "Tests Failed"
        case .configUpdated: return "Config Updated"
        case .error: return "Error"
        }
    }
}
