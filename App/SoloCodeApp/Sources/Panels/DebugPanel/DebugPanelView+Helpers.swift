import SwiftUI

extension DebugPanelView {
    func emptyState(icon: String, title: String, subtitle: String) -> some View {
        VStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(Color.primary.opacity(0.03))
                    .frame(width: 48, height: 48)
                Image(systemName: icon)
                    .font(.system(size: 20))
                    .foregroundStyle(DesignSystem.Colors.textTertiary)
            }

            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(DesignSystem.Colors.textSecondary)

            Text(subtitle)
                .font(.system(size: 10.5))
                .foregroundStyle(DesignSystem.Colors.textTertiary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 200)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 36)
    }

    func timeString(_ date: Date) -> String {
        DebugTimeFormatters.hms.string(from: date)
    }

    func sectionHeader(_ title: String, icon: String, count: Int = 0) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(accent)
            Text(title.uppercased())
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(DesignSystem.Colors.textSecondary)
                .tracking(0.5)

            if count > 0 {
                Text("\(count)")
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .foregroundStyle(accent)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(accent.opacity(0.12), in: Capsule())
            }

            Spacer()
        }
        .padding(.top, 12)
        .padding(.bottom, 4)
    }
}

private enum DebugTimeFormatters {
    static let hms: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()
}
