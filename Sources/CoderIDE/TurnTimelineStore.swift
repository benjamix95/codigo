import SwiftUI

/// Segmento della timeline per il turno assistant corrente (stile Cursor).
enum TimelineSegment: Identifiable {
    case assistantText(String, id: UUID = UUID())
    case thinking(TaskActivity)
    case tool(TaskActivity)
    case todoSnapshot(id: UUID = UUID())

    var id: UUID {
        switch self {
        case .assistantText(_, let id): return id
        case .thinking(let a): return a.id
        case .tool(let a): return a.id
        case .todoSnapshot(let id): return id
        }
    }
}

/// Store per la timeline intercalata del turno assistant (testo, thinking, tool, todo).
@MainActor
final class TurnTimelineStore: ObservableObject {
    @Published private(set) var segments: [TimelineSegment] = []

    private var lastCommittedTextLength: Int = 0
    private var lastKnownFullText: String = ""

    /// Aggiorna il testo accumulato dall'ultimo onText.
    func updateLastKnownText(_ full: String) {
        lastKnownFullText = full
        objectWillChange.send()
    }

    /// Committa il testo dall'ultimo commit fino a full.count e aggiunge un segmento.
    /// Chiamato prima di appendActivity/appendTodoSnapshot quando arriva un raw event.
    func commitText(from full: String) {
        lastKnownFullText = full
        let newLength = full.count
        if newLength < lastCommittedTextLength {
            // Streaming sanitization (es. rimozione marker) può accorciare il testo:
            // riallinea il cursore per evitare pending negativi o chunk persi.
            lastCommittedTextLength = newLength
            return
        }
        guard newLength > lastCommittedTextLength else { return }
        let chunk = String(full.suffix(newLength - lastCommittedTextLength))
        if !chunk.isEmpty {
            segments.append(.assistantText(chunk))
        }
        lastCommittedTextLength = newLength
    }

    /// Aggiunge un'attività thinking o tool alla timeline.
    func appendActivity(_ activity: TaskActivity) {
        switch activity.phase {
        case .thinking:
            segments.append(.thinking(activity))
        case .executing, .editing, .searching, .planning:
            segments.append(.tool(activity))
        }
    }

    /// Aggiunge una card todo alla timeline (una sola, aggiornata in place).
    func appendTodoSnapshot() {
        if !segments.contains(where: { if case .todoSnapshot = $0 { return true }; return false }) {
            segments.append(.todoSnapshot())
        }
    }

    /// Testo in streaming non ancora committato (mostrato come ultimo chunk).
    var pendingStreamingChunk: String? {
        let len = lastKnownFullText.count - lastCommittedTextLength
        guard len > 0 else { return nil }
        let s = String(lastKnownFullText.suffix(len))
        return s.isEmpty ? nil : s
    }

    /// Finalizza il turno: committa eventuale testo residuo.
    func finalize(lastFullText: String) {
        commitText(from: lastFullText)
    }

    /// Pulisce la timeline (nuovo turno).
    func clear() {
        segments.removeAll()
        lastCommittedTextLength = 0
        lastKnownFullText = ""
    }
}
