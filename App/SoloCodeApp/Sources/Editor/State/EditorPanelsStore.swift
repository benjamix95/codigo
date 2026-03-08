import Foundation

@MainActor
final class EditorPanelsStore: ObservableObject {
    @Published var isQuickOpenVisible = false
    @Published var activeBottomPanel: EditorBottomPanel?
    @Published var quickOpenTargetPane: EditorPaneID = .primary

    var isBottomPanelVisible: Bool { activeBottomPanel != nil }

    func showQuickOpen(targetPane: EditorPaneID) {
        quickOpenTargetPane = targetPane
        isQuickOpenVisible = true
    }

    func hideQuickOpen() {
        isQuickOpenVisible = false
    }

    func showBottomPanel(_ panel: EditorBottomPanel) {
        activeBottomPanel = panel
    }

    func hideBottomPanel() {
        activeBottomPanel = nil
    }

    func toggleBottomPanel(_ panel: EditorBottomPanel) {
        if activeBottomPanel == panel {
            activeBottomPanel = nil
        } else {
            activeBottomPanel = panel
        }
    }
}
