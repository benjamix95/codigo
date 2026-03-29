import Foundation

struct ChatTurnCompletedSubagentsGroupEntry: Identifiable {
    let id: String
    let snapshot: SubagentCardSnapshot
    let liveCard: SwarmLiveCardState?

    init(snapshot: SubagentCardSnapshot, liveCard: SwarmLiveCardState? = nil) {
        self.id = snapshot.swarmId
        self.snapshot = snapshot
        self.liveCard = liveCard
    }

    var status: SwarmCardStatus {
        liveCard?.status ?? snapshot.status
    }

    var isRunning: Bool {
        status == .running
    }
}

struct ChatTurnCompletedSubagentsGroup {
    let id: String
    let entries: [ChatTurnCompletedSubagentsGroupEntry]
    let sequence: Int

    init(
        id: String,
        entries: [ChatTurnCompletedSubagentsGroupEntry],
        sequence: Int
    ) {
        self.id = id
        self.entries = entries
        self.sequence = sequence
    }

    init(
        id: String,
        cards: [SubagentCardSnapshot],
        sequence: Int
    ) {
        self.init(
            id: id,
            entries: cards.map { ChatTurnCompletedSubagentsGroupEntry(snapshot: $0) },
            sequence: sequence
        )
    }

    var cards: [SubagentCardSnapshot] {
        entries.map(\.snapshot)
    }

    var runningCount: Int {
        entries.filter(\.isRunning).count
    }

    var completedCount: Int {
        entries.filter { $0.status == .completed }.count
    }

    var failedCount: Int {
        entries.filter { $0.status == .failed }.count
    }

    var hasRunningEntries: Bool {
        runningCount > 0
    }
}
