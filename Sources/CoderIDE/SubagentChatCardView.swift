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
/// Dark rounded rectangle with title + subtitle, shimmer overlay when running.
struct SubagentChatCardView: View {
    let card: SwarmLiveCardState
    let onOpenInPanel: () -> Void

    private var title: String {
        let raw = card.currentStepTitle
        if raw.isEmpty || raw == "Awaiting events" {
            return roleDisplayName(from: card.swarmId)
        }
        return raw
    }

    private var subtitle: String {
        if card.status == .running {
            if card.activeOpsCount == 0 {
                let elapsed = Date().timeIntervalSince(card.lastEventAt ?? .distantPast)
                if elapsed > 2 { return "Planning next moves" }
            }
            return "Planning next moves"
        }
        if card.status == .completed { return card.warningCount > 0 ? "Done with warnings" : "Done" }
        if card.status == .failed { return "Failed" }
        if card.warningCount > 0 { return "Warnings" }
        return "Idle"
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
                .textShimmer(active: card.status == .running)
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
        .overlay {
            if card.status == .running {
                ActivityShimmerTrail()
                    .allowsHitTesting(false)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: 12))
        .onTapGesture { onOpenInPanel() }
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
