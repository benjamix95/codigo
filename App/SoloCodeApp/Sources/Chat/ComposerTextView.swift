import AppKit
import SwiftUI

struct ComposerTextView: NSViewRepresentable {
    @Binding var text: String
    @Binding var isFocused: Bool
    let minHeight: CGFloat
    let maxHeight: CGFloat
    let onSubmit: () -> Void

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true

        let textView = ComposerNativeNSTextView()
        textView.drawsBackground = false
        textView.isRichText = false
        textView.font = .systemFont(ofSize: 13)
        textView.textColor = .labelColor
        textView.delegate = context.coordinator
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainerInset = NSSize(width: 0, height: 2)
        textView.onSubmit = onSubmit
        textView.string = text

        scrollView.documentView = textView
        context.coordinator.scrollView = scrollView
        context.coordinator.textView = textView
        context.coordinator.updateHeight(minHeight: minHeight, maxHeight: maxHeight)

        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = context.coordinator.textView else { return }
        if textView.string != text {
            textView.string = text
        }
        if textView.onSubmit == nil {
            textView.onSubmit = onSubmit
        }
        context.coordinator.updateHeight(minHeight: minHeight, maxHeight: maxHeight)

        // Defer focus changes to avoid modifying state during view update
        let shouldFocus = isFocused
        let isCurrentlyFocused = textView.window?.firstResponder === textView
        if shouldFocus != isCurrentlyFocused {
            DispatchQueue.main.async {
                if shouldFocus {
                    textView.window?.makeFirstResponder(textView)
                } else {
                    textView.window?.makeFirstResponder(nil)
                }
            }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: ComposerTextView
        weak var scrollView: NSScrollView?
        weak var textView: ComposerNativeNSTextView?

        init(parent: ComposerTextView) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let textView else { return }
            parent.text = textView.string
            updateHeight(minHeight: parent.minHeight, maxHeight: parent.maxHeight)
        }

        func textDidBeginEditing(_ notification: Notification) {
            if !parent.isFocused {
                parent.isFocused = true
            }
        }

        func textDidEndEditing(_ notification: Notification) {
            if parent.isFocused {
                parent.isFocused = false
            }
        }

        func updateHeight(minHeight: CGFloat, maxHeight: CGFloat) {
            guard let scrollView, let textView else { return }
            guard let textContainer = textView.textContainer else { return }
            let fitting = textView.layoutManager?.usedRect(for: textContainer).height ?? minHeight
            let nextHeight = max(minHeight, min(maxHeight, fitting + 8))
            if abs(scrollView.frame.height - nextHeight) > 0.5 {
                scrollView.constraints
                    .filter { $0.firstAttribute == .height }
                    .forEach { scrollView.removeConstraint($0) }
                scrollView.heightAnchor.constraint(equalToConstant: nextHeight).isActive = true
            }
            scrollView.hasVerticalScroller = fitting + 8 > maxHeight
        }
    }
}

final class ComposerNativeNSTextView: NSTextView {
    var onSubmit: (() -> Void)?

    override func keyDown(with event: NSEvent) {
        let chars = event.charactersIgnoringModifiers ?? ""
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let isReturn = chars == "\r" || chars == "\n"

        if isReturn {
            if flags.contains(.shift) {
                self.insertNewline(nil)
                return
            }
            if !flags.contains(.command) && !flags.contains(.option) && !flags.contains(.control) {
                onSubmit?()
                return
            }
        }

        super.keyDown(with: event)
    }
}
