import SwiftUI

enum ActivityPhase: String, Codable {
    case thinking
    case editing
    case executing
    case searching
    case planning
}

/// Attività singola nel pannello task (Edit, Bash, Search, Agent role, ecc.)
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

@MainActor
final class TaskActivityStore: ObservableObject {
    @Published private(set) var activities: [TaskActivity] = []
    @Published private(set) var instantGreps: [InstantGrepResult] = []
    @Published private(set) var envelopes: [NormalizedEventEnvelope] = []
    @Published private(set) var activeOperationsCount: Int = 0
    @Published private(set) var unseenLiveEventsCount: Int = 0

    func addActivity(_ activity: TaskActivity) {
        activities.append(activity)
        recalcActiveOperations()
    }

    func addInstantGrep(_ result: InstantGrepResult) {
        instantGreps.insert(result, at: 0)
        if instantGreps.count > 20 {
            instantGreps = Array(instantGreps.prefix(20))
        }
    }

    func addEnvelope(_ envelope: NormalizedEventEnvelope) {
        envelopes.insert(envelope, at: 0)
        unseenLiveEventsCount += 1
        if envelopes.count > 50 {
            envelopes = Array(envelopes.prefix(50))
        }
    }

    func markPaused() {
        unseenLiveEventsCount += 1
    }

    func markResumed() {
        unseenLiveEventsCount += 1
    }

    func markLiveEventsSeen() {
        unseenLiveEventsCount = 0
    }

    func appendOrMergeBatchEvent(_ activity: TaskActivity) {
        guard let groupId = activity.groupId else {
            addActivity(activity)
            return
        }
        if let idx = activities.lastIndex(where: { $0.groupId == groupId && $0.type == activity.type }) {
            activities[idx] = activity
        } else {
            activities.append(activity)
        }
        recalcActiveOperations()
    }

    private func recalcActiveOperations() {
        activeOperationsCount = activities.suffix(40).filter(\.isRunning).count
    }

    func clear() {
        activities.removeAll()
        instantGreps.removeAll()
        envelopes.removeAll()
        activeOperationsCount = 0
        unseenLiveEventsCount = 0
    }
}
