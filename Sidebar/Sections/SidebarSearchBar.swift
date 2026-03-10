import SwiftUI

/// Pill-shaped search bar with subtle glass background.
struct SidebarSearchBar: View {
    @Binding var query: String
    @State private var isFocused = false

    var body: some View {
        HStack(spacing: DesignSystem.Spacing.sm) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(isFocused ? Color.accentColor.opacity(0.8) : DesignSystem.Colors.textTertiary)

            TextField("Search threads…", text: $query, onEditingChanged: { editing in
                withAnimation(.easeInOut(duration: 0.15)) { isFocused = editing }
            })
            .textFieldStyle(.plain)
            .font(.system(size: 11.5))

            if !query.isEmpty {
                Button {
                    withAnimation(.easeOut(duration: 0.12)) { query = "" }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(DesignSystem.Colors.textTertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
                .transition(.scale.combined(with: .opacity))
            } else {
                Text("⌘K")
                    .font(.system(size: 9, weight: .medium, design: .rounded))
                    .foregroundStyle(DesignSystem.Colors.textQuaternary)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.white.opacity(0.06))
                    )
            }
        }
        .padding(.horizontal, DesignSystem.Spacing.md)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium)
                .fill(Color.white.opacity(isFocused ? 0.07 : 0.04))
                .overlay(
                    RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium)
                        .strokeBorder(
                            isFocused ? Color.accentColor.opacity(0.3) : Color.white.opacity(0.06),
                            lineWidth: 0.5
                        )
                )
        )
        .animation(.easeInOut(duration: 0.15), value: isFocused)
        .animation(.easeInOut(duration: 0.15), value: query.isEmpty)
    }
}
