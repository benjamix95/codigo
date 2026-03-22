import SwiftUI
import CoderEngine

extension DebugPanelView {
    // MARK: - Divider

    var divider: some View {
        Rectangle()
            .fill(DesignSystem.Colors.borderSubtle)
            .frame(height: 0.5)
    }

    // MARK: - Header

    var header: some View {
        HStack(spacing: 10) {
            HStack(spacing: 6) {
                ZStack {
                    Circle()
                        .fill(accent.opacity(0.12))
                        .frame(width: 24, height: 24)
                    Image(systemName: "ladybug.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(accent)
                }

                Text("Debug")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(DesignSystem.Colors.textPrimary)
            }

            if debugStore.phase.isActive {
                phaseChip(debugStore.phase)
                    .transition(.scale.combined(with: .opacity))
            }

            Spacer()

            headerBadges

            headerActions
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    var headerBadges: some View {
        HStack(spacing: 4) {
            if debugStore.openFindingsCount > 0 {
                counterBadge(count: debugStore.openFindingsCount, color: accent, icon: "magnifyingglass.circle.fill")
            }
            if debugStore.errorCount > 0 {
                counterBadge(count: debugStore.errorCount, color: DesignSystem.Colors.error, icon: "xmark.circle.fill")
            }
            if debugStore.warningCount > 0 {
                counterBadge(count: debugStore.warningCount, color: DesignSystem.Colors.warning, icon: "exclamationmark.triangle.fill")
            }
        }
    }

    func counterBadge(count: Int, color: Color, icon: String) -> some View {
        HStack(spacing: 3) {
            Image(systemName: icon)
                .font(.system(size: 8))
            Text("\(count)")
                .font(.system(size: 9, weight: .bold, design: .monospaced))
        }
        .foregroundStyle(color)
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(color.opacity(0.1), in: Capsule())
    }

    var headerActions: some View {
        HStack(spacing: 2) {
            if debugStore.phase.isActive {
                headerButton(icon: "stop.fill", color: accent) {
                    onStop()
                }
                .help("Stop debug session")
            }

            headerButton(icon: "trash", color: .secondary) {
                debugStore.resetSession()
            }
            .help("Reset debug session")

            headerButton(icon: "xmark", color: .secondary) {
                onClose()
            }
            .help("Close (Cmd+Shift+D)")
        }
    }

    func headerButton(icon: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(color)
                .frame(width: 24, height: 24)
                .background(color.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
    }

    func phaseChip(_ phase: DebugFlowPhase) -> some View {
        Text(phase.label.uppercased())
            .font(.system(size: 9, weight: .bold, design: .monospaced))
            .foregroundStyle(accent)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(accent.opacity(0.1), in: Capsule())
    }
}
