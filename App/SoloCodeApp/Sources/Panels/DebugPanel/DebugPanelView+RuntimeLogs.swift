import SwiftUI
import CoderEngine

extension DebugPanelView {
    // MARK: - Runtime Logs

    var runtimeLogsContent: some View {
        let runtimeEntries = debugStore.currentRunId == nil
            ? debugStore.runtimeLogs
            : debugStore.currentRunLogs

        return Group {
            if !runtimeEntries.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    if let runId = debugStore.currentRunId {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(accent)
                                .frame(width: 6, height: 6)
                            Text("Run \(runId.prefix(8))…")
                                .font(.system(size: 10, weight: .medium, design: .monospaced))
                                .foregroundStyle(DesignSystem.Colors.textSecondary)
                            Spacer()
                            Text("\(debugStore.currentRunLogs.count) entries")
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundStyle(DesignSystem.Colors.textTertiary)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(accent.opacity(0.04), in: RoundedRectangle(cornerRadius: 6))
                    }

                    ForEach(runtimeEntries) { entry in
                        runtimeLogRow(entry)
                    }
                }
            }
        }
    }

    func runtimeLogRow(_ entry: RuntimeLogEntry) -> some View {
        let isExpanded = expandedRuntimeLogId == entry.id

        return VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.spring(response: 0.2, dampingFraction: 0.85)) {
                    expandedRuntimeLogId = isExpanded ? nil : entry.id
                }
            } label: {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "waveform")
                        .font(.system(size: 9))
                        .foregroundStyle(accent.opacity(0.6))
                        .frame(width: 14)
                        .padding(.top, 2)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(entry.message)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(DesignSystem.Colors.textPrimary)
                            .lineLimit(isExpanded ? nil : 2)

                        HStack(spacing: 6) {
                            Text(entry.location)
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundStyle(DesignSystem.Colors.textTertiary)

                            if let hid = entry.hypothesisId {
                                Text("H:\(hid.prefix(6))")
                                    .font(.system(size: 8, weight: .medium, design: .monospaced))
                                    .foregroundStyle(DesignSystem.Colors.warning)
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 1)
                                    .background(DesignSystem.Colors.warning.opacity(0.1), in: Capsule())
                            }

                            Spacer()

                            Text(timeString(entry.timestamp))
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundStyle(DesignSystem.Colors.textQuaternary)
                        }
                    }
                }
                .padding(.vertical, 5)
                .padding(.horizontal, 6)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded && !entry.data.isEmpty {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(entry.data.sorted(by: { $0.key < $1.key }), id: \.key) { key, value in
                        HStack(spacing: 4) {
                            Text(key)
                                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                                .foregroundStyle(accent)
                            Text("=")
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundStyle(DesignSystem.Colors.textTertiary)
                            Text(value)
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundStyle(DesignSystem.Colors.textSecondary)
                                .lineLimit(3)
                        }
                    }
                }
                .padding(.leading, 22)
                .padding(.vertical, 6)
                .padding(.horizontal, 8)
                .background(accent.opacity(0.03), in: RoundedRectangle(cornerRadius: 6))
                .padding(.bottom, 4)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }

            divider.opacity(0.5)
        }
    }
}
