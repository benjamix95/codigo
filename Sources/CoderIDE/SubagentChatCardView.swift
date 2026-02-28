import SwiftUI

/// Inline card displayed in chat when a subagent is running or has completed.
/// Shows subagent title, status, current step, and expandable event list.
struct SubagentChatCardView: View {
    let card: SwarmLiveCardState
    let onOpenInPanel: () -> Void

    @State private var isExpanded = false

    private let maxPreviewEvents = 6

    private var visibleEvents: [TaskActivity] {
        card.recentEvents
            .filter { TaskActivityStore.isConcreteVisibleEvent($0) }
            .suffix(maxPreviewEvents)
            .map { $0 }
    }

    private var statusColor: Color {
        switch card.status {
        case .running: return DesignSystem.Colors.swarmColor
        case .completed: return DesignSystem.Colors.success
        case .failed: return DesignSystem.Colors.error
        case .idle: return .secondary
        }
    }

    private var statusLabel: String {
        switch card.status {
        case .running: return "Running"
        case .completed: return "Completed"
        case .failed: return "Failed"
        case .idle: return "Idle"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            headerRow
            stepRow

            if isExpanded {
                expandedContent
            }

            footerRow
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.3))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(statusColor.opacity(0.25), lineWidth: 0.8)
        )
        .contentShape(RoundedRectangle(cornerRadius: 10))
        .onTapGesture {
            withAnimation(.spring(response: 0.2, dampingFraction: 0.9)) {
                isExpanded.toggle()
            }
        }
    }

    // MARK: - Header

    private var headerRow: some View {
        HStack(spacing: 6) {
            if card.status == .running {
                Circle()
                    .fill(statusColor)
                    .frame(width: 7, height: 7)
                    .modifier(PulseModifier())
            } else {
                Circle()
                    .fill(statusColor)
                    .frame(width: 7, height: 7)
            }

            Text(card.swarmId)
                .font(.system(size: 11, weight: .semibold))
                .lineLimit(1)

            Text(statusLabel)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(statusColor)
                .padding(.horizontal, 5)
                .padding(.vertical, 1)
                .background(statusColor.opacity(0.12), in: Capsule())

            Spacer()

            if card.activeOpsCount > 0 {
                Text("\(card.activeOpsCount) ops")
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }

            if card.errorCount > 0 {
                Text("\(card.errorCount) err")
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundStyle(DesignSystem.Colors.error)
            }
        }
    }

    // MARK: - Step

    private var stepRow: some View {
        Text(card.currentStepTitle)
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(.secondary)
            .lineLimit(isExpanded ? 4 : 1)
    }

    // MARK: - Expanded Content

    private var expandedContent: some View {
        VStack(alignment: .leading, spacing: 4) {
            if !visibleEvents.isEmpty {
                ForEach(visibleEvents) { activity in
                    HStack(spacing: 5) {
                        Circle()
                            .fill(activity.isRunning ? DesignSystem.Colors.warning : .secondary)
                            .frame(width: 5, height: 5)
                        Text(activity.title)
                            .font(.system(size: 10))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        Spacer()
                        Text(activity.timestamp.formatted(date: .omitted, time: .standard))
                            .font(.system(size: 8, design: .monospaced))
                            .foregroundStyle(.quaternary)
                    }
                }
            }

            if let summary = card.summary, !summary.isEmpty {
                Rectangle()
                    .fill(DesignSystem.Colors.border.opacity(0.4))
                    .frame(height: 0.5)
                    .padding(.vertical, 2)
                Text(summary)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(6)
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Footer

    private var footerRow: some View {
        HStack(spacing: 8) {
            Button(isExpanded ? "Collapse" : "Expand") {
                withAnimation(.spring(response: 0.2, dampingFraction: 0.9)) {
                    isExpanded.toggle()
                }
            }
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(.secondary)
            .buttonStyle(.plain)

            Button {
                onOpenInPanel()
            } label: {
                HStack(spacing: 3) {
                    Text("Open in Panel")
                        .font(.system(size: 10, weight: .medium))
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 8, weight: .semibold))
                }
                .foregroundStyle(DesignSystem.Colors.swarmColor)
            }
            .buttonStyle(.plain)

            Spacer()

            if let completedAt = card.completedAt {
                Text(completedAt.formatted(date: .omitted, time: .standard))
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.tertiary)
            } else if let lastEvent = card.lastEventAt {
                Text(lastEvent.formatted(date: .omitted, time: .standard))
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }
        }
    }
}
