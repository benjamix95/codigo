import SwiftUI

struct FlowDiagnosticEntry: Identifiable {
    let id: UUID
    let timestamp: Date
    let providerId: String
    let eventType: String
    let summary: String

    init(id: UUID = UUID(), timestamp: Date = .now, providerId: String, eventType: String, summary: String) {
        self.id = id
        self.timestamp = timestamp
        self.providerId = providerId
        self.eventType = eventType
        self.summary = summary
    }
}

@MainActor
final class FlowDiagnosticsStore: ObservableObject {
    @Published var flowState: String = "idle"
    @Published var selectedProviderId: String = ""
    @Published private(set) var entries: [FlowDiagnosticEntry] = []
    @Published private(set) var lastError: String?
    @Published private(set) var swarmEventsReceived: Int = 0
    @Published private(set) var swarmEventsAssigned: Int = 0
    @Published private(set) var swarmEventsFallback: Int = 0

    func push(providerId: String, eventType: String, summary: String) {
        entries.insert(FlowDiagnosticEntry(providerId: providerId, eventType: eventType, summary: summary), at: 0)
        if entries.count > 20 {
            entries = Array(entries.prefix(20))
        }
    }

    func setError(_ value: String?) {
        lastError = value
    }

    func recordSwarmRouting(assignedToSwarm: Bool, fallbackToOrchestrator: Bool) {
        swarmEventsReceived += 1
        if assignedToSwarm {
            swarmEventsAssigned += 1
        }
        if fallbackToOrchestrator {
            swarmEventsFallback += 1
        }
    }
}
