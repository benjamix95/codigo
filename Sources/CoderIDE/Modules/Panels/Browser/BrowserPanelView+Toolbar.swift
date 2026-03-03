import SwiftUI
import AppKit

extension BrowserPanelView {
    // MARK: - Toolbar

    var browserToolbar: some View {
        VStack(spacing: 0) {
            if let store = activeStore {
                HStack(spacing: 5) {
                    navButtons(store: store)
                    urlBar(store: store)
                    actionButtons(store: store)
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

    private func navButtons(store: BrowserSessionStore) -> some View {
        HStack(spacing: 1) {
            tbBtn(icon: "chevron.left", disabled: !store.canGoBack) { store.goBack() }
            tbBtn(icon: "chevron.right", disabled: !store.canGoForward) { store.goForward() }
            tbBtn(icon: store.isLoading ? "xmark" : "arrow.clockwise", disabled: false) {
                if store.isLoading { store.webView?.stopLoading() } else { store.reload() }
            }
            tbBtn(icon: "house", disabled: false) { store.goHome() }
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

    private func actionButtons(store: BrowserSessionStore) -> some View {
        HStack(spacing: 6) {
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

            tbBtn(icon: "book", disabled: false,
                  tint: tabManager.showBookmarksPanel ? DesignSystem.Colors.browserColor : nil
            ) {
                withAnimation(.snappy(duration: 0.15)) {
                    tabManager.showBookmarksPanel.toggle()
                    if tabManager.showBookmarksPanel { tabManager.showHistoryPanel = false }
                }
            }

            tbBtn(icon: "clock.arrow.circlepath", disabled: false,
                  tint: tabManager.showHistoryPanel ? DesignSystem.Colors.browserColor : nil
            ) {
                withAnimation(.snappy(duration: 0.15)) {
                    tabManager.showHistoryPanel.toggle()
                    if tabManager.showHistoryPanel { tabManager.showBookmarksPanel = false }
                }
            }

            tbBtn(icon: "camera", disabled: false) {
                Task { let _ = await store.takeScreenshot() }
            }

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

            Menu {
                Button("Zoom In (⌘+)") { store.zoomIn() }
                Button("Zoom Out (⌘-)") { store.zoomOut() }
                Button("Reset Zoom") { store.resetZoom() }
                Divider()
                Text("Zoom: \(Int(store.zoomLevel * 100))%")
            } label: {
                Image(systemName: "textformat.size")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(DesignSystem.Colors.textSecondary)
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .frame(width: 22)

            Menu {
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
                Image(systemName: "ellipsis.circle")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(DesignSystem.Colors.textSecondary)
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .frame(width: 22)
        }
    }

    private func tbBtn(icon: String, disabled: Bool, tint: Color? = nil, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(disabled ? DesignSystem.Colors.textQuaternary : (tint ?? DesignSystem.Colors.textSecondary))
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(disabled)
    }
}
