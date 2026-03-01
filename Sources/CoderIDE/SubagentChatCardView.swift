import SwiftUI

// MARK: - Shared Helpers

private func roleDisplayName(from swarmId: String) -> String {
    let id = swarmId
    if let dashRange = id.range(of: "-", options: .backwards),
       id[dashRange.upperBound...].count <= 10,
       id[dashRange.upperBound...].allSatisfy({ $0.isHexDigit || $0.isLetter }) {
        return String(id[..<dashRange.lowerBound]).capitalized
    }
    return id
}

private func roleIcon(for swarmId: String) -> String {
    let lower = swarmId.lowercased()
    if lower.hasPrefix("explorer") { return "magnifyingglass" }
    if lower.hasPrefix("coder") { return "chevron.left.forwardslash.chevron.right" }
    if lower.hasPrefix("debugger") { return "ladybug" }
    if lower.hasPrefix("reviewer") { return "eye" }
    if lower.hasPrefix("testwriter") || lower.hasPrefix("tester") { return "checkmark.shield" }
    if lower.hasPrefix("docwriter") { return "doc.text" }
    if lower.hasPrefix("securityauditor") || lower.hasPrefix("security") { return "lock.shield" }
    if lower.hasPrefix("skill") { return "sparkle" }
    if lower == "orchestrator" { return "cpu" }
    return "gearshape"
}

private func statusAccentColor(for status: SwarmCardStatus) -> Color {
    switch status {
    case .running: return DesignSystem.Colors.swarmColor
    case .completed: return DesignSystem.Colors.success
    case .failed: return DesignSystem.Colors.error
    case .idle: return .secondary
    }
}

// MARK: - Live Card

/// Compact inline card for a running or recently completed subagent, modeled
/// after the Cursor-style task cards: left accent bar, role icon, live
/// subtitle with shimmer, and an expandable event list.
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

    private var name: String { roleDisplayName(from: card.swarmId) }
    private var icon: String { roleIcon(for: card.swarmId) }
    private var accent: Color { statusAccentColor(for: card.status) }

    private var subtitle: String {
        if card.currentStepTitle.isEmpty || card.currentStepTitle == "Awaiting events" {
            return card.status == .running ? "Working…" : "Done"
        }
        if card.status == .running && card.activeOpsCount == 0 {
            let elapsed = Date().timeIntervalSince(card.lastEventAt ?? .distantPast)
            if elapsed > 2 {
                return "Thinking…"
            }
        }
        return card.currentStepTitle
    }

    private var durationText: String? {
        guard let start = card.startedAt else { return nil }
        let end = card.completedAt ?? Date()
        let seconds = Int(end.timeIntervalSince(start))
        if seconds < 1 { return nil }
        if seconds < 60 { return "\(seconds)s" }
        return "\(seconds / 60)m \(seconds % 60)s"
    }

    var body: some View {
        HStack(spacing: 0) {
            // Left accent bar
            RoundedRectangle(cornerRadius: 1.5)
                .fill(accent)
                .frame(width: 3)
                .padding(.vertical, 4)

            VStack(alignment: .leading, spacing: 0) {
                // Header row
                HStack(spacing: 6) {
                    Image(systemName: icon)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(accent)
                        .frame(width: 14, height: 14)

                    Text(name)
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    Spacer(minLength: 4)

                    if card.errorCount > 0 {
                        HStack(spacing: 2) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 8))
                            Text("\(card.errorCount)")
                                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                        }
                        .foregroundStyle(DesignSystem.Colors.error)
                    }

                    if card.status == .running {
                        ProgressView()
                            .controlSize(.mini)
                            .scaleEffect(0.7)
                            .frame(width: 12, height: 12)
                    } else {
                        Image(systemName: card.status == .completed ? "checkmark.circle.fill" : card.status == .failed ? "xmark.circle.fill" : "circle")
                            .font(.system(size: 10))
                            .foregroundStyle(accent.opacity(0.8))
                    }

                    Button {
                        withAnimation(.snappy(duration: 0.2)) {
                            isExpanded.toggle()
                        }
                    } label: {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(.tertiary)
                            .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    }
                    .buttonStyle(.plain)
                }

                // Subtitle row
                HStack(spacing: 4) {
                    Text(subtitle)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .textShimmer(active: card.status == .running)

                    Spacer(minLength: 0)

                    if let dur = durationText {
                        Text(dur)
                            .font(.system(size: 9, weight: .medium, design: .monospaced))
                            .foregroundStyle(.quaternary)
                    }
                }
                .padding(.top, 2)

                // Expanded event list
                if isExpanded {
                    expandedContent
                        .padding(.top, 6)
                }
            }
            .padding(.leading, 8)
            .padding(.vertical, 7)
            .padding(.trailing, 8)
        }
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.35))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(DesignSystem.Colors.border.opacity(0.4), lineWidth: 0.5)
        )
        .contentShape(RoundedRectangle(cornerRadius: 8))
        .onTapGesture {
            withAnimation(.snappy(duration: 0.2)) {
                isExpanded.toggle()
            }
        }
    }

    // MARK: - Expanded

    private var expandedContent: some View {
        VStack(alignment: .leading, spacing: 3) {
            if !visibleEvents.isEmpty {
                ForEach(visibleEvents) { activity in
                    HStack(spacing: 5) {
                        Circle()
                            .fill(activity.isRunning ? accent : .secondary.opacity(0.5))
                            .frame(width: 4, height: 4)
                        Text(activity.title)
                            .font(.system(size: 10))
                            .foregroundStyle(.primary.opacity(0.85))
                            .lineLimit(1)
                            .textShimmer(active: activity.isRunning)
                        Spacer(minLength: 0)
                        Text(activity.timestamp.formatted(date: .omitted, time: .standard))
                            .font(.system(size: 8, design: .monospaced))
                            .foregroundStyle(.quaternary)
                    }
                }
            }

            if let summary = card.summary, !summary.isEmpty {
                Text(summary)
                    .font(.system(size: 9.5))
                    .foregroundStyle(.tertiary)
                    .lineLimit(3)
                    .padding(.top, 2)
            }

            HStack {
                Spacer()
                Button {
                    onOpenInPanel()
                } label: {
                    HStack(spacing: 3) {
                        Text("Open in Panel")
                            .font(.system(size: 9.5, weight: .medium))
                        Image(systemName: "arrow.up.right.square")
                            .font(.system(size: 8.5))
                    }
                    .foregroundStyle(accent)
                }
                .buttonStyle(.plain)
            }
            .padding(.top, 2)
        }
    }
}

