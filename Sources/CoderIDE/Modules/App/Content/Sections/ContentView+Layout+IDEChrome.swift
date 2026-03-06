import SwiftUI

extension ContentView {
    @ViewBuilder
    func ideUnifiedWorkspace(ctx: EffectiveContext, sidePanelWidth: CGFloat) -> some View {
        HStack(spacing: 0) {
            ActivityBarView(
                selectedItem: $activeActivityItem,
                showSettings: $showSettings
            )
            .frame(width: 60)
            .padding(.horizontal, 6)
            .padding(.vertical, 10)

            if let item = activeActivityItem, item != .settings {
                Divider()
                    .overlay(DesignSystem.Colors.borderSubtle.opacity(0.8))
                    .padding(.vertical, 12)

                SidePanelView(
                    activeItem: item,
                    context: projectContextStore.context(id: ctx.contextId)
                )
                .environmentObject(openFilesStore)
                .environmentObject(projectContextStore)
                .environmentObject(gitPanelStore)
                .frame(width: sidePanelWidth)
                .transition(.move(edge: .leading).combined(with: .opacity))

                sidePanelResizeHandle
                    .padding(.vertical, 12)
            }

            Divider()
                .overlay(DesignSystem.Colors.borderSubtle.opacity(0.75))
                .padding(.vertical, 12)

            editorArea
                .layoutPriority(1)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
        .frame(maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(DesignSystem.Colors.backgroundPrimary.opacity(0.95))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(DesignSystem.Colors.borderSubtle.opacity(0.7), lineWidth: 0.6)
        )
        .shadow(color: .black.opacity(0.12), radius: 14, y: 6)
        .animation(.smooth, value: activeActivityItem)
    }

    @ViewBuilder
    func ideSurface<Content: View>(
        tint: Color = .clear,
        @ViewBuilder content: () -> Content
    ) -> some View {
        content()
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(DesignSystem.Colors.backgroundPrimary.opacity(0.96))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .strokeBorder(
                        tint == .clear
                        ? DesignSystem.Colors.borderSubtle.opacity(0.72)
                        : tint.opacity(0.16),
                        lineWidth: 0.6
                    )
            )
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .shadow(color: .black.opacity(0.12), radius: 14, y: 6)
    }

    var ideBackdrop: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.055, green: 0.060, blue: 0.078),
                    Color(red: 0.072, green: 0.078, blue: 0.098)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            RadialGradient(
                colors: [
                    Color(red: 0.16, green: 0.34, blue: 0.56).opacity(0.16),
                    Color.clear
                ],
                center: .topLeading,
                startRadius: 20,
                endRadius: 520
            )
            RadialGradient(
                colors: [
                    Color(red: 0.12, green: 0.44, blue: 0.38).opacity(0.14),
                    Color.clear
                ],
                center: .bottomTrailing,
                startRadius: 20,
                endRadius: 460
            )
        }
        .ignoresSafeArea()
    }
}
