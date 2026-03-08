import Foundation
import AppKit
import Combine
import WebKit

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
        let safeSelector = selector.replacingOccurrences(of: "'", with: "\\'")
        let script = """
        (function() {
            var el = document.querySelector('\(safeSelector)');
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
        if let blankURL = URL(string: "about:blank") {
            webView?.load(URLRequest(url: blankURL))
        }
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
