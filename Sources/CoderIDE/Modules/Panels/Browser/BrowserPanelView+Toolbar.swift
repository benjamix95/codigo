import SwiftUI
import AppKit

enum BrowserToolbarLayoutMode {
    case full
    case medium
    case compact
}

func browserToolbarLayoutMode(for width: CGFloat) -> BrowserToolbarLayoutMode {
    if width < 520 {
        return .compact
    }
    if width < 700 {
        return .medium
    }
    return .full
}

extension BrowserPanelView {
    // MARK: - Toolbar

    var browserToolbar: some View {
        GeometryReader { proxy in
            VStack(spacing: 0) {
                if let store = activeStore {
                    let mode = browserToolbarLayoutMode(for: proxy.size.width)
                    HStack(spacing: mode == .compact ? 4 : 5) {
                        navButtons(store: store, mode: mode)
                        urlBar(store: store)
                            .layoutPriority(1)
                            .frame(maxWidth: .infinity)
                        actionButtons(store: store, mode: mode)
                            .fixedSize(horizontal: true, vertical: false)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(DesignSystem.Colors.backgroundPrimary.opacity(0.5))
                }

                if tabManager.showBookmarksPanel || tabManager.showHistoryPanel {
                    Divider().opacity(0.15)
                }
            }
        }
        .frame(height: 34)
    }

    private func navButtons(store: BrowserSessionStore, mode: BrowserToolbarLayoutMode) -> some View {
        HStack(spacing: 1) {
            tbBtn(icon: "chevron.left", disabled: !store.canGoBack) { store.goBack() }
            tbBtn(icon: "chevron.right", disabled: !store.canGoForward) { store.goForward() }
            tbBtn(icon: store.isLoading ? "xmark" : "arrow.clockwise", disabled: false) {
                if store.isLoading { store.webView?.stopLoading() } else { store.reload() }
            }
            if mode != .compact {
                tbBtn(icon: "house", disabled: false) { store.goHome() }
            }
        }
    }

    private func urlBar(store: BrowserSessionStore) -> some View {
        HStack(spacing: 5) {
            if store.isLoading {
                ProgressView().controlSize(.mini).scaleEffect(0.65)
            } else {
                Image(systemName: store.currentURL.hasPrefix("https") ? "lock.fill" : "globe")
                    .font(.system(size: 9))
                    .foregroundStyle(
                        store.currentURL.hasPrefix("https") ? DesignSystem.Colors.success : DesignSystem.Colors.textTertiary
                    )
            }

            TextField("Search or enter URL...", text: $urlFieldText)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .onSubmit { store.navigate(to: urlFieldText) }
                .onChange(of: store.currentURL) { _, newURL in
                    if !newURL.isEmpty { urlFieldText = newURL }
                }
                .onChange(of: tabManager.activeTabId) { _, _ in
                    if let url = activeStore?.currentURL, !url.isEmpty {
                        urlFieldText = url
                    } else {
                        urlFieldText = ""
                    }
                }
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium)
                .fill(DesignSystem.Colors.backgroundSecondary)
        )
        .overlay(
            RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium)
                .stroke(DesignSystem.Colors.borderSubtle, lineWidth: 0.5)
        )
    }

    private func actionButtons(store: BrowserSessionStore, mode: BrowserToolbarLayoutMode) -> some View {
        HStack(spacing: 6) {
            bookmarkButton(store: store)

            if mode == .full {
                bookmarksToggleButton(store: store)
                historyToggleButton(store: store)
                screenshotButton(store: store)
                consoleButton(store: store)
                zoomMenu(store: store)
            } else if mode == .medium {
                libraryMenu(store: store)
                screenshotButton(store: store)
                consoleButton(store: store)
                zoomMenu(store: store)
            } else {
                libraryMenu(store: store)
                consoleButton(store: store)
            }

            overflowMenu(store: store, mode: mode)
        }
    }

    private func bookmarkButton(store: BrowserSessionStore) -> some View {
        tbBtn(
            icon: tabManager.isBookmarked(store.currentURL) ? "star.fill" : "star",
            disabled: store.currentURL.isEmpty,
            tint: tabManager.isBookmarked(store.currentURL) ? DesignSystem.Colors.warning : nil
        ) {
            if tabManager.isBookmarked(store.currentURL) {
                if let bm = tabManager.bookmarks.first(where: { $0.url == store.currentURL }) {
                    tabManager.removeBookmark(id: bm.id)
                }
            } else {
                tabManager.addBookmark()
            }
        }
    }

    private func bookmarksToggleButton(store: BrowserSessionStore) -> some View {
        tbBtn(icon: "book", disabled: false,
              tint: tabManager.showBookmarksPanel ? DesignSystem.Colors.browserColor : nil
        ) {
            withAnimation(.snappy(duration: 0.15)) {
                tabManager.showBookmarksPanel.toggle()
                if tabManager.showBookmarksPanel { tabManager.showHistoryPanel = false }
            }
        }
    }

    private func historyToggleButton(store: BrowserSessionStore) -> some View {
        tbBtn(icon: "clock.arrow.circlepath", disabled: false,
              tint: tabManager.showHistoryPanel ? DesignSystem.Colors.browserColor : nil
        ) {
            withAnimation(.snappy(duration: 0.15)) {
                tabManager.showHistoryPanel.toggle()
                if tabManager.showHistoryPanel { tabManager.showBookmarksPanel = false }
            }
        }
    }

    private func libraryMenu(store: BrowserSessionStore) -> some View {
        Menu {
            Button {
                withAnimation(.snappy(duration: 0.15)) {
                    tabManager.showBookmarksPanel.toggle()
                    if tabManager.showBookmarksPanel { tabManager.showHistoryPanel = false }
                }
            } label: {
                Label("Bookmarks", systemImage: "book")
            }
            Button {
                withAnimation(.snappy(duration: 0.15)) {
                    tabManager.showHistoryPanel.toggle()
                    if tabManager.showHistoryPanel { tabManager.showBookmarksPanel = false }
                }
            } label: {
                Label("History", systemImage: "clock.arrow.circlepath")
            }
        } label: {
            tbMenuLabel(
                icon: tabManager.showBookmarksPanel || tabManager.showHistoryPanel ? "books.vertical.fill" : "books.vertical",
                tint: (tabManager.showBookmarksPanel || tabManager.showHistoryPanel) ? DesignSystem.Colors.browserColor : nil
            )
        }
        .menuStyle(.borderlessButton)
    }

    private func screenshotButton(store: BrowserSessionStore) -> some View {
        tbBtn(icon: "camera", disabled: false) {
            Task { let _ = await store.takeScreenshot() }
        }
    }

    private func consoleButton(store: BrowserSessionStore) -> some View {
        tbBtn(icon: "terminal", disabled: false,
              tint: store.showConsoleDrawer ? DesignSystem.Colors.browserColor : nil
        ) {
            withAnimation(.snappy(duration: 0.15)) { store.showConsoleDrawer.toggle() }
        }
        .overlay(alignment: .topTrailing) {
            let errCt = store.consoleLogs.filter { $0.level == .error }.count
            if errCt > 0 {
                Text("\(min(errCt, 99))")
                    .font(.system(size: 7, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 3).padding(.vertical, 1)
                    .background(DesignSystem.Colors.error, in: Capsule())
                    .offset(x: 4, y: -4)
            }
        }
    }

    private func zoomMenu(store: BrowserSessionStore) -> some View {
        Menu {
            Button("Zoom In (⌘+)") { store.zoomIn() }
            Button("Zoom Out (⌘-)") { store.zoomOut() }
            Button("Reset Zoom") { store.resetZoom() }
            Divider()
            Text("Zoom: \(Int(store.zoomLevel * 100))%")
        } label: {
            tbMenuLabel(icon: "textformat.size")
        }
        .menuStyle(.borderlessButton)
    }

    private func overflowMenu(store: BrowserSessionStore, mode: BrowserToolbarLayoutMode) -> some View {
        Menu {
            if mode == .compact {
                Button {
                    Task { let _ = await store.takeScreenshot() }
                } label: {
                    Label("Screenshot", systemImage: "camera")
                }
                Divider()
            }

            if mode == .compact {
                Button("Zoom In (⌘+)") { store.zoomIn() }
                Button("Zoom Out (⌘-)") { store.zoomOut() }
                Button("Reset Zoom") { store.resetZoom() }
                Divider()
            }

            if mode == .compact {
                Button("Home") { store.goHome() }
                Divider()
            }

            Button(role: .destructive) { store.clearCache() } label: {
                Label("Clear Cache & Cookies", systemImage: "trash.circle")
            }
            Button(role: .destructive) { tabManager.clearHistory() } label: {
                Label("Clear History", systemImage: "clock.badge.xmark")
            }
            Button(role: .destructive) { store.clearConsoleLogs() } label: {
                Label("Clear Console", systemImage: "terminal")
            }
            Divider()
            Button(role: .destructive) {
                store.hardReset()
                tabManager.clearHistory()
            } label: {
                Label("Hard Reset (Clear Everything)", systemImage: "arrow.counterclockwise.circle.fill")
            }
        } label: {
            tbMenuLabel(icon: "ellipsis.circle")
        }
        .menuStyle(.borderlessButton)
    }

    private func tbMenuLabel(icon: String, tint: Color? = nil) -> some View {
        Image(systemName: icon)
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(tint ?? DesignSystem.Colors.textSecondary)
            .frame(width: 22, height: 22)
            .contentShape(Rectangle())
    }

    private func tbBtn(icon: String, disabled: Bool, tint: Color? = nil, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            tbMenuLabel(icon: icon, tint: disabled ? DesignSystem.Colors.textQuaternary : tint)
        }
        .buttonStyle(.plain)
        .disabled(disabled)
    }
}
