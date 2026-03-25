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
                default:
                    break
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

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void) {
            decisionHandler(.allow)
        }
    }
}
