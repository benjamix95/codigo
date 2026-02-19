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

    func push(providerId: String, eventType: String, summary: String) {
        entries.insert(FlowDiagnosticEntry(providerId: providerId, eventType: eventType, summary: summary), at: 0)
        if entries.count > 20 {
            entries = Array(entries.prefix(20))
        }
    }

    func setError(_ value: String?) {
        lastError = value
    }
}
