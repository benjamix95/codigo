import AppKit
import SwiftUI

extension CodigoApp {
    func configureWindow() {
        let candidates = NSApplication.shared.windows.filter { $0.canBecomeMain }
        for window in candidates {
            window.minSize = NSSize(width: 860, height: 500)
            window.backgroundColor = DesignSystem.AppKit.windowBackground
            AppDelegate.applyMainWindowStyle(window)
        }
    }
}
