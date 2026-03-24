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

    func makeNSView(context: Context) -> InlineEditContainerView {
        let container = InlineEditContainerView()
        let textView = container.textView
        textView.delegate = context.coordinator
        textView.editDelegate = context.coordinator
        textView.string = text

        // Auto-focus and place cursor at end
        DispatchQueue.main.async {
            textView.window?.makeFirstResponder(textView)
            textView.setSelectedRange(NSRange(location: textView.string.count, length: 0))
        }

        return container
    }

    func updateNSView(_ container: InlineEditContainerView, context: Context) {
        if container.textView.string != text {
            container.textView.string = text
            container.invalidateIntrinsicContentSize()
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
            // Resize container to fit content
            if let container = textView.superview?.superview as? InlineEditContainerView {
                container.invalidateIntrinsicContentSize()
            }
        }

        func handleReturn() { parent.onSubmit() }
        func handleCancel() { parent.onCancel() }
    }
}

// MARK: - Container View

/// Wraps NSScrollView + NSTextView and reports intrinsic content size to SwiftUI.
final class InlineEditContainerView: NSView {
    let scrollView = NSScrollView()
    let textView = EditableNSTextView()

    private let maxHeight: CGFloat = 200
    private let minHeight: CGFloat = 22

    override init(frame: NSRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false

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
        textView.textContainerInset = .zero
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.lineFragmentPadding = 0

        scrollView.documentView = textView
        addSubview(scrollView)

        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    override var intrinsicContentSize: NSSize {
        guard let layoutManager = textView.layoutManager,
              let textContainer = textView.textContainer else {
            return NSSize(width: NSView.noIntrinsicMetric, height: minHeight)
        }
        layoutManager.ensureLayout(for: textContainer)
        let textHeight = layoutManager.usedRect(for: textContainer).height
        let height = min(max(textHeight + 4, minHeight), maxHeight)
        return NSSize(width: NSView.noIntrinsicMetric, height: height)
    }
}

// MARK: - Editable NSTextView

/// Custom NSTextView that intercepts Enter and Esc.
final class EditableNSTextView: NSTextView {
    weak var editDelegate: InlineEditTextView.Coordinator?

    override func keyDown(with event: NSEvent) {
        let isReturn = event.keyCode == 36
        let isShift = event.modifierFlags.contains(.shift)
        let isEsc = event.keyCode == 53

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
