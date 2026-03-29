import SwiftUI

extension ChatComposerView {
    var frozenTimerForegroundStyle: Color {
        switch frozenTimerTone {
        case .success:
            return DesignSystem.Colors.success.opacity(0.95)
        case .error:
            return DesignSystem.Colors.error.opacity(0.95)
        case .neutral:
            return .secondary
        }
    }

    var frozenTimerBackgroundStyle: Color {
        switch frozenTimerTone {
        case .success:
            return DesignSystem.Colors.success.opacity(0.12)
        case .error:
            return DesignSystem.Colors.error.opacity(0.12)
        case .neutral:
            return Color.white.opacity(0.08)
        }
    }

    @ViewBuilder
    var runtimeTimerLabel: some View {
        if let startDate = runtimeTaskStartDate {
            ElapsedTimerView(startDate: startDate) { elapsed in
                Text(formatElapsed(elapsed))
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 36, alignment: .trailing)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .background(Color.white.opacity(0.08), in: Capsule())
            }
        } else if let frozenTimerText {
            if frozenTimerDismissible {
                Button {
                    onDismissFrozenTimer()
                } label: {
                    frozenTimerChip(text: frozenTimerText)
                }
                .buttonStyle(.plain)
                .help("Hide timer")
            } else {
                frozenTimerChip(text: frozenTimerText)
            }
        }
    }

    func frozenTimerChip(text: String) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold, design: .monospaced))
            .foregroundStyle(frozenTimerForegroundStyle)
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(frozenTimerBackgroundStyle, in: Capsule())
    }
}
