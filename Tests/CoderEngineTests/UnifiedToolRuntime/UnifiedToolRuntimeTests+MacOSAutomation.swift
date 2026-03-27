import XCTest
@testable import CoderEngine

@MainActor
private final class FakeMacOSAutomationBridge: MacOSAutomationBridge {
    var focusReturnValue = true
    var screenshotData: Data?
    var appleScriptResult: Result<String, MacOSAutomationBridgeError> = .success("")
    var clickReturnValue = true
    var pressKeyReturnValue = true
    var typeTextReturnValue = true
    var listedElements: [MacOSUIElementSnapshot] = []

    func focusApp(appName: String?, bundleID: String?) async -> Bool {
        focusReturnValue
    }

    func captureScreenshot(target: String, appName: String?, bundleID: String?) async -> Data? {
        screenshotData
    }

    func runAppleScript(_ script: String, appName: String?, bundleID: String?, timeoutMs: Int?) async -> Result<String, MacOSAutomationBridgeError> {
        appleScriptResult
    }

    func click(x: Double, y: Double) async -> Bool {
        clickReturnValue
    }

    func pressKey(key: String, modifiers: [String]) async -> Bool {
        pressKeyReturnValue
    }

    func typeText(_ text: String) async -> Bool {
        typeTextReturnValue
    }

    func listUIElements(appName: String?, bundleID: String?, scope: String, limit: Int) async -> [MacOSUIElementSnapshot] {
        Array(listedElements.prefix(limit))
    }
}

extension UnifiedToolRuntimeTests {
    func testMacOSCaptureScreenshotReturnsInlineDataURL() async {
        let bridge = await MainActor.run {
            let bridge = FakeMacOSAutomationBridge()
            bridge.screenshotData = Data([0x89, 0x50, 0x4E, 0x47])
            return bridge
        }
        let runtime = UnifiedToolRuntime(macOSAutomationBridge: bridge)
        let (call, ctx) = makeCall(name: "macos_capture_screenshot", args: ["target": "front_window"])
        let events = await runtime.execute(call, context: ctx)
        let completed = extractLastPayload(events)

        XCTAssertEqual(completed?["status"], "completed")
        XCTAssertEqual(completed?["title"], "macOS screenshot captured")
        XCTAssertTrue((completed?["output"] ?? "").hasPrefix("data:image/png;base64,"))
    }

    func testMacOSRunAppleScriptReturnsOutput() async {
        let bridge = await MainActor.run {
            let bridge = FakeMacOSAutomationBridge()
            bridge.appleScriptResult = .success("ok")
            return bridge
        }
        let runtime = UnifiedToolRuntime(macOSAutomationBridge: bridge)
        let (call, ctx) = makeCall(name: "macos_run_applescript", args: ["script": "return 1"])
        let events = await runtime.execute(call, context: ctx)
        let completed = extractLastPayload(events)

        XCTAssertEqual(completed?["status"], "completed")
        XCTAssertEqual(completed?["output"], "ok")
    }

    func testMacOSListUIElementsSerializesStructuredOutput() async {
        let bridge = await MainActor.run {
            let bridge = FakeMacOSAutomationBridge()
            bridge.listedElements = [
                MacOSUIElementSnapshot(
                    role: "AXButton",
                    name: "Done",
                    help: "Close panel",
                    x: 100,
                    y: 200,
                    width: 40,
                    height: 22
                )
            ]
            return bridge
        }
        let runtime = UnifiedToolRuntime(macOSAutomationBridge: bridge)
        let (call, ctx) = makeCall(name: "macos_list_ui_elements", args: ["scope": "front_window", "limit": "10"])
        let events = await runtime.execute(call, context: ctx)
        let completed = extractLastPayload(events)

        XCTAssertEqual(completed?["status"], "completed")
        XCTAssertTrue((completed?["output"] ?? "").contains("\"AXButton\""))
        XCTAssertTrue((completed?["output"] ?? "").contains("\"Done\""))
    }

    func testMacOSAutomationUnavailableReturnsTransportFailure() async {
        let runtime = UnifiedToolRuntime()
        let (call, ctx) = makeCall(name: "macos_focus_app")
        let events = await runtime.execute(call, context: ctx)
        let completed = extractLastPayload(events)

        XCTAssertEqual(completed?["status"], "failed")
        XCTAssertEqual(completed?["error_code"], "transport")
    }

    func testMacOSClickValidatesCoordinates() async {
        let bridge = await MainActor.run { FakeMacOSAutomationBridge() }
        let runtime = UnifiedToolRuntime(macOSAutomationBridge: bridge)
        let (call, ctx) = makeCall(name: "macos_click", args: ["x": "abc", "y": "10"])
        let events = await runtime.execute(call, context: ctx)
        let completed = extractLastPayload(events)

        XCTAssertEqual(completed?["status"], "failed")
        XCTAssertEqual(completed?["error_code"], "validation")
    }
}
