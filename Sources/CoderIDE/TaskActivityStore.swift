import SwiftUI

/// Attività singola nel pannello task (Edit, Bash, Search, Agent role, ecc.)
struct TaskActivity: Identifiable {
    let id: UUID
    let type: String
    let title: String
    let detail: String?
    let payload: [String: String]
    let timestamp: Date

    init(
        id: UUID = UUID(),
        type: String,
        title: String,
        detail: String? = nil,
        payload: [String: String] = [:],
        timestamp: Date = .now
    ) {
        self.id = id
        self.type = type
        self.title = title
        self.detail = detail
        self.payload = payload
        self.timestamp = timestamp
    }
}

/// Store per le attività degli agenti (Edit, Bash, Search, ruoli swarm)
@MainActor
final class TaskActivityStore: ObservableObject {
    @Published private(set) var activities: [TaskActivity] = []

    func addActivity(_ activity: TaskActivity) {
        activities.append(activity)
    }

    func clear() {
        activities.removeAll()
    }
}
