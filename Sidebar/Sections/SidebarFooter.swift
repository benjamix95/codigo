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

    // MARK: - Date Formatting

    private static let relativeDateFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.locale = Locale(identifier: "en_US")
        f.unitsStyle = .short
        return f
    }()

    func relativeDate(_ date: Date, relativeTo referenceDate: Date = Date()) -> String {
        Self.relativeDateFormatter.localizedString(for: date, relativeTo: referenceDate)
    }

    // MARK: - Query Matching

    func matchesQuery(_ conv: Conversation, query: String) -> Bool {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return true }
        return conv.title.lowercased().contains(q)
    }
}
