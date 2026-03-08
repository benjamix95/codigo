import SwiftUI

extension View {
    @ViewBuilder
    func hideSidebarToggleIfSupported() -> some View {
        if #available(macOS 14.0, *) {
            toolbar(removing: .sidebarToggle)
        } else {
            self
        }
    }
}
