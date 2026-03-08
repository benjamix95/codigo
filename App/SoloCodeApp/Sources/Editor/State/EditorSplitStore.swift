import Foundation

@MainActor
final class EditorSplitStore: ObservableObject {
    @Published private(set) var secondaryFilePath: String?
    @Published private(set) var activePane: EditorPaneID = .primary

    var isSplitVisible: Bool { secondaryFilePath != nil }

    func filePath(primaryPath: String?) -> String? {
        switch activePane {
        case .primary:
            return primaryPath
        case .secondary:
            return secondaryFilePath ?? primaryPath
        }
    }

    func filePath(for pane: EditorPaneID, primaryPath: String?) -> String? {
        switch pane {
        case .primary:
            return primaryPath
        case .secondary:
            return secondaryFilePath
        }
    }

    func toggleSplit(using primaryPath: String?) {
        if secondaryFilePath != nil {
            secondaryFilePath = nil
            activePane = .primary
            return
        }
        secondaryFilePath = primaryPath
        activePane = .secondary
    }

    func setActivePane(_ pane: EditorPaneID) {
        if pane == .secondary, secondaryFilePath == nil {
            activePane = .primary
            return
        }
        activePane = pane
    }

    func open(path: String?, in pane: EditorPaneID, primaryPath: String?) {
        guard let path, !path.isEmpty else { return }
        switch pane {
        case .primary:
            activePane = .primary
        case .secondary:
            if secondaryFilePath == nil {
                secondaryFilePath = primaryPath
            }
            secondaryFilePath = path
            activePane = .secondary
        }
    }

    func handleClosedFile(_ path: String) {
        guard secondaryFilePath == path else { return }
        secondaryFilePath = nil
        if activePane == .secondary {
            activePane = .primary
        }
    }
}
