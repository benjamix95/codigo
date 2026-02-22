import SwiftUI

/// Segmento della timeline per il turno assistant corrente (stile Cursor).
enum TimelineSegment: Identifiable {
    case assistantText(String, id: UUID = UUID())
    case step(TaskActivity)
    case todoSnapshot(id: UUID = UUID())

    var id: UUID {
        switch self {
        case .assistantText(_, let id): return id
        case .step(let a): return a.id
        case .todoSnapshot(let id): return id
        }
    }
}

/// Store per la timeline intercalata del turno assistant (testo, step operativi, todo).
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

    /// Aggiunge un'attività operativa alla timeline lineare.
    func appendActivity(_ activity: TaskActivity) {
        segments.append(.step(activity))
    }

    /// Aggiunge una card todo alla timeline.
    /// Quando `placeAtTop` è true, la card viene ancorata in alto.
    func appendTodoSnapshot(placeAtTop: Bool = false) {
        if let idx = segments.firstIndex(where: { if case .todoSnapshot = $0 { return true }; return false }) {
            if placeAtTop, idx != 0 {
                let segment = segments.remove(at: idx)
                segments.insert(segment, at: 0)
            }
            return
        }
        if placeAtTop {
            segments.insert(.todoSnapshot(), at: 0)
        } else {
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
