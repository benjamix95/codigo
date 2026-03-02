import Foundation
import AppKit
import Combine
import WebKit
import CoderEngine

// MARK: - Models

public enum ConsoleLogLevel: String, Codable, CaseIterable {
    case log, info, warn, error, debug
    
    var icon: String {
        switch self {
        case .log: return "text.bubble"
        case .info: return "info.circle"
        case .warn: return "exclamationmark.triangle"
        case .error: return "xmark.octagon"
        case .debug: return "ladybug"
        }
    }
}

public struct ConsoleLogEntry: Identifiable {
    public let id = UUID()
    public let level: ConsoleLogLevel
    public let message: String
    public let source: String?
    public let line: Int?
    public let timestamp: Date
}

public struct JSError: Identifiable {
    public let id = UUID()
    public let message: String
    public let source: String?
    public let line: Int?
    public let column: Int?
    public let stack: String?
    public let timestamp: Date
}

public struct NetworkRequest: Identifiable {
    public let id = UUID()
    public let url: String
    public let method: String
    public let status: Int?
    public let duration: Double?
    public let initiatorType: String?
    public let timestamp: Date
}

public enum BrowserEngine: String, CaseIterable {
    case wkWebView = "WKWebView"
    case cdp = "Chrome DevTools Protocol"
}

// MARK: - Bookmark & History Models

public struct BrowserBookmark: Identifiable, Codable, Equatable {
    public var id = UUID()
    public var title: String
    public var url: String
    public var dateAdded: Date = Date()
}

public struct BrowserHistoryEntry: Identifiable, Codable {
    public var id = UUID()
    public var title: String
    public var url: String
    public var timestamp: Date = Date()
}

// MARK: - BrowserSessionStore (per-tab state)

@MainActor
public final class BrowserSessionStore: ObservableObject {
    @Published public var currentURL: String = ""
    @Published public var isLoading: Bool = false
    @Published public var pageTitle: String = ""
    @Published public var canGoBack: Bool = false
    @Published public var canGoForward: Bool = false
    @Published public var consoleLogs: [ConsoleLogEntry] = []
    @Published public var jsErrors: [JSError] = []
    @Published public var networkRequests: [NetworkRequest] = []
    @Published public var lastScreenshot: NSImage?
    @Published public var lastScreenshotTimestamp: Date?
    @Published public var showConsoleDrawer: Bool = false
    @Published public var engine: BrowserEngine = .wkWebView
    @Published public var zoomLevel: Double = 1.0

    let maxLogEntries = 1_000

    weak var webView: WKWebView?

    public init() {}

    // MARK: - Navigation

    public func navigate(to urlString: String) {
        var normalized = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        if !normalized.hasPrefix("http://") && !normalized.hasPrefix("https://") {
            if normalized.contains(".") && !normalized.contains(" ") {
                normalized = "https://\(normalized)"
            } else {
                normalized = "https://www.google.com/search?q=\(normalized.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? normalized)"
            }
        }
        guard let url = URL(string: normalized) else { return }
        currentURL = normalized
        webView?.load(URLRequest(url: url))
    }

    public func goBack() { webView?.goBack() }
    public func goForward() { webView?.goForward() }
    public func reload() { webView?.reload() }

    public func goHome() {
        navigate(to: "https://www.google.com")
    }

    // MARK: - Screenshot

    public func takeScreenshot() async -> Data? {
        guard let webView else { return nil }
        let config = WKSnapshotConfiguration()
        do {
            let image = try await webView.takeSnapshot(configuration: config)
            let tiffData = image.tiffRepresentation
            guard let tiff = tiffData,
                  let bitmapRep = NSBitmapImageRep(data: tiff) else { return nil }
            lastScreenshot = image
            lastScreenshotTimestamp = Date()
            return bitmapRep.representation(using: .png, properties: [:])
        } catch {
            return nil
        }
    }

    // MARK: - JavaScript

    public func evaluateJS(_ script: String) async -> String? {
        guard let webView else { return nil }
        do {
            let result = try await webView.evaluateJavaScript(script)
            if let str = result as? String { return str }
            if let num = result as? NSNumber { return num.stringValue }
            if result == nil { return "undefined" }
            return String(describing: result)
        } catch {
            return "Error: \(error.localizedDescription)"
        }
    }

    public func click(selector: String) async -> Bool {
        let script = """
        (function() {
            var el = document.querySelector('\(selector.replacingOccurrences(of: "'", with: "\\'"))');
            if (!el) return 'not_found';
            el.click();
            return 'clicked';
        })()
        """
        let result = await evaluateJS(script)
        return result == "clicked"
    }

    public func type(selector: String, text: String) async -> Bool {
        let safeSelector = selector.replacingOccurrences(of: "'", with: "\\'")
        let safeText = text.replacingOccurrences(of: "'", with: "\\'")
            .replacingOccurrences(of: "\n", with: "\\n")
        let script = """
        (function() {
            var el = document.querySelector('\(safeSelector)');
            if (!el) return 'not_found';
            el.focus();
            el.value = '\(safeText)';
            el.dispatchEvent(new Event('input', {bubbles: true}));
            el.dispatchEvent(new Event('change', {bubbles: true}));
            return 'typed';
        })()
        """
        let result = await evaluateJS(script)
        return result == "typed"
    }

