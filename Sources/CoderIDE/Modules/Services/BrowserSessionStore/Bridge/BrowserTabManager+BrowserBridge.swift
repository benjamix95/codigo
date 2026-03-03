import Foundation
import CoderEngine

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
