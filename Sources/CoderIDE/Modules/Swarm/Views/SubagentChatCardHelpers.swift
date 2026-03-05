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
        fallback: String = "Working..."
    ) -> String {
        if let liveLine = latestMeaningfulLiveLine(from: liveText) {
            return liveLine
        }

        let trimmedDetail = detail.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedDetail.isEmpty {
            return trimmedDetail
        }

        return fallback
    }

    private static func latestMeaningfulLiveLine(from text: String) -> String? {
        let lines = text
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        for line in lines.reversed() {
            let lower = line.lowercased()
            if lower == "started" || lower == "completed" || lower == "failed" {
                continue
            }
            return String(line.prefix(120))
        }
        return nil
    }
}
