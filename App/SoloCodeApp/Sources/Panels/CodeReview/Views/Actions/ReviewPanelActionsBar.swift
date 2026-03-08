import CoderEngine
import SwiftUI

/// Bottom actions bar for the Findings tab with bulk actions.
struct ReviewPanelActionsBar: View {
    @ObservedObject var store: CodeReviewPanelStore

    var body: some View {
        let findings = store.currentFindings
        let openCount = findings.filter { $0.status == .open }.count
        let fixedCount = findings.filter { $0.status.isAppliedState }.count

        HStack(spacing: 8) {
            // Stats
            statsView(open: openCount, fixed: fixedCount, total: findings.count)

            Spacer()

            // Bulk actions (only when session available and not running)
            if let sessionId = store.selectedSessionId, openCount > 0 {
                applyAllButton(sessionId: sessionId, count: openCount)
                dismissAllButton(sessionId: sessionId, count: openCount)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .disabled(store.isRunning)
        .opacity(store.isRunning ? 0.7 : 1)
    }

    // MARK: - Stats

    private func statsView(open: Int, fixed: Int, total: Int) -> some View {
        HStack(spacing: 6) {
            statPill(label: "Open", count: open, color: DesignSystem.Colors.reviewColor)
            statPill(label: "Fixed", count: fixed, color: DesignSystem.Colors.success)
            Text("\(total) total")
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .foregroundStyle(.quaternary)
        }
    }

    private func statPill(label: String, count: Int, color: Color) -> some View {
        HStack(spacing: 3) {
            Circle().fill(color).frame(width: 5, height: 5)
            Text("\(count)")
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundStyle(color)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(color.opacity(0.08), in: Capsule())
    }

    // MARK: - Bulk Actions

    private func applyAllButton(sessionId: String, count: Int) -> some View {
        let openIds = store.currentFindings
            .filter { $0.status == .open }
            .map(\.id)
        return Button {
            Task { await store.applyAllFixes(sessionId: sessionId, findingIds: openIds) }
        } label: {
            HStack(spacing: 3) {
                Image(systemName: "wrench.and.screwdriver")
                    .font(.system(size: 8))
                Text("Fix All (\(count))")
                    .font(.system(size: 9, weight: .semibold))
            }
            .foregroundStyle(store.accent)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                store.accent.opacity(0.1),
                in: RoundedRectangle(cornerRadius: 6, style: .continuous)
            )
        }
        .buttonStyle(.plain)
    }

    private func dismissAllButton(sessionId: String, count: Int) -> some View {
        let openIds = store.currentFindings
            .filter { $0.status == .open }
            .map(\.id)
        return Button {
            Task {
                await store.dismissAll(
                    sessionId: sessionId,
                    findingIds: openIds,
                    reason: "bulk dismissed"
                )
            }
        } label: {
            HStack(spacing: 3) {
                Image(systemName: "xmark.circle")
                    .font(.system(size: 8))
                Text("Dismiss All")
                    .font(.system(size: 9, weight: .medium))
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Color.primary.opacity(0.04),
                in: RoundedRectangle(cornerRadius: 6, style: .continuous)
            )
        }
        .buttonStyle(.plain)
    }
}
