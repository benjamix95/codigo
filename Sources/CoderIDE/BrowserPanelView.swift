import SwiftUI
import WebKit
import AppKit

// MARK: - Browser WKWebView (NSViewRepresentable)

struct BrowserWebView: NSViewRepresentable {
    @ObservedObject var store: BrowserSessionStore
    let tabManager: BrowserTabManager

    func makeCoordinator() -> Coordinator { Coordinator(store: store, tabManager: tabManager) }

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let controller = WKUserContentController()

        controller.add(context.coordinator, name: "browserbridge")

        if let bridgeURL = Bundle.main.url(forResource: "browser-bridge", withExtension: "js"),
           let bridgeSource = try? String(contentsOf: bridgeURL, encoding: .utf8) {
            let userScript = WKUserScript(
                source: bridgeSource,
                injectionTime: .atDocumentStart,
                forMainFrameOnly: false
            )
            controller.addUserScript(userScript)
        }

        config.userContentController = controller
        config.preferences.setValue(true, forKey: "javaScriptEnabled")
        config.preferences.setValue(true, forKey: "developerExtrasEnabled")

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true
        webView.wantsLayer = true

        context.coordinator.webView = webView

        Task { @MainActor in
            store.webView = webView
        }

        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {}

    static func dismantleNSView(_ webView: WKWebView, coordinator: Coordinator) {
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "browserbridge")
    }

    final class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
        let store: BrowserSessionStore
        let tabManager: BrowserTabManager
        weak var webView: WKWebView?

        init(store: BrowserSessionStore, tabManager: BrowserTabManager) {
            self.store = store
            self.tabManager = tabManager
        }

        func userContentController(_ uc: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.name == "browserbridge",
                  let body = message.body as? [String: Any],
                  let type = body["type"] as? String,
                  let payload = body["payload"] as? [String: Any] else { return }

            Task { @MainActor [store] in
                switch type {
                case "console":
                    let levelStr = payload["level"] as? String ?? "log"
                    let level = ConsoleLogLevel(rawValue: levelStr) ?? .log
                    store.appendConsoleLog(ConsoleLogEntry(
                        level: level, message: payload["message"] as? String ?? "",
                        source: nil, line: nil, timestamp: Date()
                    ))
                case "jsError":
                    store.appendJSError(JSError(
                        message: payload["message"] as? String ?? "Unknown error",
                        source: payload["source"] as? String,
                        line: payload["line"] as? Int,
                        column: payload["col"] as? Int,
                        stack: payload["stack"] as? String,
                        timestamp: Date()
                    ))
                case "network", "networkXHR", "networkFetch":
                    store.appendNetworkRequest(NetworkRequest(
                        url: payload["url"] as? String ?? "",
                        method: payload["method"] as? String ?? "GET",
                        status: payload["status"] as? Int,
                        duration: payload["duration"] as? Double,
                        initiatorType: payload["initiatorType"] as? String ?? type,
                        timestamp: Date()
                    ))
                default: break
                }
            }
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            Task { @MainActor [store] in
                store.updatePageState(url: webView.url?.absoluteString, title: nil, loading: true)
                store.updateNavState(canGoBack: webView.canGoBack, canGoForward: webView.canGoForward)
            }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            Task { @MainActor [store, tabManager] in
                let url = webView.url?.absoluteString ?? ""
                let title = webView.title ?? ""
                store.updatePageState(url: url, title: title, loading: false)
                store.updateNavState(canGoBack: webView.canGoBack, canGoForward: webView.canGoForward)
                if !url.isEmpty, url != "about:blank" {
                    tabManager.recordHistory(url: url, title: title)
                }
            }
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            Task { @MainActor [store] in
                store.updatePageState(url: nil, title: nil, loading: false)
                store.appendConsoleLog(ConsoleLogEntry(
                    level: .error, message: "Navigation failed: \(error.localizedDescription)",
                    source: nil, line: nil, timestamp: Date()
                ))
            }
        }

        func webView(_ wv: WKWebView, decidePolicyFor nav: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            decisionHandler(.allow)
        }
    }
}

// MARK: - Browser Panel View

