import Foundation

enum ActivityPhase: String, Codable {
    case thinking
    case editing
    case executing
    case searching
    case planning
}

struct TaskActivity: Identifiable {
    let id: UUID
    let type: String
    let title: String
    let detail: String?
    let payload: [String: String]
    let timestamp: Date
    let phase: ActivityPhase
    let isRunning: Bool
    let groupId: String?

    init(
        id: UUID = UUID(),
        type: String,
        title: String,
        detail: String? = nil,
        payload: [String: String] = [:],
        timestamp: Date = .now,
        phase: ActivityPhase = .thinking,
        isRunning: Bool = true,
        groupId: String? = nil
    ) {
        self.id = id
        self.type = type
        self.title = title
        self.detail = detail
        self.payload = payload
        self.timestamp = timestamp
        self.phase = phase
        self.isRunning = isRunning
        self.groupId = groupId
    }
}

enum SwarmLaneStatus: String, Sendable {
    case running
    case completed
    case failed
    case idle
}

struct SwarmLaneState: Identifiable, Sendable {
    let id: String
    let swarmId: String
    let status: SwarmLaneStatus
    let lastEventAt: Date?
    let currentActivityTitle: String
    let events: [TaskActivity]
    let activeOpsCount: Int
    let errorsCount: Int
    let hasUnreadWhileCollapsed: Bool
}
