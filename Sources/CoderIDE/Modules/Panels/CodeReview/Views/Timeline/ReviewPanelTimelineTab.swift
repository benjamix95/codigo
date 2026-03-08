import CoderEngine
import SwiftUI

/// Timeline tab showing review session events in reverse chronological order.
struct ReviewPanelTimelineTab: View {
    @ObservedObject var store: CodeReviewPanelStore

    var body: some View {
        let events = store.currentEvents
        if events.isEmpty {
            emptyPlaceholder
        } else {
            timelineContent(events)
        }
    }

    private var emptyPlaceholder: some View {
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

    // MARK: - Row

    private func timelineRow(_ event: CodeReviewSessionEvent) -> some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(spacing: 0) {
                Circle()
                    .fill(eventColor(event.type))
                    .frame(width: 6, height: 6)
                    .padding(.top, 4)
                Rectangle()
                    .fill(Color.primary.opacity(0.08))
                    .frame(width: 1)
            }
            .frame(width: 6)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Image(systemName: eventIcon(event.type))
                        .font(.system(size: 9))
                        .foregroundStyle(eventColor(event.type))

                    Text(eventLabel(event.type))
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

    // MARK: - Event Helpers

    private func eventColor(_ type: CodeReviewSessionEvent.EventType) -> Color {
        switch type {
        case .sessionStarted, .sessionCompleted: return store.accent
        case .analysisStarted, .analysisCompleted: return DesignSystem.Colors.info
        case .auditStarted, .auditCompleted: return DesignSystem.Colors.info.opacity(0.85)
        case .candidateAdded: return DesignSystem.Colors.info
        case .candidateVerified: return DesignSystem.Colors.success
        case .candidateRejected: return .secondary
        case .findingAdded: return DesignSystem.Colors.warning
        case .findingFixApplied: return DesignSystem.Colors.success
        case .findingDismissed: return .secondary
        case .findingCommented: return store.accent
        case .patchPrepared, .patchVerified: return store.accent
        case .patchApplyFailed, .conflictDetected: return DesignSystem.Colors.error
        case .prOpened, .prMerged: return DesignSystem.Colors.success
        case .outcomePublished: return DesignSystem.Colors.info
        case .roundStarted, .roundCompleted: return DesignSystem.Colors.info
        case .workerSpawned, .workerCompleted: return .secondary
        case .testsPassed: return DesignSystem.Colors.success
        case .testsFailed: return DesignSystem.Colors.error
        case .configUpdated: return .secondary
        case .error: return DesignSystem.Colors.error
        }
    }

    private func eventIcon(_ type: CodeReviewSessionEvent.EventType) -> String {
        switch type {
        case .sessionStarted: return "play.circle.fill"
        case .sessionCompleted: return "checkmark.circle.fill"
        case .analysisStarted: return "magnifyingglass"
        case .analysisCompleted: return "magnifyingglass.circle.fill"
        case .auditStarted: return "shield"
        case .auditCompleted: return "shield.checkered"
        case .candidateAdded: return "plus.circle"
        case .candidateVerified: return "checkmark.seal"
        case .candidateRejected: return "xmark.seal"
        case .findingAdded: return "exclamationmark.triangle"
        case .findingFixApplied: return "wrench.and.screwdriver"
        case .findingDismissed: return "xmark.circle"
        case .findingCommented: return "bubble.left"
        case .patchPrepared: return "doc.badge.plus"
        case .patchVerified: return "checkmark.shield"
        case .patchApplyFailed: return "xmark.octagon"
        case .prOpened: return "arrow.up.right.square"
        case .prMerged: return "arrow.merge"
        case .conflictDetected: return "exclamationmark.arrow.trianglehead.2.clockwise.rotate.90"
        case .outcomePublished: return "text.badge.checkmark"
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

    private func eventLabel(_ type: CodeReviewSessionEvent.EventType) -> String {
        switch type {
        case .sessionStarted: return "Review Started"
        case .sessionCompleted: return "Review Completed"
        case .analysisStarted: return "Analysis Started"
        case .analysisCompleted: return "Analysis Completed"
        case .auditStarted: return "Audit Started"
        case .auditCompleted: return "Audit Completed"
        case .candidateAdded: return "Candidate Added"
        case .candidateVerified: return "Candidate Verified"
        case .candidateRejected: return "Candidate Rejected"
        case .findingAdded: return "Finding Added"
        case .findingFixApplied: return "Fix Applied"
        case .findingDismissed: return "Finding Dismissed"
        case .findingCommented: return "Comment Added"
        case .patchPrepared: return "Patch Prepared"
        case .patchVerified: return "Patch Verified"
        case .patchApplyFailed: return "Patch Apply Failed"
        case .prOpened: return "PR Opened"
        case .prMerged: return "PR Merged"
        case .conflictDetected: return "Conflict Detected"
        case .outcomePublished: return "Outcome Published"
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
