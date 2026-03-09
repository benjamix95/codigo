import AppKit
import XCTest
@testable import CoderIDE

@MainActor
final class ComposerTextViewFocusTests: XCTestCase {
    func testDeferredBlurDoesNotClearFocusFromAnotherControl() {
        let window = makeWindow()
        let composer = ComposerNativeNSTextView(frame: NSRect(x: 0, y: 0, width: 200, height: 40))
        let otherField = NSTextField(string: "")
        let stack = NSStackView(views: [composer, otherField])
        stack.orientation = .vertical
        window.contentView = stack
        window.makeKeyAndOrderFront(nil)

        XCTAssertTrue(window.makeFirstResponder(composer))
        XCTAssertTrue(window.firstResponder === composer)

        XCTAssertTrue(window.makeFirstResponder(otherField))
        XCTAssertTrue(window.firstResponder === otherField.currentEditor())

        ComposerTextViewFocusCoordinator.applyDeferredFocusChange(
            shouldFocus: false,
            textView: composer
        )

        XCTAssertTrue(window.firstResponder === otherField.currentEditor())
    }

    func testDeferredBlurClearsComposerWhenItStillOwnsFocus() {
        let window = makeWindow()
        let composer = ComposerNativeNSTextView(frame: NSRect(x: 0, y: 0, width: 200, height: 40))
        window.contentView = composer
        window.makeKeyAndOrderFront(nil)

        XCTAssertTrue(window.makeFirstResponder(composer))
        XCTAssertTrue(window.firstResponder === composer)

        ComposerTextViewFocusCoordinator.applyDeferredFocusChange(
            shouldFocus: false,
            textView: composer
        )

        XCTAssertFalse(window.firstResponder === composer)
    }

    private func makeWindow() -> NSWindow {
        NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 200),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
    }
}
