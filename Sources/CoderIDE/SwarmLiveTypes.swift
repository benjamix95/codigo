import Foundation

enum SwarmCardStatus: String, Codable, Sendable {
    case running
    case completed
    case failed
    case idle
}

struct SwarmLiveCardState: Identifiable, Sendable {
    let swarmId: String
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

    var id: String { swarmId }

    static let liveTextMaxLength = 12_000

    init(
        swarmId: String,
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
        liveText: String = ""
    ) {
        self.swarmId = swarmId
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
    }
}
