import Foundation

struct EditorNavigationRequest: Equatable, Sendable {
    let id: UUID
    let pane: EditorPaneID
    let path: String
    let line: Int

    init(pane: EditorPaneID, path: String, line: Int) {
        self.id = UUID()
        self.pane = pane
        self.path = path
        self.line = line
    }
}

@MainActor
final class EditorNavigationDispatchStore: ObservableObject {
    @Published private(set) var request: EditorNavigationRequest?

    func dispatch(path: String, line: Int, pane: EditorPaneID) {
        request = EditorNavigationRequest(pane: pane, path: path, line: line)
    }
}
