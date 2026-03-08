import CoderEngine
import SwiftUI

enum SubagentChatCardHelpers {
    static func roleDisplayName(from swarmId: String) -> String {
        let normalized = swarmId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return "Subagent" }

        if let role = SubagentRole.fromToolName("subagent_\(normalized)") {
            return role.displayName
        }

        let genericRolePrefixes = SubagentRole.allCases.map(\.rawValue)
        let lowercase = normalized.lowercased()
        if genericRolePrefixes.contains(where: { prefix in
            lowercase == prefix || lowercase.hasPrefix("\(prefix)-")
        }) {
            return normalized.components(separatedBy: "-").first?.capitalized ?? normalized
        }

        return normalized
    }

    static func runningSubtitle(
        detail: String,
        liveText: String,
        title: String? = nil,
        fallback: String = "Working..."
    ) -> String {
        if let liveLine = SwarmLivePresentation.latestMeaningfulLiveLine(
            from: liveText,
            excluding: title
        ) {
            return liveLine
        }

        if let detailLine = SwarmLivePresentation.normalizedSubtitleText(
            detail,
            excluding: title
        ) {
            return detailLine
        }

        return fallback
    }
}
