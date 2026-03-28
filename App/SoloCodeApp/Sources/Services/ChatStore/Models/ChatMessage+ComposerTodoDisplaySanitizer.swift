import Foundation

extension ChatMessage {
    /// Copia display-only: rimuove checklist / sezioni todo-piano duplicate quando il composer mostra già l’overlay.
    func redactingComposerDuplicateTodoMarkdown() -> ChatMessage {
        func strip(_ s: String) -> String {
            ChatTodoTimelineDisplaySanitizer.stripDuplicateTodoPresentation(
                from: s,
                numberedListRunMinimum: 2,
                stripAllOrderedListItemLines: true
            )
        }
        var m = self
        m.content = strip(m.content)
        if let ps = m.primaryTextSnapshot {
            m.primaryTextSnapshot = strip(ps)
        }
        if var blks = m.blocks {
            for idx in blks.indices {
                switch blks[idx].kind {
                case .primaryText, .plan, .status, .toolTrace, .reasoning:
                    if !blks[idx].text.isEmpty {
                        var b = blks[idx]
                        b.text = strip(b.text)
                        blks[idx] = b
                    }
                case .mermaid, .commands, .files, .toolMarker:
                    break
                }
            }
            m.blocks = blks
        }
        return m
    }
}
