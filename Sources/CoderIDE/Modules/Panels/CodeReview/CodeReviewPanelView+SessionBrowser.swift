import CoderEngine
import SwiftUI

extension CodeReviewPanelView {
    @ViewBuilder
    var sessionBrowserCard: some View {
        let snapshots = taskActivityStore.codeReviewSnapshots(for: conversationId)
        let selectedSessionId = taskActivityStore.selectedCodeReviewSessionId(for: conversationId)
        if snapshots.isEmpty {
            EmptyView()
        } else {
            VStack(spacing: 0) {
                Button {
                    withAnimation(.snappy(duration: 0.18)) {
                        sessionBrowserExpanded.toggle()
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "square.stack.3d.up")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(accent)
                        Text("Review Sessions")
                            .font(.system(size: 10.5, weight: .semibold))
                            .foregroundStyle(.primary)
                        Text("\(snapshots.count)")
                            .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                            .foregroundStyle(accent)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(accent.opacity(0.12), in: Capsule())
                        Spacer()
                        Image(systemName: sessionBrowserExpanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                }
                .buttonStyle(.plain)

                if sessionBrowserExpanded {
                    Divider().opacity(0.2)
                    VStack(spacing: 6) {
                        ForEach(snapshots, id: \.sessionId) { snapshot in
                            reviewSessionRow(
                                snapshot,
                                isSelected: snapshot.sessionId == selectedSessionId
                            )
                        }
                    }
                    .padding(10)
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor).opacity(0.3))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(DesignSystem.Colors.border.opacity(0.35), lineWidth: 0.5)
            )
            .padding(.horizontal, 12)
            .padding(.bottom, 8)
        }
    }

    private func reviewSessionRow(
        _ snapshot: CodeReviewSessionSnapshot,
        isSelected: Bool
    ) -> some View {
        Button {
            taskActivityStore.setSelectedCodeReviewSessionId(snapshot.sessionId, for: conversationId)
        } label: {
            HStack(spacing: 0) {
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(sessionAccent(snapshot))
                    .frame(width: 2.5)
                    .padding(.vertical, 3)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(shortReviewSessionId(snapshot.sessionId))
                            .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                            .foregroundStyle(accent)
                        badge(snapshot.phase.rawValue.replacingOccurrences(of: "_", with: " "), sessionAccent(snapshot))
                        Spacer(minLength: 4)
                        Text("\(snapshot.findings.count) findings")
                            .font(.system(size: 8.5, weight: .medium, design: .monospaced))
                            .foregroundStyle(.quaternary)
                    }

                    Text(snapshot.scope?.description ?? "Unknown scope")
                        .font(.system(size: 9.5))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    HStack(spacing: 8) {
                        Text("stage \(snapshot.stage.rawValue)")
                            .font(.system(size: 8.5, design: .monospaced))
                            .foregroundStyle(.quaternary)
                        Text("round \(snapshot.currentRound)")
                            .font(.system(size: 8.5, design: .monospaced))
                            .foregroundStyle(.quaternary)
                        if snapshot.activeWorkerCount > 0 {
                            Text("\(snapshot.activeWorkerCount) workers")
                                .font(.system(size: 8.5, design: .monospaced))
                                .foregroundStyle(.quaternary)
                        }
                    }
                }
                .padding(.leading, 8)
                .padding(.vertical, 6)
                .padding(.trailing, 8)
            }
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(
                        isSelected
                            ? accent.opacity(0.10)
                            : Color(nsColor: .controlBackgroundColor).opacity(0.25)
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(
                        isSelected ? accent.opacity(0.28) : DesignSystem.Colors.border.opacity(0.28),
                        lineWidth: 0.5
                    )
            )
        }
        .buttonStyle(.plain)
    }

    private func shortReviewSessionId(_ sessionId: String) -> String {
        String(sessionId.prefix(8)).uppercased()
    }

    private func sessionAccent(_ snapshot: CodeReviewSessionSnapshot) -> Color {
        switch snapshot.phase {
        case .failed:
            return DesignSystem.Colors.error
        case .completed:
            return DesignSystem.Colors.success
        case .analyzing, .fixing, .testing, .reReviewing:
            return accent
        case .idle:
            return .secondary
        }
    }
}