    public func getPageContent() async -> String? {
        return await evaluateJS("document.documentElement.outerHTML")
    }

    public func getPageTitle() async -> String? {
        return await evaluateJS("document.title")
    }

    // MARK: - Zoom

    public func zoomIn() { zoomLevel = min(zoomLevel + 0.1, 3.0); applyZoom() }
    public func zoomOut() { zoomLevel = max(zoomLevel - 0.1, 0.3); applyZoom() }
    public func resetZoom() { zoomLevel = 1.0; applyZoom() }
    private func applyZoom() { webView?.pageZoom = zoomLevel }

    // MARK: - Cache / Hard Reset

    public func clearCache() {
        let dataStore = WKWebsiteDataStore.default()
        let types: Set<String> = [
            WKWebsiteDataTypeDiskCache,
            WKWebsiteDataTypeMemoryCache,
            WKWebsiteDataTypeCookies,
            WKWebsiteDataTypeLocalStorage,
            WKWebsiteDataTypeSessionStorage,
            WKWebsiteDataTypeIndexedDBDatabases,
            WKWebsiteDataTypeWebSQLDatabases
        ]
        dataStore.removeData(ofTypes: types, modifiedSince: .distantPast) { [weak self] in
            Task { @MainActor in
                self?.appendConsoleLog(ConsoleLogEntry(
                    level: .info,
                    message: "Cache, cookies, and site data cleared",
                    source: nil, line: nil, timestamp: Date()
                ))
            }
        }
    }

    public func hardReset() {
        clearCache()
        clearConsoleLogs()
        clearNetworkRequests()
        webView?.load(URLRequest(url: URL(string: "about:blank")!))
        currentURL = ""
        pageTitle = ""
        lastScreenshot = nil
        lastScreenshotTimestamp = nil
    }

    // MARK: - Console Log Management

    func appendConsoleLog(_ entry: ConsoleLogEntry) {
        consoleLogs.append(entry)
        if consoleLogs.count > maxLogEntries {
            consoleLogs.removeFirst(consoleLogs.count - maxLogEntries)
        }
    }

    func appendJSError(_ error: JSError) {
        jsErrors.append(error)
        let errorLog = ConsoleLogEntry(
            level: .error,
            message: error.message,
            source: error.source,
            line: error.line,
            timestamp: error.timestamp
        )
        appendConsoleLog(errorLog)
    }

    func appendNetworkRequest(_ request: NetworkRequest) {
        networkRequests.append(request)
        if networkRequests.count > maxLogEntries {
            networkRequests.removeFirst(networkRequests.count - maxLogEntries)
        }
    }

    public func clearConsoleLogs() {
        consoleLogs.removeAll()
        jsErrors.removeAll()
    }

    public func clearNetworkRequests() {
        networkRequests.removeAll()
    }

    public func filteredLogs(level: ConsoleLogLevel?) -> [ConsoleLogEntry] {
        guard let level else { return consoleLogs }
        return consoleLogs.filter { $0.level == level }
    }

    public func consoleLogsAsText(level: ConsoleLogLevel? = nil, lastN: Int = 100) -> String {
        let logs = filteredLogs(level: level).suffix(lastN)
        if logs.isEmpty { return "(no console logs)" }
        return logs.map { entry in
            let src = entry.source.map { " (\($0):\(entry.line ?? 0))" } ?? ""
            return "[\(entry.level.rawValue.uppercased())]\(src) \(entry.message)"
        }.joined(separator: "\n")
    }

    // MARK: - Page State Updates

    func updatePageState(url: String?, title: String?, loading: Bool) {
        if let url { currentURL = url }
        if let title { pageTitle = title }
        isLoading = loading
    }

    func updateNavState(canGoBack: Bool, canGoForward: Bool) {
        self.canGoBack = canGoBack
        self.canGoForward = canGoForward
    }
}

// MARK: - BrowserTab

@MainActor
public final class BrowserTab: ObservableObject, Identifiable {
    public let id = UUID()
    @Published public var store: BrowserSessionStore

    public var label: String {
        if !store.pageTitle.isEmpty { return store.pageTitle }
        if !store.currentURL.isEmpty {
            if let host = URL(string: store.currentURL)?.host { return host }
            return store.currentURL
        }
        return "New Tab"
    }

    public init(url: String? = nil) {
        self.store = BrowserSessionStore()
        if let url { store.navigate(to: url) }
    }
}

// MARK: - BrowserTabManager

@MainActor
public final class BrowserTabManager: ObservableObject {
    @Published public var tabs: [BrowserTab] = []
    @Published public var activeTabId: UUID?
    @Published public var showBookmarksPanel: Bool = false
    @Published public var showHistoryPanel: Bool = false

