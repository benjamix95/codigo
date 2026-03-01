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

// MARK: - Live Card

/// Minimal inline card for a running or recently completed subagent.
/// Dark rounded rectangle with title + subtitle, text shimmer on subtitle when running.
/// Hover reveals Stop button and expand chevron; expand shows recent events.
struct SubagentChatCardView: View {
    let card: SwarmLiveCardState
    let onOpenInPanel: () -> Void
    var onStop: (() -> Void)? = nil

    @State private var isHovered = false
    @State private var isExpanded = false

    private var title: String {
        let raw = card.currentStepTitle
        if raw.isEmpty || raw == "Awaiting events" {
            return roleDisplayName(from: card.swarmId)
        }
        return raw
    }

    private var subtitle: String {
        if card.status == .running {
            if let live = liveRunningSubtitle() {
                return live
            }
            return "Planning next moves"
        }
        if card.status == .completed { return card.warningCount > 0 ? "Done with warnings" : "Done" }
        if card.status == .failed { return "Failed" }
        if card.warningCount > 0 { return "Warnings" }
        return "Idle"
    }

    private func liveRunningSubtitle() -> String? {
        let candidates: [String?] = [
            card.currentDetail,
            card.recentEvents.last?.detail,
            card.recentEvents.last?.payload["detail"],
            card.recentEvents.last?.payload["query"],
            card.recentEvents.last?.payload["path"],
            card.recentEvents.last?.payload["command"],
            card.recentEvents.last?.payload["tool"],
            card.recentEvents.last?.payload["mcp_tool"],
        ]
        for candidate in candidates {
            let text = (candidate ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }
            let lower = text.lowercased()
            if lower == "started" || lower == "running" || lower == "in_progress" || lower == "pending" {
                continue
            }
            if text == title { continue }
            return String(text.prefix(120))
        }
        return nil
    }

    private var visibleEvents: [TaskActivity] {
        card.recentEvents
            .filter { TaskActivityStore.isConcreteVisibleEvent($0) }
            .suffix(15)
            .map { $0 }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.primary.opacity(0.7))
                        .lineLimit(1)
                        .truncationMode(.tail)

                    Text(subtitle)
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(.secondary.opacity(0.6))
                        .lineLimit(1)
                        .textShimmer(active: card.status == .running)
                }

                Spacer(minLength: 0)

                if isHovered || isExpanded {
                    HStack(spacing: 10) {
                        if card.status == .running, let onStop {
                            Button {
                                onStop()
                            } label: {
                                Text("Stop")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                        }

                        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.quaternary)
                    }
                    .transition(.opacity.combined(with: .scale(scale: 0.9)))
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)

            // Expanded events
            if isExpanded, !visibleEvents.isEmpty {
                Divider()
                    .opacity(0.15)
                    .padding(.horizontal, 12)

                VStack(alignment: .leading, spacing: 3) {
                    ForEach(visibleEvents) { activity in
                        eventRow(activity)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.15))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(
                    Color.white.opacity(isHovered || isExpanded ? 0.14 : 0.08),
                    lineWidth: 1
                )
        )
        .contentShape(RoundedRectangle(cornerRadius: 12))
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) { isHovered = hovering }
        }
        .onTapGesture {
            withAnimation(.snappy(duration: 0.2)) { isExpanded.toggle() }
        }
    }

    // MARK: - Event Row

    @ViewBuilder
    private func eventRow(_ activity: TaskActivity) -> some View {
        let isLast = activity.id == visibleEvents.last?.id
        HStack(spacing: 6) {
            Image(systemName: eventIcon(for: activity))
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(
                    activity.isRunning
                        ? phaseColor(for: activity)
                        : .secondary.opacity(0.5)
                )
                .frame(width: 14, alignment: .center)

            Text(activity.title)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(activity.isRunning ? Color.primary.opacity(0.8) : Color.secondary.opacity(0.7))
                .lineLimit(1)
                .truncationMode(.tail)
                .textShimmer(active: activity.isRunning && isLast)
        }
        .padding(.vertical, 2)
    }

    private func phaseColor(for activity: TaskActivity) -> Color {
        switch activity.phase {
        case .executing: return DesignSystem.Colors.warning
        case .editing: return DesignSystem.Colors.info
        case .searching: return DesignSystem.Colors.swarmColor
        case .planning: return DesignSystem.Colors.planColor
        case .thinking: return DesignSystem.Colors.swarmColor
        }
    }

    private func eventIcon(for activity: TaskActivity) -> String {
        switch activity.type {
        case "command_execution", "bash": return "terminal.fill"
        case "file_change", "edit": return "pencil"
        case "mcp_tool_call": return "wrench.and.screwdriver.fill"
        case "web_search", "web_search_started", "web_search_completed": return "magnifyingglass"
        case "web_fetch", "web_fetch_started", "web_fetch_completed": return "globe"
        case "read_batch_started", "read_batch_completed": return "doc.on.doc"
        case "todo_write", "todo_read": return "checklist"
        case "agent": return "person.circle.fill"
        default: return "gearshape.fill"
        }
    }
}

// MARK: - Snapshot Card

/// Static card for persisted subagent snapshots shown in chat history after task completes.
/// Matches the same minimal dark-card design as the live card.
struct SubagentSnapshotCardView: View {
    let snapshot: SubagentCardSnapshot

    private var title: String {
        let raw = snapshot.title
        if raw.isEmpty { return roleDisplayName(from: snapshot.swarmId) }
        return raw
    }

    private var subtitle: String {
        if let warningCount = snapshot.warningCount, warningCount > 0, snapshot.status != .failed {
            return "Done with warnings"
        }
        if let summary = snapshot.summary, !summary.isEmpty { return summary }
        switch snapshot.status {
        case .completed: return "Done"
        case .failed: return "Failed"
        default: return roleDisplayName(from: snapshot.swarmId)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.primary.opacity(0.7))
                .lineLimit(1)
                .truncationMode(.tail)

            Text(subtitle)
                .font(.system(size: 12, weight: .regular))
                .foregroundStyle(.secondary.opacity(0.6))
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.15))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
        )
    }
}
