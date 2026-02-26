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
            if let url = Bundle.module.url(forResource: "AppLogo", withExtension: "png"),
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
        let bundledExecutableURL = macOSURL.appendingPathComponent("Codigo")
        let bundledInfoURL = contentsURL.appendingPathComponent("Info.plist")

        try fileManager.createDirectory(at: macOSURL, withIntermediateDirectories: true)
        if fileManager.fileExists(atPath: bundledExecutableURL.path) {
            try fileManager.removeItem(at: bundledExecutableURL)
        }
        try fileManager.copyItem(at: executableURL, to: bundledExecutableURL)

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

        let entitlementsURL = workingDirectoryURL.appendingPathComponent(
            "Package/Codigo.app/Contents/Entitlements.plist"
        )
        let codesignArgs: [String] = {
            if fileManager.fileExists(atPath: entitlementsURL.path) {
                return ["--force", "--deep", "-s", "-", "--entitlements", entitlementsURL.path, appURL.path]
            }
            return ["--force", "--deep", "-s", "-", appURL.path]
        }()
        _ = runProcess(executablePath: "/usr/bin/codesign", arguments: codesignArgs)
    }

    private func runProcess(executablePath: String, arguments: [String]) -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus
        } catch {
            return -1
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
