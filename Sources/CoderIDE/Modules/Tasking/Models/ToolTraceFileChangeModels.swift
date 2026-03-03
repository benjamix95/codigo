import Foundation

enum ToolTraceFileChangeKind: String, CaseIterable {
    case created
    case edited
    case deleted
    case unknown

    var displayTitle: String {
        switch self {
        case .created: return "Created"
        case .edited: return "Edited"
        case .deleted: return "Deleted"
        case .unknown: return "Edited"
        }
    }
}

enum ToolTraceFileChangeDiffSource: String, CaseIterable {
    case payload
    case gitFallback
    case unknown

    var isDerived: Bool {
        switch self {
        case .payload:
            return false
        case .gitFallback, .unknown:
            return true
        }
    }
}

struct ToolTraceFileChange: Identifiable, Hashable {
    let eventId: UUID
    let path: String?
    let basename: String
    let kind: ToolTraceFileChangeKind
    let added: Int
    let removed: Int
    let diffPreview: String?
    let rawOutput: String?
    let diffSource: ToolTraceFileChangeDiffSource
    let sequence: Int
    let timestamp: Date
    let isRunning: Bool

    var id: UUID { eventId }
}
