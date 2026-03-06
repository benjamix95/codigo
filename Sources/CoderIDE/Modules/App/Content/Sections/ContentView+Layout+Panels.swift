import AppKit
import SwiftUI
import UniformTypeIdentifiers
import CoderEngine

extension ContentView {
    func editorTopBar(ctx: EffectiveContext) -> some View {
        let activePath = editorSplitStore.filePath(primaryPath: openFilesStore.openFilePath)
        let diagnostics = editorDiagnosticsStore.summary(for: activePath)

        return HStack(spacing: 12) {
            workspaceBadge(ctx: ctx)

            if let path = activePath, !path.isEmpty {
                activeFileBadge(path: path, ctx: ctx)
            } else {
                emptyEditorBadge()
            }

            Spacer()

            if diagnostics.errors > 0 || diagnostics.warnings > 0 {
                statusBadge(
                    icon: diagnostics.errors > 0 ? "xmark.octagon.fill" : "exclamationmark.triangle.fill",
                    title: diagnostics.errors > 0 ? "\(diagnostics.errors) errors" : "\(diagnostics.warnings) warnings",
                    tint: diagnostics.errors > 0 ? DesignSystem.Colors.error : DesignSystem.Colors.warning
                )
            }

            statusBadge(
                icon: editorSplitStore.isSplitVisible ? "rectangle.split.2x1.fill" : "rectangle",
                title: editorSplitStore.isSplitVisible ? "Split editor" : "Single editor",
                tint: DesignSystem.Colors.info
            )

            HStack(spacing: 8) {
                toolbarActionButton(
                    icon: "magnifyingglass",
                    title: "Quick Open",
                    isActive: false
                ) {
                    NotificationCenter.default.post(name: .editorQuickOpen, object: nil)
                }

                toolbarActionButton(
                    icon: "rectangle.split.2x1",
                    title: "Split",
                    isActive: editorSplitStore.isSplitVisible
                ) {
                    NotificationCenter.default.post(name: .editorToggleSplit, object: nil)
                }

                toolbarActionButton(
                    icon: "list.bullet.rectangle.portrait",
                    title: "Outline",
                    isActive: false
                ) {
                    NotificationCenter.default.post(name: .editorShowOutline, object: nil)
                }

                toolbarActionButton(
                    icon: "exclamationmark.triangle",
                    title: "Problems",
                    isActive: diagnostics.errors > 0 || diagnostics.warnings > 0
                ) {
                    NotificationCenter.default.post(name: .editorShowProblems, object: nil)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.white.opacity(0.04))
            )

            HStack(spacing: 8) {
                toolbarActionButton(
                    icon: "terminal",
                    title: "Terminal",
                    isActive: showTerminal
                ) {
                    withAnimation(.snappy(duration: 0.2)) { showTerminal.toggle() }
                }

                toolbarActionButton(
                    icon: "globe",
                    title: "Browser",
                    isActive: showBrowserPanel,
                    tint: DesignSystem.Colors.browserColor
                ) {
                    withAnimation(.snappy(duration: 0.2)) { showBrowserPanel.toggle() }
                }

                toolbarActionButton(
                    icon: "arrow.triangle.branch",
                    title: "Git",
                    isActive: gitPanelStore.isOpen,
                    tint: ActivityBarItem.sourceControl.tint
                ) {
                    gitPanelStore.isOpen.toggle()
                }

                toolbarActionButton(
                    icon: "bubble.left.and.bubble.right",
                    title: "Chat",
                    isActive: showChatPanel
                ) {
                    withAnimation(.snappy(duration: 0.2)) { showChatPanel.toggle() }
                }

                toolbarActionButton(
                    icon: chatPanelPosition == "left" ? "sidebar.right" : "sidebar.left",
                    title: "Swap",
                    isActive: false,
                    tint: DesignSystem.Colors.info
                ) {
                    withAnimation(.snappy(duration: 0.2)) {
                        chatPanelPosition = chatPanelPosition == "left" ? "right" : "left"
                    }
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.white.opacity(0.04))
            )
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            LinearGradient(
                colors: [
                    Color.white.opacity(0.03),
                    Color.clear
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
    }

    private func workspaceBadge(ctx: EffectiveContext) -> some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(DesignSystem.Colors.info.opacity(0.16))
                    .frame(width: 34, height: 34)
                Image(systemName: "sidebar.leading")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(DesignSystem.Colors.info)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(ctx.displayLabel)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(ctx.activeRootPath.map { ($0 as NSString).lastPathComponent } ?? "No workspace")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white.opacity(0.04))
        )
    }

    private func activeFileBadge(path: String, ctx: EffectiveContext) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: "doc.text")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.accentColor)
                Text((path as NSString).lastPathComponent)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
            }
            breadcrumb(path: path, ctx: ctx)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white.opacity(0.04))
        )
    }

    private func breadcrumb(path: String, ctx: EffectiveContext) -> some View {
        let components = breadcrumbComponents(path: path, rootPaths: ctx.folderPaths)
        return HStack(spacing: 4) {
            ForEach(Array(components.enumerated()), id: \.offset) { idx, component in
                if idx > 0 {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 7, weight: .bold))
                        .foregroundStyle(.quaternary)
                }
                Text(component)
                    .font(.system(size: 10.5, weight: idx == components.count - 1 ? .medium : .regular))
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
