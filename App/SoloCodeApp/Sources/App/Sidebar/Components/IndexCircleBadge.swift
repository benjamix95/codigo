import SwiftUI
import CoderEngine

// MARK: - IndexCircleBadge

/// Circular progress indicator for codebase indexing.
/// Shows a ring that fills as indexing progresses.
/// At 100% the ring stays solid green with a checkmark.
struct IndexCircleBadge: View {
    let progress: IndexingProgress?

    /// Resolved fraction: 1.0 when indexing is done (progress == nil).
    private var fraction: Double {
        if let progress { return progress.fraction }
        return 1.0
    }

    /// Whether indexing is complete.
    private var isComplete: Bool { progress == nil }

    /// Percentage text for the tooltip.
    private var percentText: String {
        if let progress { return progress.percentText }
        return "100%"
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            // Background ring (track).
            Circle()
                .stroke(
                    isComplete
                        ? DesignSystem.Colors.success.opacity(0.2)
                        : Color.accentColor.opacity(0.15),
                    lineWidth: 2
                )

            // Filled ring (progress).
            Circle()
                .trim(from: 0, to: fraction)
                .stroke(
                    isComplete
                        ? DesignSystem.Colors.success
                        : Color.accentColor,
                    style: StrokeStyle(lineWidth: 2, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(.easeInOut(duration: 0.3), value: fraction)

            // Center content.
            if isComplete {
                Image(systemName: "checkmark")
                    .font(.system(size: 6, weight: .bold))
                    .foregroundStyle(DesignSystem.Colors.success)
            } else {
                Text("\(Int(fraction * 100))")
                    .font(.system(size: 6, weight: .bold, design: .monospaced))
                    .foregroundStyle(Color.accentColor)
                    .minimumScaleFactor(0.5)
            }
        }
        .frame(width: 18, height: 18)
        .help(isComplete ? "Indexed — codebase ready" : "Indexing: \(percentText)")
    }
}
