import AppKit
import ApplicationServices
import CoderEngine
import CoreGraphics
import Foundation

struct MacOSAutomationWindowInfo: Equatable {
    let windowID: CGWindowID
    let bounds: CGRect
}

enum MacOSAutomationEventMapping {
    static func modifierFlags(from modifiers: [String]) -> CGEventFlags {
        modifiers.reduce(into: CGEventFlags()) { partialResult, raw in
            switch raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
            case "command", "cmd":
                partialResult.insert(.maskCommand)
            case "shift":
                partialResult.insert(.maskShift)
            case "option", "alt":
                partialResult.insert(.maskAlternate)
            case "control", "ctrl":
                partialResult.insert(.maskControl)
            case "function", "fn":
                partialResult.insert(.maskSecondaryFn)
            default:
                break
            }
        }
    }

    static func keyCode(for key: String) -> CGKeyCode? {
        switch key.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "a": 0
        case "s": 1
        case "d": 2
        case "f": 3
        case "h": 4
        case "g": 5
        case "z": 6
        case "x": 7
        case "c": 8
        case "v": 9
        case "b": 11
        case "q": 12
        case "w": 13
        case "e": 14
        case "r": 15
        case "y": 16
        case "t": 17
        case "1": 18
        case "2": 19
        case "3": 20
        case "4": 21
        case "6": 22
        case "5": 23
        case "=": 24
        case "9": 25
        case "7": 26
        case "-": 27
        case "8": 28
        case "0": 29
        case "]": 30
        case "o": 31
        case "u": 32
        case "[": 33
        case "i": 34
        case "p": 35
        case "return", "enter": 36
        case "l": 37
        case "j": 38
        case "'": 39
        case "k": 40
        case ";": 41
        case "\\": 42
        case ",": 43
        case "/": 44
        case "n": 45
        case "m": 46
        case ".": 47
        case "tab": 48
        case "space": 49
        case "`": 50
        case "delete", "backspace": 51
        case "escape", "esc": 53
        case "left": 123
        case "right": 124
        case "down": 125
        case "up": 126
        default:
            nil
        }
    }
}

@MainActor
final class MacOSAutomationService {
    static let shared = MacOSAutomationService()

    let hostAppName: String
    let hostBundleID: String?
    let hostPID: pid_t

    init(
        hostAppName: String = Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String ?? "Solo Code",
        hostBundleID: String? = Bundle.main.bundleIdentifier,
        hostPID: pid_t = ProcessInfo.processInfo.processIdentifier
    ) {
        self.hostAppName = hostAppName
        self.hostBundleID = hostBundleID
        self.hostPID = hostPID
    }

    func isAccessibilityTrusted() -> Bool {
        AXIsProcessTrusted()
    }

    func resolveAppName(appName: String?, bundleID: String?) -> String {
        if let appName, !appName.isEmpty {
            return appName
        }
        if bundleID != nil {
            return resolveRunningApplication(appName: nil, bundleID: bundleID)?.localizedName ?? ""
        }
        if let app = resolveRunningApplication(appName: nil, bundleID: bundleID) {
            return app.localizedName ?? hostAppName
        }
        return hostAppName
    }

    func resolveRunningApplication(appName: String?, bundleID: String?) -> NSRunningApplication? {
        if let bundleID, !bundleID.isEmpty,
           let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first {
            return app
        }
        if let appName, !appName.isEmpty {
            let lowered = appName.lowercased()
            if let running = NSWorkspace.shared.runningApplications.first(where: {
                ($0.localizedName ?? "").lowercased() == lowered
            }) {
                return running
            }
        }
        if bundleID == nil && appName == nil {
            return NSRunningApplication(processIdentifier: hostPID)
        }
        return nil
    }

    func resolveApplicationURL(appName: String?, bundleID: String?) -> URL? {
        if let bundleID, !bundleID.isEmpty {
            return NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
        }
        if let appName, !appName.isEmpty,
           let fullPath = NSWorkspace.shared.fullPath(forApplication: appName) {
            return URL(fileURLWithPath: fullPath)
        }
        return nil
    }

    func openApplication(at url: URL) async -> Bool {
        await withCheckedContinuation { continuation in
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = true
            NSWorkspace.shared.openApplication(at: url, configuration: configuration) { _, error in
                continuation.resume(returning: error == nil)
            }
        }
    }

    func resolveTargetPID(appName: String?, bundleID: String?) -> pid_t? {
        resolveRunningApplication(appName: appName, bundleID: bundleID)?.processIdentifier
    }

    func visibleWindows(forPID pid: pid_t) -> [MacOSAutomationWindowInfo] {
        guard let windowList = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] else {
            return []
        }

