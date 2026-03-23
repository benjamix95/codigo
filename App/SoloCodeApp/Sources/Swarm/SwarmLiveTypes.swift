import Foundation

enum SwarmCardStatus: String, Codable, Sendable {
    case running
    case completed
    case failed
    case idle
}

enum SubagentTranscriptEntryKind: String, Codable, Sendable {
    case assistantText
    case activity
}

struct SubagentTranscriptEntry: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let kind: SubagentTranscriptEntryKind
    let title: String
    let detail: String
    let timestamp: Date?
    let isRunning: Bool

    init(
        id: String = UUID().uuidString.lowercased(),
        kind: SubagentTranscriptEntryKind,
        title: String,
        detail: String,
        timestamp: Date? = nil,
        isRunning: Bool = false
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.detail = detail
        self.timestamp = timestamp
        self.isRunning = isRunning
    }

    static func assistantText(_ text: String, timestamp: Date?) -> SubagentTranscriptEntry? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return SubagentTranscriptEntry(
            kind: .assistantText,
            title: "Update",
            detail: trimmed,
            timestamp: timestamp,
            isRunning: true
        )
    }

    static func activity(_ activity: TaskActivity) -> SubagentTranscriptEntry? {
        let title = activity.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let detail = (activity.detail ?? activity.payload["detail"] ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty || !detail.isEmpty else { return nil }
        return SubagentTranscriptEntry(
            kind: .activity,
            title: title.isEmpty ? activity.type : title,
            detail: detail,
            timestamp: activity.timestamp,
            isRunning: activity.isRunning
        )
    }
}

struct SwarmLiveCardState: Identifiable, Sendable {
    let swarmId: String
    var displayName: String
    var status: SwarmCardStatus
    var startedAt: Date?
    var lastEventAt: Date?
    var completedAt: Date?
    var currentStepTitle: String
    var currentDetail: String
    var activeOpsCount: Int
    var errorCount: Int
    var warningCount: Int
    var recentEvents: [TaskActivity]
    var summary: String?
    var isCollapsed: Bool
    var hasUnreadSinceCollapse: Bool
    /// Accumulated LLM text output streamed in real-time (capped to prevent unbounded growth).
    var liveText: String
    var transcript: [SubagentTranscriptEntry]

    var id: String { swarmId }

    static let liveTextMaxLength = 12_000
    static let transcriptMaxEntries = 120

    init(
        swarmId: String,
        displayName: String = "",
        status: SwarmCardStatus = .idle,
        startedAt: Date? = nil,
        lastEventAt: Date? = nil,
        completedAt: Date? = nil,
        currentStepTitle: String = "Awaiting events",
        currentDetail: String = "",
        activeOpsCount: Int = 0,
        errorCount: Int = 0,
        warningCount: Int = 0,
        recentEvents: [TaskActivity] = [],
        summary: String? = nil,
        isCollapsed: Bool = false,
        hasUnreadSinceCollapse: Bool = false,
        liveText: String = "",
        transcript: [SubagentTranscriptEntry] = []
    ) {
        self.swarmId = swarmId
        self.displayName = displayName
        self.status = status
        self.startedAt = startedAt
        self.lastEventAt = lastEventAt
        self.completedAt = completedAt
        self.currentStepTitle = currentStepTitle
        self.currentDetail = currentDetail
        self.activeOpsCount = activeOpsCount
        self.errorCount = errorCount
        self.warningCount = warningCount
        self.recentEvents = recentEvents
        self.summary = summary
        self.isCollapsed = isCollapsed
        self.hasUnreadSinceCollapse = hasUnreadSinceCollapse
        self.liveText = liveText
        self.transcript = transcript
    }
}
