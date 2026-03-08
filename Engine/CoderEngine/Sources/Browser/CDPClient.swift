import Foundation
import Logging

/// Chrome DevTools Protocol (CDP) client for controlling an external Chrome/Chromium browser
/// via WebSocket. Provides advanced debugging capabilities beyond WKWebView.
///
/// Usage:
///   1. Ensure Chrome or Chromium is installed
///   2. Call `launch()` to start Chrome with remote debugging enabled
///   3. Use `send(method:params:)` to execute CDP commands
///   4. Call `disconnect()` when done
public actor CDPClient {
    private static let logger = Logger(label: "com.codigo.CDPClient")

    private let debuggingPort: Int
    private var process: Process?
    private var webSocketTask: URLSessionWebSocketTask?
    private var messageId: Int = 0
    private var pendingCallbacks: [Int: CheckedContinuation<[String: Any], Error>] = [:]
    private var eventHandlers: [String: @Sendable ([String: Any]) -> Void] = [:]
    private var isConnected: Bool = false
    private let session = URLSession(configuration: .default)

    public init(port: Int = 9222) {
        self.debuggingPort = port
    }

    // MARK: - Chrome Lifecycle

    /// Launch Chrome with remote debugging enabled.
    /// Returns true if Chrome was started and CDP connection established.
    public func launch(url: String? = nil) async throws -> Bool {
        let chromePaths = [
            "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome",
            "/Applications/Chromium.app/Contents/MacOS/Chromium",
            "/Applications/Google Chrome Canary.app/Contents/MacOS/Google Chrome Canary",
            "/usr/bin/google-chrome",
            "/usr/bin/chromium"
        ]

        guard let chromePath = chromePaths.first(where: { FileManager.default.fileExists(atPath: $0) }) else {
            Self.logger.warning("Chrome/Chromium not found on the system")
            return false
        }

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: chromePath)
        var args = [
            "--remote-debugging-port=\(debuggingPort)",
            "--no-first-run",
            "--no-default-browser-check",
            "--disable-background-networking",
            "--disable-sync",
            "--disable-translate",
            "--metrics-recording-only",
            "--disable-default-apps"
        ]
        if let url { args.append(url) }
        proc.arguments = args
        proc.standardOutput = FileHandle.nullDevice
        proc.standardError = FileHandle.nullDevice

        do {
            try proc.run()
            self.process = proc
        } catch {
            Self.logger.error("Failed to launch Chrome: \(error.localizedDescription)")
            return false
        }

        try await Task.sleep(for: .seconds(2))

        return try await connect()
    }

    /// Connect to an already-running Chrome instance.
    public func connect() async throws -> Bool {
        let listURL = URL(string: "http://127.0.0.1:\(debuggingPort)/json")!
        let (data, _) = try await session.data(from: listURL)

        guard let targets = try JSONSerialization.jsonObject(with: data) as? [[String: Any]],
              let page = targets.first(where: { ($0["type"] as? String) == "page" }),
              let wsURLString = page["webSocketDebuggerUrl"] as? String,
              let wsURL = URL(string: wsURLString) else {
            Self.logger.warning("No page target found on CDP port \(debuggingPort)")
            return false
        }

        let wsTask = session.webSocketTask(with: wsURL)
        wsTask.resume()
        self.webSocketTask = wsTask
        self.isConnected = true

        Task { await receiveMessages() }

        Self.logger.info("CDP connected to \(wsURLString)")
        return true
    }

    /// Disconnect from Chrome and optionally kill the process.
    public func disconnect(killProcess: Bool = false) {
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
        isConnected = false

        for (_, continuation) in pendingCallbacks {
            continuation.resume(throwing: CDPError.disconnected)
        }
        pendingCallbacks.removeAll()

        if killProcess {
            process?.terminate()
            process = nil
        }
    }

    // MARK: - CDP Commands

    /// Send a CDP command and wait for the result.
    public func send(method: String, params: [String: Any] = [:]) async throws -> [String: Any] {
        guard isConnected, let ws = webSocketTask else {
            throw CDPError.notConnected
        }

        messageId += 1
        let id = messageId

        var message: [String: Any] = [
            "id": id,
            "method": method
        ]
        if !params.isEmpty {
            message["params"] = params
        }

        let data = try JSONSerialization.data(withJSONObject: message)
        let jsonString = String(data: data, encoding: .utf8) ?? "{}"

        try await ws.send(.string(jsonString))

        return try await withCheckedThrowingContinuation { continuation in
            self.pendingCallbacks[id] = continuation
        }
    }

    /// Register a handler for CDP events.
    public func on(event: String, handler: @escaping @Sendable ([String: Any]) -> Void) {
        eventHandlers[event] = handler
    }

    // MARK: - Convenience Methods

    /// Navigate to a URL.
    public func navigate(to url: String) async throws {
        _ = try await send(method: "Page.navigate", params: ["url": url])
    }

    /// Capture a screenshot as base64-encoded PNG.
    public func captureScreenshot(format: String = "png", quality: Int? = nil) async throws -> String {
        var params: [String: Any] = ["format": format]
        if let quality { params["quality"] = quality }
        let result = try await send(method: "Page.captureScreenshot", params: params)
        return result["data"] as? String ?? ""
    }

    /// Evaluate JavaScript expression.
    public func evaluate(expression: String) async throws -> Any? {
        let result = try await send(method: "Runtime.evaluate", params: [
            "expression": expression,
            "returnByValue": true
        ])
        if let exResult = result["result"] as? [String: Any] {
            return exResult["value"]
        }
        return nil
    }

    /// Enable console log capture.
    public func enableConsoleLog() async throws {
        _ = try await send(method: "Log.enable")
        _ = try await send(method: "Runtime.enable")
    }

    /// Enable network tracking.
    public func enableNetwork() async throws {
        _ = try await send(method: "Network.enable")
    }

    /// Get the page title.
    public func getPageTitle() async throws -> String {
        let result = try await evaluate(expression: "document.title")
        return result as? String ?? ""
    }

    /// Get the current URL.
    public func getCurrentURL() async throws -> String {
        let result = try await evaluate(expression: "window.location.href")
        return result as? String ?? ""
    }

    // MARK: - WebSocket Message Loop

    private func receiveMessages() async {
        guard let ws = webSocketTask else { return }

        while isConnected {
            do {
                let message = try await ws.receive()
                switch message {
                case .string(let text):
                    guard let data = text.data(using: .utf8),
                          let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                        continue
                    }
                    handleMessage(json)
                case .data(let data):
                    guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                        continue
                    }
                    handleMessage(json)
                @unknown default:
                    continue
                }
            } catch {
                if isConnected {
                    Self.logger.warning("CDP WebSocket receive error: \(error.localizedDescription)")
                    isConnected = false
                }
                break
            }
        }
    }

    private func handleMessage(_ json: [String: Any]) {
        if let id = json["id"] as? Int, let continuation = pendingCallbacks.removeValue(forKey: id) {
            if let error = json["error"] as? [String: Any] {
                let message = error["message"] as? String ?? "Unknown CDP error"
                continuation.resume(throwing: CDPError.protocolError(message))
            } else {
                let result = json["result"] as? [String: Any] ?? [:]
                continuation.resume(returning: result)
            }
        }

        if let method = json["method"] as? String {
            let params = json["params"] as? [String: Any] ?? [:]
            eventHandlers[method]?(params)
        }
    }
}

// MARK: - Errors

public enum CDPError: Error, LocalizedError {
    case notConnected
    case disconnected
    case chromeNotFound
    case protocolError(String)
    case timeout

    public var errorDescription: String? {
        switch self {
        case .notConnected: return "Not connected to Chrome DevTools Protocol"
        case .disconnected: return "CDP connection was disconnected"
        case .chromeNotFound: return "Chrome or Chromium not found on the system"
        case .protocolError(let msg): return "CDP protocol error: \(msg)"
        case .timeout: return "CDP command timed out"
        }
    }
}
