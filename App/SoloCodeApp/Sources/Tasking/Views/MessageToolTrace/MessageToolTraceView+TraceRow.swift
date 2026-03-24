import SwiftUI

extension MessageToolTraceView {
    // MARK: - Trace Row

    @ViewBuilder
    func traceRow(_ event: ToolTraceEvent, displayIndex: Int, compactMode: Bool, derived: DerivedState) -> some View {
        let isRowExpanded = isExpanded && expandedIds.contains(event.id)
        let isError = Self.isErrorType(event)
        let isWarning = Self.isWarningType(event)
        let durationMs = Int(event.payload["duration_ms"] ?? "") ?? 0

        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 6) {
                toolIcon(for: event)
                    .frame(width: 14, alignment: .center)

                toolTitle(for: event)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(
                        isError
                            ? DesignSystem.Colors.error
                            : (isWarning ? DesignSystem.Colors.warning : .primary)
                    )
                    .lineLimit(1)
                    .textShimmer(active: event.isRunning)

                if let detail = compactDetail(for: event), !compactMode || detail.count < 60 {
                    Text(detail)
                        .font(.system(size: 10.5))
                        .foregroundStyle(DesignSystem.Colors.textTertiary)
                        .lineLimit(1)
                        .textShimmer(active: event.isRunning)
                }

                Spacer(minLength: 0)

                HStack(spacing: 4) {
                    if let counters = editLineCounters(for: event) {
                        Text("+\(counters.added)")
                            .font(.system(size: 9, weight: .semibold, design: .monospaced))
                            .foregroundStyle(DesignSystem.Colors.success)
                        Text("-\(counters.removed)")
                            .font(.system(size: 9, weight: .semibold, design: .monospaced))
                            .foregroundStyle(DesignSystem.Colors.error)
                    }

                    if event.isRunning {
                        ProgressView()
                            .controlSize(.mini)
                            .scaleEffect(0.6)
                            .frame(width: 12, height: 12)
                    } else {
                        if durationMs > 0 {
                            Text(formatDuration(durationMs))
                                .font(.system(size: 9, weight: .medium, design: .monospaced))
                                .foregroundStyle(DesignSystem.Colors.textQuaternary)
                        }
                        if !isError && !isWarning {
                            Text("DONE")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1.5)
                                .background(
                                    Capsule().fill(DesignSystem.Colors.success.opacity(0.75))
                                )
                        }
                    }

                    if !compactMode {
                        Image(systemName: isRowExpanded ? "chevron.down" : "chevron.right")
                            .font(.system(size: 7, weight: .bold))
                            .foregroundStyle(DesignSystem.Colors.textQuaternary)
                    }
                }
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 6)
            .contentShape(Rectangle())
            .onTapGesture {
                guard !compactMode else {
                    withAnimation(.easeOut(duration: 0.15)) { isExpanded = true }
                    return
                }
                withAnimation(.easeInOut(duration: 0.12)) {
                    if isRowExpanded {
                        expandedIds.remove(event.id)
                    } else {
                        expandedIds.insert(event.id)
                    }
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(
                        isError
                            ? DesignSystem.Colors.error.opacity(0.06)
                            : (isWarning
                                ? DesignSystem.Colors.warning.opacity(0.06)
                                : DesignSystem.Colors.toolTraceRowBackground)
                    )
            )

            if isRowExpanded {
                expandedDetails(for: event)
                    .padding(.leading, 20)
                    .padding(.trailing, 6)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(DesignSystem.Colors.backgroundSecondary.opacity(0.3))
                    )
            }
        }
    }
}
