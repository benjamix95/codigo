import SwiftUI
import CoderEngine

extension CodeReviewPanelView {
    // MARK: - Review Actions Bar

    @ViewBuilder
    func reviewActionsBar(
        findings: [CodeReviewFinding],
        onApplyAll: @escaping () -> Void,
        onDismissAll: @escaping () -> Void,
        onReReview: @escaping () -> Void,
        onExport: @escaping () -> Void
    ) -> some View {
        let openFindings = findings.filter { $0.status == .open }
        let hasFixableFindings = !openFindings.isEmpty

        VStack(spacing: 6) {
            // Stats row
            if !findings.isEmpty {
                reviewStatsRow(findings)
            }

            // Action buttons
            HStack(spacing: 6) {
                if hasFixableFindings {
                    actionButton(
                        title: "Apply All Fixes",
                        icon: "wrench.and.screwdriver.fill",
                        color: accent,
                        action: onApplyAll
                    )
                }

                if !openFindings.isEmpty {
                    actionButton(
                        title: "Dismiss All",
                        icon: "xmark.circle.fill",
                        color: .secondary,
                        action: onDismissAll
                    )
                }

                actionButton(
                    title: "Re-Review",
                    icon: "arrow.clockwise",
                    color: DesignSystem.Colors.info,
                    action: onReReview
                )

                actionButton(
                    title: "Export",
                    icon: "square.and.arrow.up",
                    color: .secondary,
                    action: onExport
                )
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .disabled(isTaskRunning)
        .opacity(isTaskRunning ? 0.72 : 1)
    }

    // MARK: - Stats Row

    private func reviewStatsRow(_ findings: [CodeReviewFinding]) -> some View {
        let open = findings.filter { $0.status == .open }.count
        let fixed = findings.filter { $0.status == .fixApplied }.count
        let dismissed = findings.filter { $0.status == .dismissed || $0.status == .wontFix }.count

        return HStack(spacing: 12) {
            statPill(label: "Open", count: open, color: accent)
            statPill(label: "Fixed", count: fixed, color: DesignSystem.Colors.success)
            statPill(label: "Dismissed", count: dismissed, color: .secondary)
            Spacer()
            Text("\(findings.count) total")
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .foregroundStyle(.quaternary)
        }
    }

    private func statPill(label: String, count: Int, color: Color) -> some View {
        HStack(spacing: 3) {
            Circle()
                .fill(color)
                .frame(width: 4, height: 4)
            Text("\(count)")
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundStyle(color)
            Text(label)
                .font(.system(size: 8, weight: .medium))
                .foregroundStyle(.tertiary)
        }
    }

    // MARK: - Action Button

    private func actionButton(
        title: String,
        icon: String,
        color: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 3) {
                Image(systemName: icon)
                    .font(.system(size: 8, weight: .semibold))
                Text(title)
                    .font(.system(size: 9, weight: .medium))
            }
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color.opacity(0.1), in: Capsule())
            .overlay(
                Capsule()
                    .strokeBorder(color.opacity(0.2), lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
    }
}
