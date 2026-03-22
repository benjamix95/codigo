import SwiftUI
import CoderEngine

extension SidebarView {
    var footer: some View {
        HStack(spacing: DesignSystem.Spacing.sm) {
            ProfileSwitcherView()

            Spacer()

            Button { showSettings = true } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(DesignSystem.Colors.textTertiary)
                    .frame(width: 24, height: 24)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.white.opacity(0.04))
                    )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Settings")
        }
        .padding(.horizontal, DesignSystem.Sidebar.insetMD)
        .padding(.vertical, DesignSystem.Spacing.sm)
        .frame(maxWidth: .infinity)
        .background(
            VStack(spacing: 0) {
                Rectangle()
                    .fill(Color.white.opacity(0.04))
                    .frame(height: 0.5)
                Color.clear
            }
        )
        .onReceive(NotificationCenter.default.publisher(for: .openSettingsToAccounts)) { _ in
            showSettings = true
        }
    }
}
