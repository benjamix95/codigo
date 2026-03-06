import AppKit
import Foundation

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var observers: [NSObjectProtocol] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        if relaunchBundledAppIfNeeded() {
            return
        }

        NSApplication.shared.setActivationPolicy(.regular)

        // Set the app icon asynchronously to avoid blocking launch
        DispatchQueue.global(qos: .userInitiated).async {
            if let url = RuntimeResourceLocator.appLogoURL(),
               let icon = NSImage(contentsOf: url) {
                DispatchQueue.main.async {
                    NSApplication.shared.applicationIconImage = icon
                }
            }
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

    private func relaunchBundledAppIfNeeded() -> Bool {
        guard Bundle.main.bundleURL.pathExtension != "app" else {
            return false
        }

        let fileManager = FileManager.default
        let executableURL = URL(fileURLWithPath: CommandLine.arguments.first ?? "")
        let workingDirectoryURL = URL(fileURLWithPath: fileManager.currentDirectoryPath, isDirectory: true)
        let appURL = resolveBundledAppURL(executableURL: executableURL, workingDirectoryURL: workingDirectoryURL)

        do {
            try prepareBundledApp(at: appURL, executableURL: executableURL, workingDirectoryURL: workingDirectoryURL)
        } catch {
            return false
        }

        do {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            process.arguments = [appURL.path]
            try process.run()
            NSApplication.shared.terminate(nil)
            return true
        } catch {
            return false
        }
    }

    private func resolveBundledAppURL(executableURL: URL, workingDirectoryURL: URL) -> URL {
        let fileManager = FileManager.default
        let candidates: [URL] = [
            workingDirectoryURL.appendingPathComponent("Codigo.app"),
            executableURL.deletingLastPathComponent().appendingPathComponent("Codigo.app"),
            executableURL.deletingLastPathComponent().deletingLastPathComponent()
                .appendingPathComponent("Codigo.app"),
        ]

        if let existing = candidates.first(where: { fileManager.fileExists(atPath: $0.path) }) {
            return existing
        }
        return workingDirectoryURL.appendingPathComponent("Codigo.app")
    }

    private func prepareBundledApp(at appURL: URL, executableURL: URL, workingDirectoryURL: URL) throws {
        let fileManager = FileManager.default
        let contentsURL = appURL.appendingPathComponent("Contents", isDirectory: true)
        let macOSURL = contentsURL.appendingPathComponent("MacOS", isDirectory: true)
        let resourcesURL = contentsURL.appendingPathComponent("Resources", isDirectory: true)
        let bundledExecutableURL = macOSURL.appendingPathComponent("Codigo")
        let bundledInfoURL = contentsURL.appendingPathComponent("Info.plist")

        try fileManager.createDirectory(at: macOSURL, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: resourcesURL, withIntermediateDirectories: true)
        if fileManager.fileExists(atPath: bundledExecutableURL.path) {
            try fileManager.removeItem(at: bundledExecutableURL)
        }
        try fileManager.copyItem(at: executableURL, to: bundledExecutableURL)
        try copySiblingExecutableIfPresent(
            named: "coderide-mcp-server",
            from: executableURL.deletingLastPathComponent(),
            to: macOSURL
        )
        try copyResourceBundles(
            from: executableURL.deletingLastPathComponent(),
            to: resourcesURL
        )

        let plistCandidates = [
            workingDirectoryURL.appendingPathComponent("Package/Codigo.app/Contents/Info.plist"),
            workingDirectoryURL.appendingPathComponent("Sources/CoderIDE/Info.plist"),
        ]
        if let plistURL = plistCandidates.first(where: { fileManager.fileExists(atPath: $0.path) }) {
            if fileManager.fileExists(atPath: bundledInfoURL.path) {
                try fileManager.removeItem(at: bundledInfoURL)
            }
            try fileManager.copyItem(at: plistURL, to: bundledInfoURL)
        }

        // During local SwiftPM runs we avoid blocking the main thread on codesign.
        // Gatekeeper signing is handled by the packaging workflow.
    }

    private func copySiblingExecutableIfPresent(named name: String, from sourceDir: URL, to targetDir: URL) throws {
        let fileManager = FileManager.default
        let source = sourceDir.appendingPathComponent(name)
        let destination = targetDir.appendingPathComponent(name)
        guard fileManager.fileExists(atPath: source.path) else { return }
        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.removeItem(at: destination)
        }
        try fileManager.copyItem(at: source, to: destination)
    }

    private func copyResourceBundles(from sourceDir: URL, to resourcesDir: URL) throws {
        let fileManager = FileManager.default
        let entries = try fileManager.contentsOfDirectory(at: sourceDir, includingPropertiesForKeys: nil)
        for entry in entries where entry.pathExtension == "bundle" {
            let destination = resourcesDir.appendingPathComponent(entry.lastPathComponent)
            if fileManager.fileExists(atPath: destination.path) {
                try fileManager.removeItem(at: destination)
            }
            try fileManager.copyItem(at: entry, to: destination)
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
        WindowSidebarToggleController.installIfNeeded(on: window)
    }
}
