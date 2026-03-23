import AppKit
import SwiftUI

extension SoloCodeApp {
    func configureWindow() {
        let candidates = NSApplication.shared.windows.filter { $0.canBecomeMain }
        for window in candidates {
            window.minSize = NSSize(width: 860, height: 500)
            AppDelegate.applyMainWindowStyle(window)
        }
    }
}