// MARK: - Snapshot Card

/// Static card for persisted subagent snapshots shown in chat history after task completes.
struct SubagentSnapshotCardView: View {
    let snapshot: SubagentCardSnapshot

    private var name: String { roleDisplayName(from: snapshot.swarmId) }
    private var icon: String { roleIcon(for: snapshot.swarmId) }
    private var accent: Color { statusAccentColor(for: snapshot.status) }

    var body: some View {
        HStack(spacing: 0) {
            RoundedRectangle(cornerRadius: 1.5)
                .fill(accent)
                .frame(width: 3)
                .padding(.vertical, 4)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Image(systemName: icon)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(accent)
                        .frame(width: 14, height: 14)

                    Text(name)
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    Spacer(minLength: 4)

                    if snapshot.errorCount > 0 {
                        HStack(spacing: 2) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 8))
                            Text("\(snapshot.errorCount)")
                                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                        }
                        .foregroundStyle(DesignSystem.Colors.error)
                    }

                    Image(systemName: snapshot.status == .completed ? "checkmark.circle.fill" : snapshot.status == .failed ? "xmark.circle.fill" : "circle")
                        .font(.system(size: 10))
                        .foregroundStyle(accent.opacity(0.8))
                }

                Text(snapshot.title)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                if let summary = snapshot.summary, !summary.isEmpty {
                    Text(summary)
                        .font(.system(size: 9.5))
                        .foregroundStyle(.tertiary)
                        .lineLimit(2)
                }
            }
            .padding(.leading, 8)
            .padding(.vertical, 7)
            .padding(.trailing, 8)
        }
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.35))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(DesignSystem.Colors.border.opacity(0.4), lineWidth: 0.5)
        )
    }
}
