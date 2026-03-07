import AppKit
import SwiftUI

final class WindowSidebarToggleController {
    private static var controllers: [ObjectIdentifier: WindowSidebarToggleController] = [:]

    static func installIfNeeded(on window: NSWindow) {
        let key = ObjectIdentifier(window)
        if let controller = controllers[key] {
            controller.attachChromeIfNeeded()
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
    private let accessoryHost = NSHostingView(rootView: AnyView(EmptyView()))
    private var observers: [NSObjectProtocol] = []
    private var chatInfo: WindowTitlebarChatInfo?

    private init(window: NSWindow) {
        self.window = window
        configureButton()
        configureAccessoryHost()
        installObservers(for: window)
        attachChromeIfNeeded()
        updateAccessoryContent(maxWidth: 0)
        updateLayout()
    }

    deinit {
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
    }

    private func configureAccessoryHost() {
        accessoryHost.isHidden = true
        accessoryHost.setFrameSize(.zero)
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
                self?.attachChromeIfNeeded()
                self?.updateLayout()
            }
        }

        observers.append(
            center.addObserver(
                forName: .windowTitlebarChatInfoDidChange,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                guard let self else { return }
                self.chatInfo = WindowTitlebarChatInfo(userInfo: notification.userInfo)
                self.attachChromeIfNeeded()
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

    private func attachChromeIfNeeded() {
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
        if accessoryHost.superview !== titlebarView {
            accessoryHost.removeFromSuperview()
            titlebarView.addSubview(accessoryHost)
        }
        stripAutomaticSidebarToolbarItems(from: window)
        for delay in [0.0, 0.2, 0.6] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self, weak window] in
                guard let self, let window else { return }
                self.stripAutomaticSidebarToolbarItems(from: window)
            }
        }
    }

    private func updateLayout() {
        guard
            let window,
            let zoomButton = window.standardWindowButton(.zoomButton),
            let titlebarView = zoomButton.superview
        else {
            return
        }

        let buttonSize = NSSize(width: 18, height: 18)
        let buttonX = zoomButton.frame.maxX + 12
        let buttonY = round(zoomButton.frame.midY - (buttonSize.height / 2))
        button.frame = NSRect(origin: NSPoint(x: buttonX, y: buttonY), size: buttonSize)

        let accessoryLeadingX = button.frame.maxX + 10
        let accessoryWidth = max(
            0,
            min(titlebarView.bounds.width * 0.42, titlebarView.bounds.width - accessoryLeadingX - 20)
        )
        updateAccessoryContent(maxWidth: accessoryWidth)
        let accessoryHeight = max(20, accessoryHost.fittingSize.height)
        let accessoryY = round(zoomButton.frame.midY - (accessoryHeight / 2))
        accessoryHost.frame = NSRect(
            x: accessoryLeadingX,
            y: accessoryY,
            width: accessoryWidth,
            height: accessoryHeight
        )
        stripAutomaticSidebarToolbarItems(from: window)
    }

    private func updateAccessoryContent(maxWidth: CGFloat) {
        guard let chatInfo, maxWidth > 0 else {
            accessoryHost.rootView = AnyView(EmptyView())
            accessoryHost.isHidden = true
            return
        }

        accessoryHost.rootView = AnyView(
            WindowTitlebarChatAccessoryView(
                info: chatInfo,
                openProject: { [weak self] in
                    guard let path = self?.chatInfo?.projectPath else { return }
                    NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: path)
                }
            )
            .frame(width: maxWidth, alignment: .leading)
        )
        accessoryHost.isHidden = false
        accessoryHost.layoutSubtreeIfNeeded()
    }

    private func stripAutomaticSidebarToolbarItems(from window: NSWindow) {
        guard let toolbar = window.toolbar else { return }

        let removableIdentifiers: [NSToolbarItem.Identifier] = [
            .toggleSidebar,
            .sidebarTrackingSeparator,
            .init("com.apple.SwiftUI.navigationSplitView.toggleSidebar"),
            .init("com.apple.SwiftUI.splitViewSeparator-0"),
        ]

        let indices = toolbar.items.enumerated().compactMap { index, item -> Int? in
            let identifier = item.itemIdentifier
            let rawValue = identifier.rawValue
            if removableIdentifiers.contains(identifier) { return index }
            if rawValue.hasPrefix("com.apple.SwiftUI.splitViewSeparator-") { return index }
            if rawValue.contains("navigationSplitView.toggleSidebar") { return index }
            return nil
        }

        for index in indices.reversed() {
            toolbar.removeItem(at: index)
        }
    }
}
