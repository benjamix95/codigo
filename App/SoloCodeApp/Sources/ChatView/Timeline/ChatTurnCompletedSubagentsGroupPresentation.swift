import Foundation

struct ChatTurnCompletedSubagentsGroupExpansionState: Equatable {
    var isExpanded: Bool

    static func initial(hasCards: Bool) -> Self {
        Self(isExpanded: false)
    }

    mutating func toggle() {
        isExpanded.toggle()
    }
}

struct ChatTurnCompletedSubagentsGroupPresentation: Equatable {
    let title: String
    let badgeText: String
    let subtitle: String

    static func make(group: ChatTurnCompletedSubagentsGroup) -> Self {
        let totalCount = group.cards.count
        let title = totalCount == 1 ? "Sub-agent utilizzato" : "Sub-agent utilizzati"
        let badgeText = "\(totalCount)"
        let subtitle = statusSummary(
            completedCount: group.completedCount,
            failedCount: group.failedCount
        )
        return Self(
            title: title,
            badgeText: badgeText,
            subtitle: subtitle
        )
    }

    private static func statusSummary(
        completedCount: Int,
        failedCount: Int
    ) -> String {
        var parts: [String] = []
        if completedCount > 0 {
            let label = completedCount == 1 ? "completato" : "completati"
            parts.append("\(completedCount) \(label)")
        }
        if failedCount > 0 {
            let label = failedCount == 1 ? "fallito" : "falliti"
            parts.append("\(failedCount) \(label)")
        }
        if parts.isEmpty {
            return "Nessun sub-agent completato"
        }
        return parts.joined(separator: " · ")
    }
}
