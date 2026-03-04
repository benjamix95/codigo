import AppKit
import SwiftUI
import UniformTypeIdentifiers
import CoderEngine

extension ContentView {
    func editorTopBar(ctx: EffectiveContext) -> some View {
        HStack(spacing: 8) {
            if let path = openFilesStore.openFilePath, !path.isEmpty {
                breadcrumb(path: path, ctx: ctx)
            } else {
                Image(systemName: "rectangle.split.2x1")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                Text("Editor")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                withAnimation(.snappy(duration: 0.2)) { showTerminal.toggle() }
            } label: {
                Image(systemName: "terminal.fill")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(showTerminal ? Color.accentColor : Color.secondary.opacity(0.5))
                    .padding(4)
                    .background(
                        showTerminal ? Color.accentColor.opacity(0.12) : .clear,
                        in: RoundedRectangle(cornerRadius: 4)
                    )
            }
            .buttonStyle(.plain)
            .help("Toggle terminal")

            Button {
                withAnimation(.snappy(duration: 0.2)) { showBrowserPanel.toggle() }
            } label: {
                Image(systemName: "globe")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(showBrowserPanel ? DesignSystem.Colors.browserColor : Color.secondary.opacity(0.5))
                    .padding(4)
                    .background(
                        showBrowserPanel ? DesignSystem.Colors.browserColor.opacity(0.12) : .clear,
                        in: RoundedRectangle(cornerRadius: 4)
                    )
            }
            .buttonStyle(.plain)
            .help("Toggle browser")

            Button {
                withAnimation(.snappy(duration: 0.2)) { showChatPanel.toggle() }
            } label: {
                Image(systemName: "bubble.left.and.bubble.right")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(showChatPanel ? Color.accentColor : Color.secondary.opacity(0.5))
                    .padding(4)
                    .background(
                        showChatPanel ? Color.accentColor.opacity(0.12) : .clear,
                        in: RoundedRectangle(cornerRadius: 4)
                    )
            }
            .buttonStyle(.plain)
            .help("Toggle chat panel")

            Button {
                gitPanelStore.isOpen.toggle()
            } label: {
                Image(systemName: "arrow.triangle.branch")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(gitPanelStore.isOpen ? Color.accentColor : Color.secondary.opacity(0.5))
                    .padding(4)
                    .background(
                        gitPanelStore.isOpen ? Color.accentColor.opacity(0.12) : .clear,
                        in: RoundedRectangle(cornerRadius: 4)
                    )
            }
            .buttonStyle(.plain)
            .help("Toggle git panel")

            Button {
                withAnimation(.snappy(duration: 0.2)) {
                    chatPanelPosition = chatPanelPosition == "left" ? "right" : "left"
                }
            } label: {
                Image(systemName: chatPanelPosition == "left" ? "sidebar.left" : "sidebar.right")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.secondary.opacity(0.5))
                    .padding(4)
            }
            .buttonStyle(.plain)
            .help(chatPanelPosition == "left" ? "Move chat to right" : "Move chat to left")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(DesignSystem.Colors.backgroundPrimary.opacity(0.5))
    }

    private func breadcrumb(path: String, ctx: EffectiveContext) -> some View {
        let components = breadcrumbComponents(path: path, rootPaths: ctx.folderPaths)
        return HStack(spacing: 2) {
            ForEach(Array(components.enumerated()), id: \.offset) { idx, component in
                if idx > 0 {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 7, weight: .bold))
                        .foregroundStyle(.quaternary)
                }
                Text(component)
                    .font(.system(size: 11, weight: idx == components.count - 1 ? .medium : .regular))
                    .foregroundStyle(idx == components.count - 1 ? .primary : .secondary)
                    .lineLimit(1)
            }
        }
    }

    private func breadcrumbComponents(path: String, rootPaths: [String]) -> [String] {
        for root in rootPaths {
            if path.hasPrefix(root + "/") {
                let relative = String(path.dropFirst(root.count + 1))
                let rootName = (root as NSString).lastPathComponent
                return [rootName] + relative.components(separatedBy: "/")
            }
        }
        return path.components(separatedBy: "/").suffix(3).map { String($0) }
    }

    var chatPanel: some View {
        ChatPanelView(
            selectedConversationId: $selectedConversationId,
            effectiveContext: effectiveContext(
                for: selectedConversationId,
                chatStore: chatStore,
                projectContextStore: projectContextStore,
                preferActiveContextForGlobalThread: preferActiveContextForGlobalThread
            ),
            coderMode: $coderMode,
            showPlanPanel: $showPlanPanel,
            showDebugPanel: $showDebugPanel,
            showSwarmPanel: $showSwarmPanel,
            showCodeReviewPanel: $showCodeReviewPanel,
            showBrowserPanel: $showBrowserPanel,
            debugStore: debugStore
        )
        .environmentObject(providerRegistry)
        .environmentObject(chatStore)
        .environmentObject(projectContextStore)
        .environmentObject(openFilesStore)
        .environmentObject(planHistoryStore)
        .environmentObject(browserTabManager)
        .chatPanelContainer(
            style: ChatBackgroundStyle.from(raw: chatBackgroundStyle),
            cornerRadius: 14
        )
    }
}