        return windowList.compactMap { entry in
            guard let ownerPID = entry[kCGWindowOwnerPID as String] as? NSNumber,
                  ownerPID.intValue == Int(pid),
                  let layer = entry[kCGWindowLayer as String] as? NSNumber,
                  layer.intValue == 0,
                  let alpha = entry[kCGWindowAlpha as String] as? NSNumber,
                  alpha.doubleValue > 0,
                  let windowID = entry[kCGWindowNumber as String] as? NSNumber,
                  let boundsDict = entry[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: boundsDict),
                  bounds.width > 1,
                  bounds.height > 1 else {
                return nil
            }
            return MacOSAutomationWindowInfo(
                windowID: CGWindowID(windowID.uint32Value),
                bounds: bounds
            )
        }
    }

    func pngData(from cgImage: CGImage) -> Data? {
        let image = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff) else {
            return nil
        }
        return rep.representation(using: .png, properties: [:])
    }

    func unionRect(for windows: [MacOSAutomationWindowInfo]) -> CGRect? {
        windows.reduce(nil) { partialResult, info in
            guard let partialResult else { return info.bounds }
            return partialResult.union(info.bounds)
        }
    }

    func appleScriptSource(script: String, appName: String?, timeoutMs: Int?) -> String {
        let body: String
        if let appName, !appName.isEmpty,
           !script.lowercased().contains("tell application") {
            body = """
            tell application "\(appName)"
            \(script)
            end tell
            """
        } else {
            body = script
        }

        guard let timeoutMs, timeoutMs > 0 else { return body }
        let seconds = max(1, Int(ceil(Double(timeoutMs) / 1000.0)))
        return """
        with timeout of \(seconds) seconds
        \(body)
        end timeout
        """
    }

    func axElementValues(for element: AXUIElement) -> MacOSUIElementSnapshot {
        let role = copyAXString(attribute: kAXRoleAttribute as CFString, from: element) ?? ""
        let name = copyAXString(attribute: kAXTitleAttribute as CFString, from: element)
            ?? copyAXString(attribute: kAXDescriptionAttribute as CFString, from: element)
            ?? copyAXString(attribute: kAXValueAttribute as CFString, from: element)
            ?? ""
        let help = copyAXString(attribute: kAXHelpAttribute as CFString, from: element) ?? ""
        let position = copyAXPoint(attribute: kAXPositionAttribute as CFString, from: element) ?? .zero
        let size = copyAXSize(attribute: kAXSizeAttribute as CFString, from: element) ?? .zero
        return MacOSUIElementSnapshot(
            role: role,
            name: name,
            help: help,
            x: position.x,
            y: position.y,
            width: size.width,
            height: size.height
        )
    }

    func copyAXString(attribute: CFString, from element: AXUIElement) -> String? {
        var value: CFTypeRef?
        let status = AXUIElementCopyAttributeValue(element, attribute, &value)
        guard status == .success else { return nil }
        if let string = value as? String {
            return string
        }
        if let attributed = value as? NSAttributedString {
            return attributed.string
        }
        if let number = value as? NSNumber {
            return number.stringValue
        }
        return nil
    }

    func copyAXPoint(attribute: CFString, from element: AXUIElement) -> CGPoint? {
        var value: CFTypeRef?
        let status = AXUIElementCopyAttributeValue(element, attribute, &value)
        guard status == .success,
              let axValue = value,
              CFGetTypeID(axValue) == AXValueGetTypeID() else {
            return nil
        }
        let typedValue = axValue as! AXValue
        guard AXValueGetType(typedValue) == .cgPoint else { return nil }
        var point = CGPoint.zero
        guard AXValueGetValue(typedValue, .cgPoint, &point) else { return nil }
        return point
    }

    func copyAXSize(attribute: CFString, from element: AXUIElement) -> CGSize? {
        var value: CFTypeRef?
        let status = AXUIElementCopyAttributeValue(element, attribute, &value)
        guard status == .success,
              let axValue = value,
              CFGetTypeID(axValue) == AXValueGetTypeID() else {
            return nil
        }
        let typedValue = axValue as! AXValue
        guard AXValueGetType(typedValue) == .cgSize else { return nil }
        var size = CGSize.zero
        guard AXValueGetValue(typedValue, .cgSize, &size) else { return nil }
        return size
    }
}

extension MacOSAutomationService: CoderEngine.MacOSAutomationBridge {
    func focusApp(appName: String?, bundleID: String?) async -> Bool {
        if let running = resolveRunningApplication(appName: appName, bundleID: bundleID) {
            return running.activate(options: [.activateAllWindows, .activateIgnoringOtherApps])
        }
        guard let url = resolveApplicationURL(appName: appName, bundleID: bundleID) else { return false }
        return await openApplication(at: url)
    }

