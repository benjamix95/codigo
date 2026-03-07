import AppKit

final class WindowSidebarToggleController {
    private static var controllers: [ObjectIdentifier: WindowSidebarToggleController] = [:]
    private static let stripBurstPassCount = 4

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
    private var stripPassesRemaining = 0
    private var consecutiveUnchangedStripPasses = 0
    private init(window: NSWindow) {
        self.window = window
        configureButton()
        installObservers(for: window)
        attachButtonIfNeeded()
        updateLayout()
        scheduleStripBurst()
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

    private func scheduleStripBurst() {
        stripPassesRemaining = max(stripPassesRemaining, Self.stripBurstPassCount)
        guard periodicStripTimer == nil else { return }

        let timer = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
            self?.runScheduledStripPass()
        }
        timer.tolerance = 0.1
        periodicStripTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func runScheduledStripPass() {
        guard let window else {
            stopPeriodicStrip()
            return
        }

        let didChange = performStripPass(on: window)
        stripPassesRemaining -= 1
        consecutiveUnchangedStripPasses = didChange ? 0 : consecutiveUnchangedStripPasses + 1

        if stripPassesRemaining <= 0 || consecutiveUnchangedStripPasses >= 2 {
            stopPeriodicStrip()
        }
    }

    private func stopPeriodicStrip() {
        periodicStripTimer?.invalidate()
        periodicStripTimer = nil
        stripPassesRemaining = 0
        consecutiveUnchangedStripPasses = 0
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
                self?.scheduleStripBurst()
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
        _ = performStripPass(on: window)
        scheduleStripBurst()
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

    @discardableResult
    private func performStripPass(on window: NSWindow) -> Bool {
        let strippedToolbarItems = stripAutomaticSidebarToolbarItems(from: window)
        let hidSidebarButtons = hideTitlebarSidebarButtons(from: window)
        return strippedToolbarItems || hidSidebarButtons
    }

    @discardableResult
    private func stripAutomaticSidebarToolbarItems(from window: NSWindow) -> Bool {
        guard let toolbar = window.toolbar else { return false }

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
        return !indices.isEmpty
    }

    /// Walk the titlebar view hierarchy and hide any native sidebar toggle
    /// buttons that SwiftUI or AppKit inserts outside the toolbar.
    @discardableResult
    private func hideTitlebarSidebarButtons(from window: NSWindow) -> Bool {
        let toggleAction = NSSelectorFromString("toggleSidebar:")
        guard let titlebarView = window.standardWindowButton(.zoomButton)?.superview else {
            return false
        }
        return hideSidebarButtons(in: titlebarView, action: toggleAction, depth: 6)
    }

    @discardableResult
    private func hideSidebarButtons(in view: NSView, action: Selector, depth: Int) -> Bool {
        guard depth > 0 else { return false }
        var didChange = false
        for subview in view.subviews where subview !== button {
            if let btn = subview as? NSButton, isSidebarToggleButton(btn, action: action) {
                if !subview.isHidden {
                    subview.isHidden = true
                    didChange = true
                }
                if subview.alphaValue != 0 {
                    subview.alphaValue = 0
                    didChange = true
                }
                if subview.frame.size != .zero {
                    subview.setFrameSize(.zero)
                    didChange = true
                }
                continue
            }
            if hideSidebarButtons(in: subview, action: action, depth: depth - 1) {
                didChange = true
            }
        }
        return didChange
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
