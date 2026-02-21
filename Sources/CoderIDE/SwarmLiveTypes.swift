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
    var recentEvents: [TaskActivity]
    var summary: String?
    var isCollapsed: Bool
    var hasUnreadSinceCollapse: Bool

    var id: String { swarmId }

    init(
        swarmId: String,
        status: SwarmCardStatus = .idle,
        startedAt: Date? = nil,
        lastEventAt: Date? = nil,
        completedAt: Date? = nil,
        currentStepTitle: String = "In attesa eventi",
        currentDetail: String = "",
        activeOpsCount: Int = 0,
        errorCount: Int = 0,
        recentEvents: [TaskActivity] = [],
        summary: String? = nil,
        isCollapsed: Bool = false,
        hasUnreadSinceCollapse: Bool = false
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
        self.recentEvents = recentEvents
        self.summary = summary
        self.isCollapsed = isCollapsed
        self.hasUnreadSinceCollapse = hasUnreadSinceCollapse
    }
}
