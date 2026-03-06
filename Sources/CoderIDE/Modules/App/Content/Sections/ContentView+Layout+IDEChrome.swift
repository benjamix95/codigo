import SwiftUI

extension ContentView {
    @ViewBuilder
    func ideWorkbenchColumn(ctx: EffectiveContext, sidePanelWidth: CGFloat) -> some View {
        HStack(spacing: 12) {
            ActivityBarView(
                selectedItem: $activeActivityItem,
                showSettings: $showSettings,
                workspaceTitle: ctx.displayLabel
            )
            .frame(width: 84)

            if let item = activeActivityItem, item != .settings {
                SidePanelView(
                    activeItem: item,
                    context: projectContextStore.context(id: ctx.contextId)
                )
                .environmentObject(openFilesStore)
                .environmentObject(projectContextStore)
                .environmentObject(gitPanelStore)
                .frame(width: sidePanelWidth)
                .transition(.move(edge: .leading).combined(with: .opacity))
            }
        }
        .padding(12)
        .frame(maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            DesignSystem.Colors.backgroundPrimary.opacity(0.96),
                            DesignSystem.Colors.backgroundSecondary.opacity(0.84)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .strokeBorder(DesignSystem.Colors.borderAccent.opacity(0.8), lineWidth: 0.7)
        )
        .shadow(color: .black.opacity(0.18), radius: 18, y: 8)
        .animation(.smooth, value: activeActivityItem)
    }

    @ViewBuilder
    func ideSurface<Content: View>(
        tint: Color = .clear,
        @ViewBuilder content: () -> Content
    ) -> some View {
        content()
            .background(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                DesignSystem.Colors.backgroundPrimary.opacity(0.96),
                                DesignSystem.Colors.backgroundSecondary.opacity(0.86)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .strokeBorder(
                        tint == .clear
                        ? DesignSystem.Colors.borderAccent.opacity(0.72)
                        : tint.opacity(0.18),
                        lineWidth: 0.7
                    )
            )
            .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
            .shadow(color: .black.opacity(0.16), radius: 18, y: 8)
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
