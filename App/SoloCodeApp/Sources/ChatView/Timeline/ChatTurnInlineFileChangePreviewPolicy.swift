import Foundation

enum ChatTurnInlineFileChangePreviewMode: Equatable {
    case hidden
    case expandedOnly
}

enum ChatTurnInlineFileChangePreviewPolicy {
    static func mode(for change: ToolTraceFileChange) -> ChatTurnInlineFileChangePreviewMode {
        change.hasFullPreview ? .expandedOnly : .hidden
    }
}
