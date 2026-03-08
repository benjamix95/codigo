import SwiftUI

extension MessageToolTraceView {
    // MARK: - Header

    func headerView(derived: DerivedState) -> some View {
        Button {
            onInteractionStart?()
            withAnimation(.easeOut(duration: 0.15)) {
                isExpanded.toggle()
                if isExpanded { userDidManuallyExpand = true }
                if !isExpanded {
                    userDidManuallyExpand = false
                    expandedIds.removeAll()
                    expandedFileIds.removeAll()
                    isCompactDiffExpanded = false
                }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(DesignSystem.Colors.textTertiary)
                    .frame(width: 12)

                if derived.hasRunningEvent {
                    ProgressView()
                        .controlSize(.mini)
                        .scaleEffect(0.7)
                        .frame(width: 12, height: 12)
                } else if derived.errorCount > 0 {
                    Image(systemName: "xmark.octagon.fill")
                        .font(.system(size: 10))
                    .foregroundStyle(DesignSystem.Colors.error)
                } else if derived.warningCount > 0 {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(DesignSystem.Colors.warning)
                } else {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(DesignSystem.Colors.success.opacity(0.7))
                }

                Text(headerTitle(derived: derived))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(DesignSystem.Colors.textSecondary)

                Spacer(minLength: 0)

                if derived.fileAddedTotal > 0 || derived.fileRemovedTotal > 0 {
                    HStack(spacing: 3) {
                        Text("+\(derived.fileAddedTotal)")
                            .foregroundStyle(DesignSystem.Colors.success)
                        Text("-\(derived.fileRemovedTotal)")
                            .foregroundStyle(DesignSystem.Colors.error)
                    }
                    .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                }

                if derived.totalDurationMs > 0 && !derived.hasRunningEvent {
                    Text(formatDuration(derived.totalDurationMs))
                        .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                        .foregroundStyle(DesignSystem.Colors.textQuaternary)
                }
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHoveringHeader = $0 }
        .background(
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(isHoveringHeader ? DesignSystem.Colors.backgroundSecondary.opacity(0.5) : Color.clear)
        )
    }

    var collapseShortcutRow: some View {
        HStack(spacing: 6) {
            Image(systemName: "arrow.up.and.line.horizontal.and.arrow.down")
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(DesignSystem.Colors.textQuaternary)
            Button("Collapse trace") {
                onInteractionStart?()
                withAnimation(.easeOut(duration: 0.12)) {
                    isExpanded = false
                    userDidManuallyExpand = false
                    expandedIds.removeAll()
                    expandedFileIds.removeAll()
                    isCompactDiffExpanded = false
                }
            }
            .buttonStyle(.plain)
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(DesignSystem.Colors.textTertiary)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 6)
    }
    func headerTitle(derived: DerivedState) -> String {
        let count = derived.orderedEvents.count
        if derived.hasRunningEvent {
            return "\(count) \(pluralized("operation", count: count)) running..."
        }
        if !derived.orderedEvents.isEmpty {
            return derived.collapsedSummary
        }
        return "Tool operations"
    }

    // MARK: - Hidden Events

    func hiddenEventsButton(count: Int) -> some View {
        Button {
            withAnimation(.easeOut(duration: 0.15)) {
                isExpanded = true
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "ellipsis")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(DesignSystem.Colors.textQuaternary)
                Text("\(count) more \(pluralized("operation", count: count))")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(DesignSystem.Colors.textTertiary)
            }
            .padding(.vertical, 3)
            .padding(.horizontal, 6)
        }
        .buttonStyle(.plain)
    }
}
