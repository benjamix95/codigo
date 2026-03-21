import AppKit
import SwiftUI
import XCTest
@testable import CoderIDE

@MainActor
final class ComposerTextViewFocusTests: XCTestCase {
    func testUpdateCoordinatorRefreshesSubmitHandlerToLatestClosure() {
        var legacySubmitCount = 0
        var latestSubmitCount = 0
        let textView = ComposerNativeNSTextView(frame: NSRect(x: 0, y: 0, width: 200, height: 40))

        let initial = ComposerTextView(
            text: .constant("legacy"),
            isFocused: .constant(false),
            minHeight: 22,
            maxHeight: 140,
            onSubmit: { legacySubmitCount += 1 }
        )
        let updated = ComposerTextView(
            text: .constant("latest"),
            isFocused: .constant(false),
            minHeight: 22,
            maxHeight: 140,
            onSubmit: { latestSubmitCount += 1 }
        )

        let coordinator = initial.makeCoordinator()
        coordinator.textView = textView

        ComposerTextViewUpdateCoordinator.applyViewState(
            parent: initial,
            coordinator: coordinator
        )
        ComposerTextViewUpdateCoordinator.applyViewState(
            parent: updated,
            coordinator: coordinator
        )

        textView.keyDown(with: makeReturnKeyEvent())

        XCTAssertEqual(legacySubmitCount, 0)
        XCTAssertEqual(latestSubmitCount, 1)
        XCTAssertEqual(textView.string, "latest")
    }

    func testUpdateCoordinatorRefreshesTextBindingForSubsequentEdits() {
        var legacyText = ""
        var latestText = ""
        let textView = ComposerNativeNSTextView(frame: NSRect(x: 0, y: 0, width: 200, height: 40))

        let initial = ComposerTextView(
            text: Binding(
                get: { legacyText },
                set: { legacyText = $0 }
            ),
            isFocused: .constant(false),
            minHeight: 22,
            maxHeight: 140,
            onSubmit: {}
        )
        let updated = ComposerTextView(
            text: Binding(
                get: { latestText },
                set: { latestText = $0 }
            ),
            isFocused: .constant(false),
            minHeight: 22,
            maxHeight: 140,
            onSubmit: {}
        )

        let coordinator = initial.makeCoordinator()
        coordinator.textView = textView

        ComposerTextViewUpdateCoordinator.applyViewState(
            parent: initial,
            coordinator: coordinator
        )
        ComposerTextViewUpdateCoordinator.applyViewState(
            parent: updated,
            coordinator: coordinator
        )

        textView.string = "Nuovo messaggio"
        coordinator.textDidChange(Notification(name: NSText.didChangeNotification, object: textView))

        XCTAssertEqual(legacyText, "")
        XCTAssertEqual(latestText, "Nuovo messaggio")
    }

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

    private func makeReturnKeyEvent() -> NSEvent {
        guard let event = NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: "\r",
            charactersIgnoringModifiers: "\r",
            isARepeat: false,
            keyCode: 36
        ) else {
            XCTFail("Impossibile creare l'evento Return per il test")
            fatalError()
        }
        return event
    }
}
