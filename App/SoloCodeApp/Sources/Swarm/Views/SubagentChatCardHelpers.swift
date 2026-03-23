import CoderEngine
import SwiftUI

enum WorkerPresentationRole: String, CaseIterable {
    case planner
    case explorer
    case coder
    case debugger
    case reviewer
    case bugHunter
    case docWriter
    case securityAuditor
    case testWriter

    var displayName: String {
        switch self {
        case .planner: return "Planner"
        case .explorer: return "Explorer"
        case .coder: return "Coder"
        case .debugger: return "Debugger"
        case .reviewer: return "Reviewer"
        case .bugHunter: return "BugHunter"
        case .docWriter: return "DocWriter"
        case .securityAuditor: return "SecurityAuditor"
        case .testWriter: return "TestWriter"
        }
    }

    static func fromWorkerID(_ raw: String) -> WorkerPresentationRole? {
        let normalized = raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: "_", with: "")
            .lowercased()
        switch normalized {
        case "planner": return .planner
        case "explorer": return .explorer
        case "coder": return .coder
        case "debugger": return .debugger
        case "reviewer": return .reviewer
        case "bughunter", "bugfinder": return .bugHunter
        case "docwriter": return .docWriter
        case "securityauditor": return .securityAuditor
        case "testwriter", "tester": return .testWriter
        default: return nil
        }
    }
}

enum SubagentChatCardHelpers {
    static func roleDisplayName(from swarmId: String) -> String {
        let normalized = swarmId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return "Subagent" }

        let head = normalized.components(separatedBy: "-").first ?? normalized
        if let role = WorkerPresentationRole.fromWorkerID(head) {
            return role.displayName
        }

        return "Subagent"
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
