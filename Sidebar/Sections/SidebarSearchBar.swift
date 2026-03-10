import SwiftUI

/// Inline search bar — no box, just a flat row integrated into the sidebar flow.
struct SidebarSearchBar: View {
    @Binding var query: String

    var body: some View {
        HStack(spacing: DesignSystem.Spacing.sm - 2) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(DesignSystem.Colors.textQuaternary)

            TextField("Search threads...", text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: 11))

            if !query.isEmpty {
                Button { query = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(DesignSystem.Colors.textTertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            } else {
                Text("⌘K")
                    .font(.system(size: 9, weight: .medium, design: .rounded))
                    .foregroundStyle(DesignSystem.Colors.textQuaternary)
                    .padding(.horizontal, DesignSystem.Spacing.xs)
                    .padding(.vertical, 1)
                    .background(
                        Color.white.opacity(0.04),
                        in: RoundedRectangle(cornerRadius: 3)
                    )
            }
        }
        .padding(.vertical, DesignSystem.Spacing.xs)
    }
}
