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
        controllers.removeValue(forKey: ObjectIdentifier(window))
    }

    private weak var window: NSWindow?
    private let button = NSButton()
    private var observers: [NSObjectProtocol] = []
    private var chromeState = WorkbenchSidebarChromeState(isAvailable: false, isVisible: false)

    private init(window: NSWindow) {
        self.window = window
        configureButton()
        installObservers(for: window)
        attachButtonIfNeeded()
        updateAppearance()
        updateLayout()
    }

    deinit {
        observers.forEach { NotificationCenter.default.removeObserver($0) }
    }

    @objc
    private func handleButtonTap() {
        NotificationCenter.default.post(name: .workbenchSidebarToggleRequested, object: nil)
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
            systemSymbolName: "sidebar.left",
            accessibilityDescription: "Toggle Sidebar"
        )?.withSymbolConfiguration(.init(pointSize: 15, weight: .medium))
    }

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
                forName: .workbenchSidebarChromeStateDidChange,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                guard let self else { return }
                guard let state = WorkbenchSidebarChromeState(userInfo: notification.userInfo) else { return }
                self.chromeState = state
                self.updateAppearance()
                self.updateLayout()
            }
        )

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
    }

    private func updateAppearance() {
        button.isHidden = !chromeState.isAvailable
        button.alphaValue = chromeState.isVisible ? 1.0 : 0.92
        button.contentTintColor = NSColor.white.withAlphaComponent(chromeState.isVisible ? 0.9 : 0.82)
        button.toolTip = chromeState.isVisible ? "Hide Sidebar" : "Show Sidebar"
    }

    private func updateLayout() {
        guard
            let window,
            let zoomButton = window.standardWindowButton(.zoomButton)
        else {
            return
        }

        let buttonSize = NSSize(width: 20, height: 18)
        let x = zoomButton.frame.maxX + 12
        let y = round(zoomButton.frame.midY - (buttonSize.height / 2))
        button.frame = NSRect(origin: NSPoint(x: x, y: y), size: buttonSize)
    }
}
