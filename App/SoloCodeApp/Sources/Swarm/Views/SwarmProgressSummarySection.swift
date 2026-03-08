import SwiftUI

struct SwarmProgressSummarySection: View {
    let metrics: SwarmProgressMetrics

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(metrics.progressLabel)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.primary.opacity(0.9))
                Spacer(minLength: 8)
                if let summaryLabel = metrics.summaryLabel {
                    Text(summaryLabel)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            GeometryReader { proxy in
                let width = max(proxy.size.width, 0)
                let fillWidth = width * metrics.progressFraction

                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.primary.opacity(0.08))
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [
                                    DesignSystem.Colors.swarmColor.opacity(0.92),
                                    DesignSystem.Colors.success.opacity(0.88),
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: fillWidth)
                }
            }
            .frame(height: 6)
        }
    }
}

struct SwarmStepSyncPlaceholder: View {
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "ellipsis.circle")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.tertiary)
            Text("Syncing pipeline step details…")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.tertiary)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Color.primary.opacity(0.03))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(DesignSystem.Colors.borderSubtle.opacity(0.78), lineWidth: 1)
        }
    }
}
