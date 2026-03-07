import CoderEngine
import SwiftUI

/// Collapsible session browser showing available review snapshots.
struct ReviewPanelSessionBrowser: View {
    @ObservedObject var store: CodeReviewPanelStore

    var body: some View {
        let snapshots = store.availableSnapshots
        guard !snapshots.isEmpty else { return AnyView(EmptyView()) }

        return AnyView(
            VStack(spacing: 0) {
                browserToggle(count: snapshots.count)

                if store.sessionBrowserExpanded {
                    Divider().opacity(0.15)
                    sessionList(snapshots)
                }
            }
        )
    }

    // MARK: - Toggle Header

    private func browserToggle(count: Int) -> some View {
        Button {
            withAnimation(.snappy(duration: 0.2)) {
                store.sessionBrowserExpanded.toggle()
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: store.sessionBrowserExpanded
                    ? "chevron.down" : "chevron.right")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(.tertiary)
                    .frame(width: 10)

                Image(systemName: "folder")
                    .font(.system(size: 9))
                    .foregroundStyle(store.accent)

                Text("Sessions")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)

                Spacer()

                Text("\(count)")
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundStyle(.quaternary)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(Color.primary.opacity(0.06), in: Capsule())
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 5)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Session List

    private func sessionList(
        _ snapshots: [CodeReviewSessionSnapshot]
    ) -> some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(spacing: 2) {
                ForEach(snapshots, id: \.sessionId) { snap in
                    sessionRow(snap)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
        }
        .frame(maxHeight: 140)
    }

    private func sessionRow(
        _ snap: CodeReviewSessionSnapshot
    ) -> some View {
        let isSelected = store.selectedSessionId == snap.sessionId

        return Button {
            store.setSelectedSession(snap.sessionId)
        } label: {
            HStack(spacing: 6) {
                phaseIndicator(snap.phase)

                VStack(alignment: .leading, spacing: 1) {
                    Text(snap.sessionId.prefix(12))
                        .font(.system(size: 10, weight: .semibold,
                                      design: .monospaced))
                        .foregroundStyle(.primary.opacity(0.9))
                        .lineLimit(1)

                    HStack(spacing: 4) {
                        Text(snap.phase.rawValue.capitalized)
                            .font(.system(size: 8.5, weight: .medium))
                            .foregroundStyle(.tertiary)

                        if !snap.findings.isEmpty {
                            Text("\(snap.findings.count) findings")
                                .font(.system(size: 8.5, design: .monospaced))
                                .foregroundStyle(.quaternary)
                        }
                    }
                }

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(store.accent)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(isSelected
                        ? store.accent.opacity(0.08)
                        : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(
                        isSelected
                            ? store.accent.opacity(0.25)
                            : Color.clear,
                        lineWidth: 0.5
                    )
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Phase Indicator

    private func phaseIndicator(
        _ phase: ReviewSessionPhase
    ) -> some View {
        Circle()
            .fill(phaseColor(phase))
            .frame(width: 6, height: 6)
    }

    private func phaseColor(
        _ phase: ReviewSessionPhase
    ) -> Color {
        switch phase {
        case .analyzing, .fixing, .testing, .reReviewing:
            return store.accent
        case .completed:
            return DesignSystem.Colors.success
        case .failed:
            return DesignSystem.Colors.error
        case .idle:
            return .secondary
        }
    }
}
