import Foundation

struct EditorMonacoCommandRequest: Equatable, Sendable {
    let id: UUID
    let commandId: String
    let pane: EditorPaneID

    init(commandId: String, pane: EditorPaneID) {
        self.id = UUID()
        self.commandId = commandId
        self.pane = pane
    }
}

@MainActor
final class EditorCommandDispatchStore: ObservableObject {
    @Published private(set) var request: EditorMonacoCommandRequest?

    func dispatch(_ commandId: String, pane: EditorPaneID) {
        request = EditorMonacoCommandRequest(commandId: commandId, pane: pane)
    }
}
