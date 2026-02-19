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

@MainActor
final class TaskActivityStore: ObservableObject {
    @Published private(set) var activities: [TaskActivity] = []
    @Published private(set) var instantGreps: [InstantGrepResult] = []
    @Published private(set) var envelopes: [NormalizedEventEnvelope] = []

    func addActivity(_ activity: TaskActivity) {
        activities.append(activity)
    }

    func addInstantGrep(_ result: InstantGrepResult) {
        instantGreps.insert(result, at: 0)
        if instantGreps.count > 20 {
            instantGreps = Array(instantGreps.prefix(20))
        }
    }

    func addEnvelope(_ envelope: NormalizedEventEnvelope) {
        envelopes.insert(envelope, at: 0)
        if envelopes.count > 50 {
            envelopes = Array(envelopes.prefix(50))
        }
    }

    func clear() {
        activities.removeAll()
        instantGreps.removeAll()
        envelopes.removeAll()
    }
}
