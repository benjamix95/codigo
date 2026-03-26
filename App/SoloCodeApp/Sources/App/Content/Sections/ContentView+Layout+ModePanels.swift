import AppKit
import SwiftUI
import UniformTypeIdentifiers
import CoderEngine

extension ContentView {
    @ViewBuilder
    func ideModeContent(detailWidth: CGFloat) -> some View {
        let ctx = effectiveContext(
            for: panelCoordinator.selectedConversationId,
            chatStore: chatStore,
            projectContextStore: projectContextStore,
            preferActiveContextForGlobalThread: panelCoordinator.preferActiveContextForGlobalThread
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
                if panelCoordinator.showChatPanel && chatIsLeft {
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

                if panelCoordinator.showBrowserPanel {
                    browserResizeHandle(clampedWidth: clampedBrowserW, maxWidth: maxBrowserW)
                    ideSurface(tint: DesignSystem.Colors.browserColor) {
                        BrowserPanelView(tabManager: browserTabManager)
                            .frame(width: clampedBrowserW)
                    }
                }

                if panelCoordinator.showChatPanel && !chatIsLeft {
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
        .onChangeCompat(of: panelCoordinator.showChatPanel) { wasOpen, isOpen in
            guard isOpen && !wasOpen else { return }
            ContentPanelWidthPolicy.snapStoredWidthToOpenMax(
                storedWidth: &chatPanelWidth,
                detailWidth: detailWidth,
                fraction: 0.45
            )
        }
        .onChangeCompat(of: panelCoordinator.showBrowserPanel) { wasOpen, isOpen in
            guard isOpen && !wasOpen else { return }
            ContentPanelWidthPolicy.snapStoredWidthToOpenMax(
                storedWidth: &browserPanelWidth,
                detailWidth: detailWidth,
                fraction: 0.55
            )
        }
        .onChangeCompat(of: showIDEWorkbenchSidebar) { wasVisible, isVisible in
            guard isVisible && !wasVisible else { return }
            sidePanelWidth = 380
        }
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

            if panelCoordinator.showBrowserPanel {
                browserResizeHandle(clampedWidth: clampedBrowserW, maxWidth: maxBrowserW, leading: true)
                BrowserPanelView(tabManager: browserTabManager)
                    .frame(width: clampedBrowserW)
            }
        }
        .frame(maxWidth: CGFloat.infinity, maxHeight: CGFloat.infinity)
        .onChangeCompat(of: panelCoordinator.showBrowserPanel) { wasOpen, isOpen in
            guard isOpen && !wasOpen else { return }
            ContentPanelWidthPolicy.snapStoredWidthToOpenMax(
                storedWidth: &browserPanelWidth,
                detailWidth: detailWidth,
                fraction: 0.65
            )
        }
    }

    var fallbackModeContent: some View {
        chatPanel
            .frame(maxWidth: CGFloat.infinity, maxHeight: CGFloat.infinity)
    }
}
