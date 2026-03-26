import AppKit
import CoderEngine
import Darwin
import Foundation

extension Notification.Name {
    static let soloCodeWillTerminateSaveDrafts = Notification.Name(
        "com.solocode.saveDraftsBeforeTermination"
    )
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var observers: [NSObjectProtocol] = []
    private static let savedStateFolderNames = [
        "com.solocode.app.savedState",
        "Solo Code.savedState",
    ]

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Ignore SIGHUP/SIGPIPE: the app orchestrates subprocesses over stdio
        // pipes (CLI providers, MCP servers, LLDB). If a child exits while we
        // still hold an in-flight read/write on those pipes, Darwin can deliver
        // a signal to the parent process instead of surfacing a recoverable
        // EPIPE/HUP error in Swift code.
        signal(SIGHUP, SIG_IGN)
        signal(SIGPIPE, SIG_IGN)

        NSApplication.shared.setActivationPolicy(.regular)
        disableWindowRestorationLoop()
        logRustRuntimeStatus()
        MCPSharedState.ensureDirectory()

        DispatchQueue.global(qos: .utility).async {
            _ = RipgrepInstaller.ensureInstalled()
        }

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
        NotificationCenter.default.post(
            name: .soloCodeWillTerminateSaveDrafts,
            object: nil
        )
        observers.forEach { NotificationCenter.default.removeObserver($0) }
        observers.removeAll()
    }

    func applicationShouldSaveApplicationState(_ app: NSApplication) -> Bool {
        false
    }

    func applicationShouldRestoreApplicationState(_ app: NSApplication) -> Bool {
        false
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        true
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

    private func logRustRuntimeStatus() {
        let state = ReviewCoreBridge.loadedState()
        if state.loaded, let version = state.version {
            NSLog("[SoloCode] Rust runtime: OK — %@ (%@)", version, state.libraryPath ?? "unknown path")
        } else {
            NSLog("[SoloCode] ⚠️ Rust runtime: NOT LOADED — reason: %@. Chat will degrade. Do Clean Build (Cmd+Shift+K) then Run.", state.failureReason ?? "unknown")
            NSLog("[SoloCode] Bundle.main: %@", Bundle.main.bundleURL.path)
            if let exec = Bundle.main.executableURL {
                NSLog("[SoloCode] Executable dir: %@", exec.deletingLastPathComponent().path)
            }
            NSLog("[SoloCode] CWD: %@", FileManager.default.currentDirectoryPath)
        }
    }

    private func disableWindowRestorationLoop() {
        UserDefaults.standard.set(false, forKey: "NSQuitAlwaysKeepsWindows")
        let savedStateRoot = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Saved Application State", isDirectory: true)
        for folderName in Self.savedStateFolderNames {
            let folderURL = savedStateRoot.appendingPathComponent(folderName, isDirectory: true)
            try? FileManager.default.removeItem(at: folderURL)
        }
    }
}