    @Published public var bookmarks: [BrowserBookmark] = [] {
        didSet { persistBookmarks() }
    }
    @Published public var history: [BrowserHistoryEntry] = [] {
        didSet { persistHistory() }
    }

    private let maxHistoryEntries = 500

    static let browserShouldOpenNotification = Notification.Name("codigoBrowserShouldOpen")

    public var activeTab: BrowserTab? {
        guard let id = activeTabId else { return tabs.first }
        return tabs.first { $0.id == id }
    }

    public var activeStore: BrowserSessionStore? {
        activeTab?.store
    }

    public init() {
        loadBookmarks()
        loadHistory()
        addNewTab()
    }

    // MARK: - Tab Management

    @discardableResult
    public func addNewTab(url: String? = nil) -> BrowserTab {
        let tab = BrowserTab(url: url)
        tabs.append(tab)
        activeTabId = tab.id
        return tab
    }

    public func closeTab(id: UUID) {
        guard tabs.count > 1 else { return }
        if let idx = tabs.firstIndex(where: { $0.id == id }) {
            let wasActive = activeTabId == id
            tabs.remove(at: idx)
            if wasActive {
                let newIdx = min(idx, tabs.count - 1)
                activeTabId = tabs[newIdx].id
            }
        }
    }

    public func selectTab(id: UUID) {
        activeTabId = id
    }

    // MARK: - Navigate (on active tab, opens browser)

    public func navigateActiveTab(to url: String) {
        if let tab = activeTab {
            tab.store.navigate(to: url)
        } else {
            addNewTab(url: url)
        }
        NotificationCenter.default.post(name: Self.browserShouldOpenNotification, object: nil)
    }

    // MARK: - Bookmarks

    public func addBookmark() {
        guard let store = activeStore, !store.currentURL.isEmpty else { return }
        let title = store.pageTitle.isEmpty ? store.currentURL : store.pageTitle
        if !bookmarks.contains(where: { $0.url == store.currentURL }) {
            bookmarks.append(BrowserBookmark(title: title, url: store.currentURL))
        }
    }

    public func removeBookmark(id: UUID) {
        bookmarks.removeAll { $0.id == id }
    }

    public func isBookmarked(_ url: String) -> Bool {
        bookmarks.contains { $0.url == url }
    }

    private func persistBookmarks() {
        if let data = try? JSONEncoder().encode(bookmarks) {
            UserDefaults.standard.set(data, forKey: "browser_bookmarks")
        }
    }

    private func loadBookmarks() {
        guard let data = UserDefaults.standard.data(forKey: "browser_bookmarks"),
              let saved = try? JSONDecoder().decode([BrowserBookmark].self, from: data) else { return }
        bookmarks = saved
    }

    // MARK: - History

    public func recordHistory(url: String, title: String) {
        let entry = BrowserHistoryEntry(title: title.isEmpty ? url : title, url: url)
        history.insert(entry, at: 0)
        if history.count > maxHistoryEntries {
            history = Array(history.prefix(maxHistoryEntries))
        }
    }

    public func clearHistory() {
        history.removeAll()
    }

    private func persistHistory() {
        if let data = try? JSONEncoder().encode(history) {
            UserDefaults.standard.set(data, forKey: "browser_history")
        }
    }

    private func loadHistory() {
        guard let data = UserDefaults.standard.data(forKey: "browser_history"),
              let saved = try? JSONDecoder().decode([BrowserHistoryEntry].self, from: data) else { return }
        history = saved
    }
}

// MARK: - CoderEngine.BrowserBridge Conformance (on TabManager, delegates to active tab)

extension BrowserTabManager: CoderEngine.BrowserBridge {
    public func navigate(to url: String) async {
        navigateActiveTab(to: url)
    }

    public func goBack() async { activeStore?.goBack() }
    public func goForward() async { activeStore?.goForward() }
    public func reload() async { activeStore?.reload() }

    public func takeScreenshot() async -> Data? {
        await activeStore?.takeScreenshot()
    }

    public func getConsoleLogs(level: String?) -> String {
        let logLevel = level.flatMap { ConsoleLogLevel(rawValue: $0) }
        return activeStore?.consoleLogsAsText(level: logLevel) ?? "(no active tab)"
    }

    public func clearConsoleLogs() {
        activeStore?.clearConsoleLogs()
    }

    public func evaluateJS(_ script: String) async -> String? {
        await activeStore?.evaluateJS(script)
    }

    public func click(selector: String) async -> Bool {
        await activeStore?.click(selector: selector) ?? false
    }

    public func type(selector: String, text: String) async -> Bool {
        await activeStore?.type(selector: selector, text: text) ?? false
    }

    public func getPageContent() async -> String? {
        await activeStore?.getPageContent()
    }

    public func getPageTitle() async -> String? {
        await activeStore?.getPageTitle()
    }

    public func getCurrentURL() -> String? {
        guard let url = activeStore?.currentURL, !url.isEmpty else { return nil }
        return url
    }
}
