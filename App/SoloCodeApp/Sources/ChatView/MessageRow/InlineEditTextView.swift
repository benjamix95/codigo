import AppKit
import SwiftUI

// MARK: - Inline Edit Text View

/// NSTextView wrapper for inline message editing.
/// Enter sends, Shift+Enter adds newline, Esc cancels.
struct InlineEditTextView: NSViewRepresentable {
    @Binding var text: String
    var onSubmit: () -> Void
    var onCancel: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false

        let textView = EditableNSTextView()
        textView.delegate = context.coordinator
        textView.editDelegate = context.coordinator
        textView.isEditable = true
        textView.isSelectable = true
        textView.isRichText = false
        textView.allowsUndo = true
        textView.drawsBackground = false
        textView.font = .systemFont(ofSize: 13.5, weight: .regular)
        textView.textColor = .labelColor
        textView.insertionPointColor = .labelColor
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.textContainerInset = NSSize(width: 2, height: 2)
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.lineFragmentPadding = 0
        textView.setContentHuggingPriority(.defaultLow, for: .horizontal)
        textView.string = text

        scrollView.documentView = textView
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        // Auto-focus
        DispatchQueue.main.async {
            textView.window?.makeFirstResponder(textView)
            textView.setSelectedRange(NSRange(location: textView.string.count, length: 0))
        }

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        if textView.string != text {
            textView.string = text
        }
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, NSTextViewDelegate {
        let parent: InlineEditTextView

        init(parent: InlineEditTextView) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.text = textView.string
        }

        // Called by EditableNSTextView on Enter key
        func handleReturn() {
            parent.onSubmit()
        }

        // Called by EditableNSTextView on Esc key
        func handleCancel() {
            parent.onCancel()
        }
    }
}

// MARK: - Editable NSTextView

/// Custom NSTextView that intercepts Enter and Esc.
final class EditableNSTextView: NSTextView {
    weak var editDelegate: InlineEditTextView.Coordinator?

    override func keyDown(with event: NSEvent) {
        let isReturn = event.keyCode == 36 // Return
        let isShift = event.modifierFlags.contains(.shift)
        let isEsc = event.keyCode == 53 // Escape

        if isReturn && !isShift {
            editDelegate?.handleReturn()
            return
        }
        if isEsc {
            editDelegate?.handleCancel()
            return
        }
        super.keyDown(with: event)
    }
}