    func captureScreenshot(target: String, appName: String?, bundleID: String?) async -> Data? {
        switch target {
        case "screen":
            guard let image = CGDisplayCreateImage(CGMainDisplayID()) else { return nil }
            return pngData(from: image)
        case "app":
            guard let pid = resolveTargetPID(appName: appName, bundleID: bundleID) else { return nil }
            let windows = visibleWindows(forPID: pid)
            guard let union = unionRect(for: windows),
                  let image = CGWindowListCreateImage(union, [.optionOnScreenOnly], kCGNullWindowID, [.bestResolution]) else {
                return nil
            }
            return pngData(from: image)
        default:
            guard let pid = resolveTargetPID(appName: appName, bundleID: bundleID) else { return nil }
            let windows = visibleWindows(forPID: pid)
            guard let window = windows.first else { return nil }
            if let image = CGWindowListCreateImage(
                .null,
                [.optionIncludingWindow],
                window.windowID,
                [.boundsIgnoreFraming, .bestResolution]
            ) {
                return pngData(from: image)
            }
            guard let fallback = CGWindowListCreateImage(
                window.bounds,
                [.optionOnScreenOnly],
                kCGNullWindowID,
                [.bestResolution]
            ) else {
                return nil
            }
            return pngData(from: fallback)
        }
    }

    func runAppleScript(_ script: String, appName: String?, bundleID: String?, timeoutMs: Int?) async -> Result<String, MacOSAutomationBridgeError> {
        let effectiveAppName = resolveAppName(appName: appName, bundleID: bundleID)
        let source = appleScriptSource(
            script: script,
            appName: effectiveAppName,
            timeoutMs: timeoutMs
        )
        guard let appleScript = NSAppleScript(source: source) else {
            return .failure(.executionFailed("Unable to compile AppleScript source"))
        }
        var errorInfo: NSDictionary?
        let descriptor = appleScript.executeAndReturnError(&errorInfo)
        if let errorInfo,
           let message = errorInfo[NSAppleScript.errorMessage] as? String {
            return .failure(.executionFailed(message))
        }
        return .success(descriptor.stringValue ?? "")
    }

    func click(x: Double, y: Double) async -> Bool {
        guard isAccessibilityTrusted() else { return false }
        let point = CGPoint(x: x, y: y)
        guard let move = CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: point, mouseButton: .left),
              let down = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: point, mouseButton: .left),
              let up = CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp, mouseCursorPosition: point, mouseButton: .left) else {
            return false
        }
        move.post(tap: .cghidEventTap)
        usleep(120_000)
        down.post(tap: .cghidEventTap)
        usleep(60_000)
        up.post(tap: .cghidEventTap)
        return true
    }

    func pressKey(key: String, modifiers: [String]) async -> Bool {
        guard isAccessibilityTrusted(),
              let keyCode = MacOSAutomationEventMapping.keyCode(for: key),
              let down = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: true),
              let up = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: false) else {
            return false
        }
        let flags = MacOSAutomationEventMapping.modifierFlags(from: modifiers)
        down.flags = flags
        up.flags = flags
        down.post(tap: .cghidEventTap)
        usleep(50_000)
        up.post(tap: .cghidEventTap)
        return true
    }

    func typeText(_ text: String) async -> Bool {
        guard isAccessibilityTrusted(),
              !text.isEmpty,
              let down = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: true),
              let up = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: false) else {
            return false
        }
        let utf16 = Array(text.utf16)
        down.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: utf16)
        up.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: utf16)
        down.post(tap: .cghidEventTap)
        usleep(40_000)
        up.post(tap: .cghidEventTap)
        return true
    }

    func listUIElements(appName: String?, bundleID: String?, scope: String, limit: Int) async -> [MacOSUIElementSnapshot] {
        guard isAccessibilityTrusted(),
              let pid = resolveTargetPID(appName: appName, bundleID: bundleID) else {
            return []
        }
        let application = AXUIElementCreateApplication(pid)
        let rootElements: [AXUIElement]
        if scope == "entire_app" {
            rootElements = [application]
        } else {
            var focusedWindow: CFTypeRef?
            let focusedStatus = AXUIElementCopyAttributeValue(application, kAXFocusedWindowAttribute as CFString, &focusedWindow)
            if focusedStatus == .success, let window = focusedWindow {
                rootElements = [window as! AXUIElement]
            } else {
                var windowsValue: CFTypeRef?
                let windowsStatus = AXUIElementCopyAttributeValue(application, kAXWindowsAttribute as CFString, &windowsValue)
                if windowsStatus == .success, let windows = windowsValue as? [AXUIElement], let first = windows.first {
                    rootElements = [first]
                } else {
                    return []
                }
            }
        }

        var queue = rootElements
        var snapshots: [MacOSUIElementSnapshot] = []
        var seen: Set<String> = []

        while !queue.isEmpty && snapshots.count < limit {
            let element = queue.removeFirst()
            let snapshot = axElementValues(for: element)
            let dedupeKey = [
                snapshot.role,
                snapshot.name,
                snapshot.help,
                "\(snapshot.x)",
                "\(snapshot.y)",
                "\(snapshot.width)",
                "\(snapshot.height)",
            ].joined(separator: "|")
            if seen.insert(dedupeKey).inserted {
                snapshots.append(snapshot)
            }

            var childrenValue: CFTypeRef?
            let childrenStatus = AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenValue)
            if childrenStatus == .success, let children = childrenValue as? [AXUIElement] {
                queue.append(contentsOf: children)
            }
        }

        return snapshots
    }
}
