import Foundation

struct ChatTurnCompletedSubagentsGroupExpansionState: Equatable {
    var isExpanded: Bool
    var didAutoCollapseAfterCompletion: Bool

    static func initial(
        hasEntries: Bool,
        hasRunningEntries: Bool
    ) -> Self {
        Self(
            isExpanded: hasRunningEntries,
            didAutoCollapseAfterCompletion: hasEntries && !hasRunningEntries
        )
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
        let totalCount = group.entries.count
        let title = "sub-agents"
        let badgeText = "\(totalCount)"
        let subtitle = statusSummary(
            runningCount: group.runningCount,
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
        runningCount: Int,
        completedCount: Int,
        failedCount: Int
    ) -> String {
        var parts: [String] = []
        if runningCount > 0 {
            parts.append("\(runningCount) in esecuzione")
        }
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

    static func reconcile(
        current: ChatTurnCompletedSubagentsGroupExpansionState,
        hasEntries: Bool,
        hasRunningEntries: Bool
    ) -> ChatTurnCompletedSubagentsGroupExpansionState {
        if hasRunningEntries {
            var updated = current
            updated.didAutoCollapseAfterCompletion = false
            return updated
        }

        guard hasEntries, !current.didAutoCollapseAfterCompletion else {
            return current
        }

        return ChatTurnCompletedSubagentsGroupExpansionState(
            isExpanded: false,
            didAutoCollapseAfterCompletion: true
        )
    }
}
