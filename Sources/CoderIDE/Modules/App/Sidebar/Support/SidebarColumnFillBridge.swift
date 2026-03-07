import AppKit
import SwiftUI

struct SidebarColumnFillBridge: NSViewRepresentable {
    func makeNSView(context: Context) -> SidebarColumnFillNSView {
        let view = SidebarColumnFillNSView()
        view.applyColumnChromeFix()
        return view
    }

    func updateNSView(_ nsView: SidebarColumnFillNSView, context: Context) {
        nsView.applyColumnChromeFix()
    }
}

final class SidebarColumnFillNSView: NSView {
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        applyColumnChromeFix()
    }

    override func layout() {
        super.layout()
        applyColumnChromeFix()
    }

    func applyColumnChromeFix() {
        DispatchQueue.main.async { [weak self] in
            self?.rewriteAncestorChrome()
        }
    }

    private func rewriteAncestorChrome() {
        var current: NSView? = self
        var depth = 0

        while let view = current, depth < 10 {
            normalize(view)
            current = view.superview
            depth += 1
        }
    }

    private func normalize(_ view: NSView) {
        view.wantsLayer = true
        view.layer?.cornerRadius = 0
        view.layer?.maskedCorners = []
        view.layer?.masksToBounds = false
        view.layer?.backgroundColor = NSColor.clear.cgColor

        if let effectView = view as? NSVisualEffectView {
            effectView.material = .sidebar
            effectView.blendingMode = .behindWindow
            effectView.state = .active
            effectView.maskImage = nil
        }
    }
}
