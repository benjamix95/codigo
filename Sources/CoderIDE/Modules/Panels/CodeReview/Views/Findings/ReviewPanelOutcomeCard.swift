import CoderEngine
import SwiftUI

struct ReviewPanelOutcomeCard: View {
    let outcome: ReviewSessionOutcome

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("OUTCOME")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.tertiary)
                .tracking(0.8)
            Text(outcome.summary)
                .font(.system(size: 10.5, weight: .medium))
            HStack(spacing: 8) {
                pill("Verified", outcome.verifiedFindings)
                pill("FP", outcome.falsePositives)
                pill("Applied", outcome.patchesApplied)
                pill("PR", outcome.prsOpened)
                pill("Merged", outcome.mergedPatches)
            }
            if outcome.manualActionRequired {
                Text("Manual action required")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(DesignSystem.Colors.warning)
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.25))
        )
    }

    private func pill(_ label: String, _ count: Int) -> some View {
        Text("\(label) \(count)")
            .font(.system(size: 8.5, weight: .semibold, design: .monospaced))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(Color.primary.opacity(0.06), in: Capsule())
    }
}
