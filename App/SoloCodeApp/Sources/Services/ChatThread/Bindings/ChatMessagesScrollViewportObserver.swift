import AppKit
import SwiftUI

struct ChatMessagesScrollViewportObserver: NSViewRepresentable {
    let onViewportChange: (Bool) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onViewportChange: onViewportChange)
    }

    func makeNSView(context: Context) -> ObserverView {
        let view = ObserverView()
        view.coordinator = context.coordinator
        return view
    }

    func updateNSView(_ nsView: ObserverView, context: Context) {
        context.coordinator.onViewportChange = onViewportChange
        nsView.coordinator = context.coordinator
        nsView.attachIfNeeded()
    }

    final class ObserverView: NSView {
        weak var coordinator: Coordinator?

        override func viewDidMoveToSuperview() {
            super.viewDidMoveToSuperview()
            attachIfNeeded()
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            attachIfNeeded()
        }

        func attachIfNeeded() {
            coordinator?.attach(to: enclosingScrollView())
        }

        private func enclosingScrollView() -> NSScrollView? {
            var current = superview
            while let view = current {
                if let scrollView = view as? NSScrollView {
                    return scrollView
                }
                current = view.superview
            }
            return nil
        }
    }

    final class Coordinator: NSObject {
        var onViewportChange: (Bool) -> Void

        private weak var scrollView: NSScrollView?
        private var boundsObserver: NSObjectProtocol?

        init(onViewportChange: @escaping (Bool) -> Void) {
            self.onViewportChange = onViewportChange
        }

        deinit {
            detach()
        }

        func attach(to newScrollView: NSScrollView?) {
            guard scrollView !== newScrollView else { return }
            detach()
            scrollView = newScrollView
            guard let newScrollView else { return }
            newScrollView.contentView.postsBoundsChangedNotifications = true
            boundsObserver = NotificationCenter.default.addObserver(
                forName: NSView.boundsDidChangeNotification,
                object: newScrollView.contentView,
                queue: .main
            ) { [weak self] _ in
                self?.emitViewportState()
            }
        }

        func detach() {
            if let boundsObserver {
                NotificationCenter.default.removeObserver(boundsObserver)
            }
            boundsObserver = nil
            scrollView = nil
        }

        private func emitViewportState() {
            guard let scrollView else { return }
            let documentHeight = scrollView.documentView?.bounds.maxY ?? 0
            let viewportMaxY = scrollView.contentView.bounds.maxY
            let distanceToBottom = max(0, documentHeight - viewportMaxY)
            let isNearBottom = distanceToBottom <= ChatAutoScrollFollowPolicy.bottomFollowDistanceThreshold
            onViewportChange(isNearBottom)
        }
    }
}
