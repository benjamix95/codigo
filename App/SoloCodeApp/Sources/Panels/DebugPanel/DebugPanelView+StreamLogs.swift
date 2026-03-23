import SwiftUI

extension DebugPanelView {
    // MARK: - Stream Logs Section

    var streamLogsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            streamLogsHeader
            divider.opacity(0.5)
            streamLogsList
        }
        .background(Color.primary.opacity(0.02), in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Color(nsColor: .separatorColor).opacity(0.3), lineWidth: 0.5)
        )
        .padding(.top, 8)
    }

    // MARK: - Header

    private var streamLogsHeader: some View {
        HStack(spacing: 8) {
            Image(systemName: "doc.text")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(DesignSystem.Colors.textSecondary)

            Text("Debug Logs")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(DesignSystem.Colors.textPrimary)

            streamLogBadge

            Spacer()

            streamLogClearButton
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private var streamLogBadge: some View {
        if debugStore.streamLogNewCount > 0 {
            Text("+\(debugStore.streamLogNewCount)")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(DesignSystem.Colors.success)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(DesignSystem.Colors.success.opacity(0.12), in: Capsule())
                .transition(.scale.combined(with: .opacity))
                .animation(.spring(response: 0.25, dampingFraction: 0.8), value: debugStore.streamLogNewCount)
        }
    }

    private var streamLogClearButton: some View {
        Button {
            withAnimation(.easeOut(duration: 0.15)) {
                debugStore.clearStreamLogs()
            }
        } label: {
            HStack(spacing: 3) {
                Text("Clear")
                    .font(.system(size: 10, weight: .medium))
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 7))
            }
            .foregroundStyle(DesignSystem.Colors.textTertiary)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Log Rows

    private var streamLogsList: some View {
        let entries = debugStore.streamLogs.suffix(100)
        return Group {
            if entries.isEmpty {
                streamLogsEmpty
            } else {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(entries)) { entry in
                        streamLogRow(entry)
                    }
                }
            }
        }
    }

    private var streamLogsEmpty: some View {
        HStack(spacing: 6) {
            Image(systemName: "waveform.slash")
                .font(.system(size: 10))
            Text("Nessun log stream")
                .font(.system(size: 10))
        }
        .foregroundStyle(DesignSystem.Colors.textTertiary)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
    }

    private func streamLogRow(_ entry: DebugStreamLogEntry) -> some View {
        HStack(spacing: 16) {
            Text(timeString(entry.timestamp))
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(DesignSystem.Colors.textQuaternary)
                .frame(width: 60, alignment: .leading)

            Text(entry.message)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(DesignSystem.Colors.textSecondary)
                .lineLimit(1)

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 3)
    }
}
