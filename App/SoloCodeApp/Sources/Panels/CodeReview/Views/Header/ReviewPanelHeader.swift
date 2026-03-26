import CoderEngine
import SwiftUI

/// Top bar for the Code Review Panel with title, mode badge, timer, and close button.
struct ReviewPanelHeader: View {
    @ObservedObject var store: CodeReviewPanelStore
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !ReviewCoreBridge.isEnabled {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.orange)
                    Text(ReviewCoreBridge.userFacingDisabledReason())
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.orange.opacity(0.12))
            }

            HStack(spacing: 8) {
            // Icon & title
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(store.accent)

            Text("Code Review")
                .font(.system(size: 13, weight: .semibold))

            // Round info
            if let ri = store.computeMetrics().roundInfo, store.isRunning {
                Text("Round \(ri.round)/\(ri.maxRounds)")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(store.accent))
            }

            // Active count badge
            let m = store.computeMetrics()
            if m.activeCount > 0 {
                Text("\(m.activeCount) active")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(store.accent)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(store.accent.opacity(0.12), in: Capsule())
            }

            Spacer()

            // Timer
            timerView

            // Spinner
            if store.isRunning {
                ProgressView().controlSize(.mini)
            }

            // Close
            Button { onClose() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 20, height: 20)
                    .background(Color.primary.opacity(0.06), in: Circle())
            }
            .buttonStyle(.plain)
            .help("Close panel")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
    }

    // MARK: - Timer

    @ViewBuilder
    private var timerView: some View {
        if let startDate = store.runStartedAt, store.isRunning {
            ElapsedTimerView(startDate: startDate) { elapsed in
                Text(formatElapsed(elapsed))
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Color.white.opacity(0.08), in: Capsule())
            }
        } else if let frozen = store.frozenTimerText {
            Text(frozen)
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundStyle(.quaternary)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(Color.white.opacity(0.04), in: Capsule())
        }
    }

    // MARK: - Timer Format

    private func formatElapsed(_ seconds: Int) -> String {
        let minutes = seconds / 60
        let remainder = seconds % 60
        return String(format: "%d:%02d", minutes, remainder)
    }
}
