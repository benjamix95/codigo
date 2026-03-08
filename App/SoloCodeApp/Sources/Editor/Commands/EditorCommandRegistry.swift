import Foundation

struct EditorCommandDescriptor: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let shortcut: String?
}

enum EditorCommandRegistry {
    static let all: [EditorCommandDescriptor] = [
        .init(id: "quickOpen", title: "Quick Open", shortcut: "Cmd+P"),
        .init(id: "toggleSplit", title: "Toggle Split Editor", shortcut: "Cmd+\\"),
        .init(id: "findInFile", title: "Find in File", shortcut: "Cmd+F"),
        .init(id: "replaceInFile", title: "Replace in File", shortcut: "Opt+Cmd+F"),
        .init(id: "gotoLine", title: "Go to Line", shortcut: "Ctrl+G"),
        .init(id: "showProblems", title: "Show Problems", shortcut: "Shift+Cmd+M"),
        .init(id: "showOutline", title: "Show Outline", shortcut: "Cmd+Shift+O"),
        .init(id: "formatDocument", title: "Format Document", shortcut: "Shift+Opt+F")
    ]
}
