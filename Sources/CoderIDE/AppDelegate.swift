import AppKit

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
                guard let window = notification.object as? NSWindow else { return }
                Self.applyMainWindowStyle(window)
            }
        }
    }

    static func applyMainWindowStyle(_ window: NSWindow) {
        guard window.canBecomeMain else { return }
        window.title = ""
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.styleMask.insert(.fullSizeContentView)
        window.isMovableByWindowBackground = false
        window.toolbar?.showsBaselineSeparator = false
    }
}
