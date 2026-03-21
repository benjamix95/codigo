import AppKit
import CoderEngine
import SwiftUI
import UniformTypeIdentifiers

extension ChatPanelView {
    internal func adjustWindowForPanelToggle(isOpening: Bool, width: CGFloat) {
        guard autoResizeSidePanels else { return }
        let delta = isOpening ? (width + 12) : -(width + 12)
        DispatchQueue.main.async {
            WindowResizeHelper.adjustWidth(by: delta, animate: false)
        }
    }
}
