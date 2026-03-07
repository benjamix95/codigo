import AppKit

final class WindowSidebarToggleController {
    private static var controllers: [ObjectIdentifier: WindowSidebarToggleController] = [:]

    static func installIfNeeded(on window: NSWindow) {
        let key = ObjectIdentifier(window)
        if let controller = controllers[key] {
            controller.attachButtonIfNeeded()
            controller.updateLayout()
            return
        }

        controllers[key] = WindowSidebarToggleController(window: window)
    }

    static func remove(for window: NSWindow) {
        let key = ObjectIdentifier(window)
        controllers[key]?.stopPeriodicStrip()
        controllers.removeValue(forKey: key)
    }

    private weak var window: NSWindow?
    private let button = NSButton()
    private var observers: [NSObjectProtocol] = []
    private var periodicStripTimer: Timer?

    private init(window: NSWindow) {
        self.window = window
        configureButton()
        installObservers(for: window)
        attachButtonIfNeeded()
        updateLayout()
        startPeriodicStrip()
    }

    deinit {
        stopPeriodicStrip()
        observers.forEach { NotificationCenter.default.removeObserver($0) }
    }

    @objc
    private func handleButtonTap() {
        NotificationCenter.default.post(name: .windowSidebarChromeToggleRequested, object: nil)
    }

    private func configureButton() {
        button.setButtonType(.momentaryChange)
        button.isBordered = false
        button.bezelStyle = .shadowlessSquare
        button.focusRingType = .none
        button.title = ""
        button.imagePosition = .imageOnly
        button.imageScaling = .scaleProportionallyDown
        button.target = self
        button.action = #selector(handleButtonTap)
        button.toolTip = "Toggle Sidebar"
        button.image = NSImage(
            systemSymbolName: "sidebar.leading",
            accessibilityDescription: "Toggle Sidebar"
        )?.withSymbolConfiguration(.init(pointSize: 15, weight: .medium))
        button.contentTintColor = NSColor.white.withAlphaComponent(0.88)
    }

    // MARK: - Periodic strip

    private func startPeriodicStrip() {
        guard periodicStripTimer == nil else { return }
        periodicStripTimer = Timer.scheduledTimer(
            withTimeInterval: 0.3,
            repeats: true
        ) { [weak self] _ in
            guard let self, let window = self.window else {
                self?.stopPeriodicStrip()
                return
            }
            self.stripAutomaticSidebarToolbarItems(from: window)
            self.hideTitlebarSidebarButtons(from: window)
        }
    }

    private func stopPeriodicStrip() {
        periodicStripTimer?.invalidate()
        periodicStripTimer = nil
    }

    // MARK: - Observers

    private func installObservers(for window: NSWindow) {
        let center = NotificationCenter.default
        let windowNotifications: [Notification.Name] = [
            NSWindow.didResizeNotification,
            NSWindow.didEnterFullScreenNotification,
            NSWindow.didExitFullScreenNotification,
            NSWindow.didDeminiaturizeNotification,
            NSWindow.didMoveNotification,
        ]

        observers = windowNotifications.map { name in
            center.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                self?.attachButtonIfNeeded()
                self?.updateLayout()
            }
        }

        observers.append(
            center.addObserver(
                forName: NSWindow.willCloseNotification,
                object: window,
                queue: .main
            ) { notification in
                guard let window = notification.object as? NSWindow else { return }
                Self.remove(for: window)
            }
        )
    }

    // MARK: - Button attachment

    private func attachButtonIfNeeded() {
        guard
            let window,
            let zoomButton = window.standardWindowButton(.zoomButton),
            let titlebarView = zoomButton.superview
        else {
            return
        }

        if button.superview !== titlebarView {
            button.removeFromSuperview()
            titlebarView.addSubview(button)
        }
        stripAutomaticSidebarToolbarItems(from: window)
        hideTitlebarSidebarButtons(from: window)
    }

    private func updateLayout() {
        guard
            let window,
            let zoomButton = window.standardWindowButton(.zoomButton)
        else {
            return
        }

        let buttonSize = NSSize(width: 18, height: 18)
        let buttonX = zoomButton.frame.maxX + 12
        let buttonY = round(zoomButton.frame.midY - (buttonSize.height / 2))
        button.frame = NSRect(origin: NSPoint(x: buttonX, y: buttonY), size: buttonSize)
    }

    // MARK: - Strip native sidebar controls

    private func stripAutomaticSidebarToolbarItems(from window: NSWindow) {
        guard let toolbar = window.toolbar else { return }

        let indices = toolbar.items.enumerated().compactMap { index, item -> Int? in
            let raw = item.itemIdentifier.rawValue
            if item.itemIdentifier == .toggleSidebar { return index }
            if item.itemIdentifier == .sidebarTrackingSeparator { return index }
            if raw.contains("toggleSidebar") { return index }
            if raw.hasPrefix("com.apple.SwiftUI.splitViewSeparator-") { return index }
            return nil
        }

        for index in indices.reversed() {
            toolbar.removeItem(at: index)
        }
    }

    /// Walk the titlebar view hierarchy and hide any native sidebar toggle
    /// buttons that SwiftUI or AppKit inserts outside the toolbar.
    private func hideTitlebarSidebarButtons(from window: NSWindow) {
        let toggleAction = NSSelectorFromString("toggleSidebar:")
        guard let titlebarView = window.standardWindowButton(.zoomButton)?.superview else {
            return
        }
        hideSidebarButtons(in: titlebarView, action: toggleAction, depth: 6)
    }

    private func hideSidebarButtons(in view: NSView, action: Selector, depth: Int) {
        guard depth > 0 else { return }
        for subview in view.subviews where subview !== button {
            if let btn = subview as? NSButton, isSidebarToggleButton(btn, action: action) {
                subview.isHidden = true
                subview.alphaValue = 0
                subview.setFrameSize(.zero)
                continue
            }
            hideSidebarButtons(in: subview, action: action, depth: depth - 1)
        }
    }

    private func isSidebarToggleButton(_ btn: NSButton, action: Selector) -> Bool {
        if btn.action == action { return true }
        if let a = btn.action, NSStringFromSelector(a).contains("toggleSidebar") {
            return true
        }
        let cls = NSStringFromClass(type(of: btn)).lowercased()
        if cls.contains("sidebartoggle") || cls.contains("columntoggle") {
            return true
        }
        if let imgName = btn.image?.name()?.lowercased(),
           imgName.contains("sidebar") {
            return true
        }
        return false
    }
}
