import AppKit
import Foundation

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var observers: [NSObjectProtocol] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.regular)

        installWindowStyleObservers()

        DispatchQueue.main.async {
            NSApplication.shared.activate(ignoringOtherApps: true)
            for window in NSApplication.shared.windows where window.canBecomeMain {
                Self.applyMainWindowStyle(window)
                window.makeKeyAndOrderFront(nil)
                break
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        observers.forEach { NotificationCenter.default.removeObserver($0) }
        observers.removeAll()
    }

    private func installWindowStyleObservers() {
        let center = NotificationCenter.default
        let names: [Notification.Name] = [
            NSWindow.didBecomeMainNotification,
            NSWindow.didBecomeKeyNotification
        ]
        observers = names.map { name in
            center.addObserver(forName: name, object: nil, queue: .main) { notification in
                MainActor.assumeIsolated {
                    guard let window = notification.object as? NSWindow else { return }
                    Self.applyMainWindowStyle(window)
                }
            }
        }
    }

    @MainActor static func applyMainWindowStyle(_ window: NSWindow) {
        if window.title != "" {
            window.title = ""
        }
        if window.titleVisibility != .hidden {
            window.titleVisibility = .hidden
        }
        if !window.titlebarAppearsTransparent {
            window.titlebarAppearsTransparent = true
        }
        if !window.styleMask.contains(.fullSizeContentView) {
            window.styleMask.insert(.fullSizeContentView)
        }
        if window.isOpaque {
            window.isOpaque = false
        }
        if !window.backgroundColor.isEqual(DesignSystem.AppKit.sidebarBackground) {
            window.backgroundColor = DesignSystem.AppKit.sidebarBackground
        }
        if window.isMovableByWindowBackground {
            window.isMovableByWindowBackground = false
        }
        if #available(macOS 11.0, *) {
            if window.toolbarStyle != .unifiedCompact {
                window.toolbarStyle = .unifiedCompact
            }
            if window.titlebarSeparatorStyle != .none {
                window.titlebarSeparatorStyle = .none
            }
        }
        if window.toolbar?.showsBaselineSeparator == true {
            window.toolbar?.showsBaselineSeparator = false
        }
        hideStandardWindowButtons(for: window)
        WindowSidebarToggleController.installIfNeeded(on: window)
    }

    @MainActor
    private static func hideStandardWindowButtons(for window: NSWindow) {
        let buttonTypes: [NSWindow.ButtonType] = [.closeButton, .miniaturizeButton, .zoomButton]
        for buttonType in buttonTypes {
            guard let button = window.standardWindowButton(buttonType) else { continue }
            button.isHidden = true
            button.alphaValue = 0
            button.isEnabled = false
        }
    }
}
