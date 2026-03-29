import Foundation

struct ChatTurnCompletedSubagentsGroup: Equatable {
    let id: String
    let cards: [SubagentCardSnapshot]
    let sequence: Int

    var completedCount: Int {
        cards.filter { $0.status == .completed }.count
    }

    var failedCount: Int {
        cards.filter { $0.status == .failed }.count
    }
}
