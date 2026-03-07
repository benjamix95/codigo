import AppKit
import SwiftUI
import UniformTypeIdentifiers
import CoderEngine

extension ContentView {
    @ViewBuilder
    func ideModeContent(detailWidth: CGFloat) -> some View {
        let ctx = effectiveContext(
            for: selectedConversationId,
            chatStore: chatStore,
            projectContextStore: projectContextStore,
            preferActiveContextForGlobalThread: preferActiveContextForGlobalThread
        )
        let chatIsLeft = chatPanelPosition == "left"
        let clampedChatW = ContentPanelWidthPolicy.clampedWidth(
            storedWidth: chatPanelWidth,
            detailWidth: detailWidth,
            fraction: 0.45
        )
        let maxChatW = ContentPanelWidthPolicy.maxWidth(detailWidth: detailWidth, fraction: 0.45)
        let clampedBrowserW = ContentPanelWidthPolicy.clampedWidth(
            storedWidth: browserPanelWidth,
            detailWidth: detailWidth,
            fraction: 0.55
        )
        let maxBrowserW = ContentPanelWidthPolicy.maxWidth(detailWidth: detailWidth, fraction: 0.55)
        let clampedSidePanelW = max(240, min(CGFloat(sidePanelWidth), 380))

        ZStack {
            ideBackdrop

            HStack(spacing: 10) {
                if showChatPanel && chatIsLeft {
                    ideSurface(tint: DesignSystem.Colors.agentColor) {
                        chatPanel
                            .frame(width: clampedChatW)
                    }
                    chatPanelLeadingResizeHandle(clampedWidth: clampedChatW, maxWidth: maxChatW)
                }

                ideUnifiedWorkspace(
                    ctx: ctx,
                    sidePanelWidth: clampedSidePanelW,
                    showsSidebar: showIDEWorkbenchSidebar
                )

                if showBrowserPanel {
                    browserResizeHandle(clampedWidth: clampedBrowserW, maxWidth: maxBrowserW)
                    ideSurface(tint: DesignSystem.Colors.browserColor) {
                        BrowserPanelView(tabManager: browserTabManager)
                            .frame(width: clampedBrowserW)
                    }
                }

                if showChatPanel && !chatIsLeft {
                    chatPanelTrailingResizeHandle(clampedWidth: clampedChatW, maxWidth: maxChatW)
                    ideSurface(tint: DesignSystem.Colors.agentColor) {
                        chatPanel
                            .frame(width: clampedChatW)
                    }
                }
            }
            .padding(10)
        }
        .frame(maxWidth: CGFloat.infinity, maxHeight: CGFloat.infinity)
    }

    @ViewBuilder
    func browserModeContent(detailWidth: CGFloat) -> some View {
        let clampedBrowserW = ContentPanelWidthPolicy.clampedWidth(
            storedWidth: browserPanelWidth,
            detailWidth: detailWidth,
            fraction: 0.65
        )
        let maxBrowserW = ContentPanelWidthPolicy.maxWidth(detailWidth: detailWidth, fraction: 0.65)

        HStack(spacing: 0) {
            chatPanel
                .frame(maxWidth: CGFloat.infinity, maxHeight: CGFloat.infinity)
                .layoutPriority(1)

            if showBrowserPanel {
                browserResizeHandle(clampedWidth: clampedBrowserW, maxWidth: maxBrowserW, leading: true)
                BrowserPanelView(tabManager: browserTabManager)
                    .frame(width: clampedBrowserW)
            }
        }
        .frame(maxWidth: CGFloat.infinity, maxHeight: CGFloat.infinity)
    }

    var fallbackModeContent: some View {
        chatPanel
            .frame(maxWidth: CGFloat.infinity, maxHeight: CGFloat.infinity)
    }
}