struct BrowserPanelView: View {
    @ObservedObject var tabManager: BrowserTabManager
    @State private var urlFieldText: String = ""
    @State private var consoleFilterLevel: ConsoleLogLevel? = nil
    @AppStorage("browser_console_height") private var consoleHeight: Double = 180

    private var activeStore: BrowserSessionStore? { tabManager.activeStore }

    var body: some View {
        VStack(spacing: 0) {
            browserTabBar
            Divider().opacity(0.2)
            browserToolbar
            Divider().opacity(0.2)
            browserContent
        }
        .background(DesignSystem.Colors.backgroundDeep)
    }

    // MARK: - Tab Bar

    private var browserTabBar: some View {
        HStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 0) {
                    ForEach(tabManager.tabs) { tab in
                        browserTabItem(tab)
                    }
                }
            }
            .frame(maxWidth: .infinity)

            Divider().opacity(0.2).frame(height: 26)

            Button {
                withAnimation(.snappy(duration: 0.15)) {
                    _ = tabManager.addNewTab()
                }
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(DesignSystem.Colors.textSecondary)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("New tab")
        }
        .frame(height: 28)
        .background { DesignSystem.Colors.backgroundPrimary.opacity(0.7) }
    }

    private func browserTabItem(_ tab: BrowserTab) -> some View {
        let isActive = tabManager.activeTabId == tab.id
        return HStack(spacing: 4) {
            if tab.store.isLoading {
                ProgressView().controlSize(.mini).scaleEffect(0.5)
            } else {
                Image(systemName: "globe")
                    .font(.system(size: 8))
                    .foregroundStyle(isActive ? DesignSystem.Colors.browserColor : DesignSystem.Colors.textTertiary)
            }

            Text(tab.label)
                .font(.system(size: 10.5, weight: isActive ? .medium : .regular))
                .foregroundStyle(isActive ? DesignSystem.Colors.textPrimary : DesignSystem.Colors.textSecondary)
                .lineLimit(1)
                .frame(maxWidth: 120)

            if tabManager.tabs.count > 1 {
                Button {
                    withAnimation(.snappy(duration: 0.15)) {
                        tabManager.closeTab(id: tab.id)
                    }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 7, weight: .bold))
                        .foregroundStyle(DesignSystem.Colors.textTertiary)
                        .frame(width: 14, height: 14)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .opacity(isActive ? 1 : 0.5)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(isActive ? DesignSystem.Colors.backgroundSecondary : Color.clear)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            tabManager.selectTab(id: tab.id)
        }
        .contextMenu {
            Button("Close Tab") { tabManager.closeTab(id: tab.id) }
                .disabled(tabManager.tabs.count <= 1)
            Button("Duplicate Tab") {
                tabManager.addNewTab(url: tab.store.currentURL.isEmpty ? nil : tab.store.currentURL)
            }
            Divider()
            Button("Close Other Tabs", role: .destructive) {
                let others = tabManager.tabs.filter { $0.id != tab.id }.map(\.id)
                for otherId in others { tabManager.closeTab(id: otherId) }
            }
            .disabled(tabManager.tabs.count <= 1)
        }
    }

    // MARK: - Toolbar

    private var browserToolbar: some View {
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
        HStack(spacing: 1) {
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

    // MARK: - Main Content

    private var browserContent: some View {
        HStack(spacing: 0) {
            if tabManager.showBookmarksPanel {
                bookmarksPanel
                    .frame(width: 220)
                Divider().opacity(0.2)
            }
            if tabManager.showHistoryPanel {
                historyPanel
                    .frame(width: 220)
                Divider().opacity(0.2)
            }

            if let tab = tabManager.activeTab {
                VStack(spacing: 0) {
                    BrowserWebView(store: tab.store, tabManager: tabManager)
                        .id(tab.id)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)

                    if let img = tab.store.lastScreenshot, tab.store.lastScreenshotTimestamp != nil {
                        Divider().opacity(0.15)
                        screenshotPreview(img, store: tab.store)
                    }

                    if tab.store.showConsoleDrawer {
                        Divider().opacity(0.2)
                        consoleDrawer(store: tab.store)
                            .frame(height: max(100, CGFloat(consoleHeight)))
                    }
                }
            } else {
                Color.clear
            }
        }
    }

    // MARK: - Screenshot Preview

    private func screenshotPreview(_ image: NSImage, store: BrowserSessionStore) -> some View {
        HStack(spacing: 8) {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(height: 44)
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(DesignSystem.Colors.borderSubtle, lineWidth: 0.5)
                )

            VStack(alignment: .leading, spacing: 2) {
                Text("Last Screenshot")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(DesignSystem.Colors.textSecondary)
                if let ts = store.lastScreenshotTimestamp {
                    Text(ts, style: .time)
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(DesignSystem.Colors.textTertiary)
                }
            }

            Spacer()

            Button {
                store.lastScreenshot = nil
                store.lastScreenshotTimestamp = nil
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(DesignSystem.Colors.textTertiary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(DesignSystem.Colors.backgroundPrimary)
    }

    // MARK: - Bookmarks Panel

    private var bookmarksPanel: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "star.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(DesignSystem.Colors.warning)
                Text("Bookmarks")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(DesignSystem.Colors.textSecondary)
                Spacer()
                Text("\(tabManager.bookmarks.count)")
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundStyle(DesignSystem.Colors.textTertiary)
            }
            .padding(.horizontal, 10).padding(.vertical, 6)
            Divider().opacity(0.15)

            if tabManager.bookmarks.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "star")
                        .font(.system(size: 20))
                        .foregroundStyle(DesignSystem.Colors.textQuaternary)
                    Text("No bookmarks yet")
                        .font(.system(size: 11))
                        .foregroundStyle(DesignSystem.Colors.textTertiary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(tabManager.bookmarks) { bm in
                            bookmarkRow(bm)
                        }
                    }
                }
            }
        }
        .background(DesignSystem.Colors.backgroundPrimary)
    }

    private func bookmarkRow(_ bm: BrowserBookmark) -> some View {
        Button {
            activeStore?.navigate(to: bm.url)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "globe")
                    .font(.system(size: 9))
                    .foregroundStyle(DesignSystem.Colors.textTertiary)
                VStack(alignment: .leading, spacing: 1) {
                    Text(bm.title)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(DesignSystem.Colors.textPrimary)
                        .lineLimit(1)
                    Text(bm.url)
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(DesignSystem.Colors.textTertiary)
                        .lineLimit(1)
                }
                Spacer()
            }
            .padding(.horizontal, 10).padding(.vertical, 5)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Open") { activeStore?.navigate(to: bm.url) }
            Button("Open in New Tab") { tabManager.addNewTab(url: bm.url) }
            Button("Copy URL") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(bm.url, forType: .string) }
            Divider()
            Button("Remove", role: .destructive) { tabManager.removeBookmark(id: bm.id) }
        }
    }

    // MARK: - History Panel

    private var historyPanel: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.system(size: 10))
                    .foregroundStyle(DesignSystem.Colors.browserColor)
                Text("History")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(DesignSystem.Colors.textSecondary)
                Spacer()
                if !tabManager.history.isEmpty {
                    Button {
                        tabManager.clearHistory()
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 9))
                            .foregroundStyle(DesignSystem.Colors.textTertiary)
                    }
                    .buttonStyle(.plain)
                    .help("Clear history")
                }
            }
            .padding(.horizontal, 10).padding(.vertical, 6)
            Divider().opacity(0.15)

            if tabManager.history.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "clock")
                        .font(.system(size: 20))
                        .foregroundStyle(DesignSystem.Colors.textQuaternary)
                    Text("No history")
                        .font(.system(size: 11))
                        .foregroundStyle(DesignSystem.Colors.textTertiary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(tabManager.history) { entry in
                            historyRow(entry)
                        }
                    }
                }
            }
        }
        .background(DesignSystem.Colors.backgroundPrimary)
    }

    private func historyRow(_ entry: BrowserHistoryEntry) -> some View {
        Button {
            activeStore?.navigate(to: entry.url)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "globe")
                    .font(.system(size: 9))
                    .foregroundStyle(DesignSystem.Colors.textTertiary)
                VStack(alignment: .leading, spacing: 1) {
                    Text(entry.title)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(DesignSystem.Colors.textPrimary)
                        .lineLimit(1)
                    HStack(spacing: 4) {
                        Text(entry.url)
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(DesignSystem.Colors.textTertiary)
                            .lineLimit(1)
                        Text(entry.timestamp, style: .time)
                            .font(.system(size: 8, design: .monospaced))
                            .foregroundStyle(DesignSystem.Colors.textQuaternary)
                    }
                }
                Spacer()
            }
            .padding(.horizontal, 10).padding(.vertical, 5)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Open") { activeStore?.navigate(to: entry.url) }
            Button("Open in New Tab") { tabManager.addNewTab(url: entry.url) }
            Button("Copy URL") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(entry.url, forType: .string) }
            Button("Bookmark") { activeStore?.navigate(to: entry.url); tabManager.addBookmark() }
        }
    }

    // MARK: - Console Drawer

    private func consoleDrawer(store: BrowserSessionStore) -> some View {
        VStack(spacing: 0) {
            consoleToolbar(store: store)
            Divider().opacity(0.15)
            consoleLogsList(store: store)
        }
        .background(DesignSystem.Colors.backgroundPrimary)
    }

    private func consoleToolbar(store: BrowserSessionStore) -> some View {
        HStack(spacing: 6) {
            Text("Console")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(DesignSystem.Colors.textSecondary)

            Spacer()

            Picker("", selection: $consoleFilterLevel) {
                Text("All").tag(ConsoleLogLevel?.none)
                ForEach(ConsoleLogLevel.allCases, id: \.self) { level in
                    Label(level.rawValue.capitalized, systemImage: level.icon)
                        .tag(ConsoleLogLevel?.some(level))
                }
            }
            .pickerStyle(.menu)
            .frame(width: 80)
            .controlSize(.small)

            let errorCount = store.consoleLogs.filter { $0.level == .error }.count
            let warnCount = store.consoleLogs.filter { $0.level == .warn }.count

            if errorCount > 0 {
                HStack(spacing: 2) {
                    Image(systemName: "xmark.octagon.fill").font(.system(size: 9))
                    Text("\(errorCount)").font(.system(size: 10, weight: .medium, design: .monospaced))
                }
                .foregroundStyle(DesignSystem.Colors.error)
            }

            if warnCount > 0 {
                HStack(spacing: 2) {
                    Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 9))
                    Text("\(warnCount)").font(.system(size: 10, weight: .medium, design: .monospaced))
                }
                .foregroundStyle(DesignSystem.Colors.warning)
            }

            Button { store.clearConsoleLogs() } label: {
                Image(systemName: "trash").font(.system(size: 10)).foregroundStyle(DesignSystem.Colors.textTertiary)
            }
            .buttonStyle(.plain).help("Clear console")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
    }

    private func consoleLogsList(store: BrowserSessionStore) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    let logs = store.filteredLogs(level: consoleFilterLevel)
                    ForEach(logs) { entry in
                        consoleLogRow(entry).id(entry.id)
                    }
                }
                .padding(.horizontal, 8)
            }
            .onChange(of: store.consoleLogs.count) { _, _ in
                if let last = store.filteredLogs(level: consoleFilterLevel).last {
                    proxy.scrollTo(last.id, anchor: .bottom)
                }
            }
        }
    }

    private func consoleLogRow(_ entry: ConsoleLogEntry) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: entry.level.icon)
                .font(.system(size: 9))
                .foregroundStyle(colorForLevel(entry.level))
                .frame(width: 12, alignment: .center)
                .padding(.top, 2)

            Text(entry.message)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(colorForLevel(entry.level))
                .textSelection(.enabled)
                .lineLimit(nil)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 2).padding(.horizontal, 4)
        .background(
            entry.level == .error ? DesignSystem.Colors.error.opacity(0.06)
            : entry.level == .warn ? DesignSystem.Colors.warning.opacity(0.04)
            : Color.clear
        )
    }

    private func colorForLevel(_ level: ConsoleLogLevel) -> Color {
        switch level {
        case .error: return DesignSystem.Colors.error
        case .warn: return DesignSystem.Colors.warning
        case .info: return DesignSystem.Colors.info
        case .debug: return DesignSystem.Colors.textTertiary
        case .log: return DesignSystem.Colors.textSecondary
        }
    }
}
