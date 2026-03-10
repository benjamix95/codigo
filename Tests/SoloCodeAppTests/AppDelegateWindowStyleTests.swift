import AppKit
import XCTest
@testable import CoderIDE

@MainActor
final class AppDelegateWindowStyleTests: XCTestCase {
    func testApplyMainWindowStylePreservesStandardWindowChrome() {
        let window = makeWindow()
        let toolbar = NSToolbar(identifier: "test-toolbar")
        toolbar.showsBaselineSeparator = true
        window.toolbar = toolbar
        window.title = "Codigo"
        window.subtitle = "Subtitle"
        window.titleVisibility = .visible
        window.titlebarAppearsTransparent = true
        window.styleMask.insert(.fullSizeContentView)

        AppDelegate.applyMainWindowStyle(window)

        XCTAssertEqual(window.title, "")
        XCTAssertEqual(window.titleVisibility, .hidden)
        XCTAssertTrue(window.titlebarAppearsTransparent)
        XCTAssertTrue(window.styleMask.contains(.fullSizeContentView))
        XCTAssertNotNil(window.toolbar)
        XCTAssertFalse(window.toolbar?.showsBaselineSeparator ?? true)
    }

    func testApplyMainWindowStyleKeepsStandardTrafficLightsAvailable() {
        let window = makeWindow()

        AppDelegate.applyMainWindowStyle(window)

        XCTAssertNotNil(window.standardWindowButton(.closeButton))
        XCTAssertNotNil(window.standardWindowButton(.miniaturizeButton))
        XCTAssertNotNil(window.standardWindowButton(.zoomButton))
    }

    func testApplyMainWindowStyleUsesSidebarBackgroundFill() {
        let window = makeWindow()

        AppDelegate.applyMainWindowStyle(window)

        XCTAssertTrue(window.backgroundColor.isEqual(DesignSystem.AppKit.sidebarBackground))
    }

    func testApplyMainWindowStyleHidesStandardTrafficLights() {
        let window = makeWindow()

        AppDelegate.applyMainWindowStyle(window)

        XCTAssertTrue(window.standardWindowButton(.closeButton)?.isHidden ?? false)
        XCTAssertTrue(window.standardWindowButton(.miniaturizeButton)?.isHidden ?? false)
        XCTAssertTrue(window.standardWindowButton(.zoomButton)?.isHidden ?? false)
    }

    private func makeWindow() -> NSWindow {
        NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1280, height: 800),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
    }
}
