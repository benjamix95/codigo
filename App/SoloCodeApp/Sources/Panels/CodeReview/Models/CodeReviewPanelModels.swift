import CoderEngine
import Foundation
import SwiftUI

// MARK: - Tabs

enum CodeReviewTab: String, CaseIterable {
    case commands = "Commands"
    case findings = "Findings"
    case timeline = "Timeline"
    case chat = "Chat"
    case settings = "Settings"

    var icon: String {
        switch self {
        case .commands: return "terminal"
        case .findings: return "exclamationmark.triangle"
        case .timeline: return "clock"
        case .chat: return "bubble.left.and.bubble.right"
        case .settings: return "gearshape"
        }
    }
}

// MARK: - Pipeline Modes

enum CodeReviewPanelMode: String, CaseIterable, Identifiable {
    case standard = "Standard"
    case securityAudit = "Security Audit"
    case bugFinder = "Bug Finder"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .standard: return "magnifyingglass"
        case .securityAudit: return "lock.shield"
        case .bugFinder: return "ladybug"
        }
    }

    var displayName: String { rawValue }

    var accentColor: Color {
        switch self {
        case .standard: return DesignSystem.Colors.reviewColor
        case .securityAudit: return DesignSystem.Colors.error
        case .bugFinder: return DesignSystem.Colors.warning
        }
    }
}

// MARK: - Scope Target

enum ReviewScopeTarget: Equatable {
    case uncommitted
    case staged
    case againstRef(String)
    case branch(String)
    case commits([String])

    var displayDescription: String {
        switch self {
        case .uncommitted: return "Uncommitted changes"
        case .staged: return "Staged changes"
        case .againstRef(let ref): return "Against \(ref)"
        case .branch(let name): return "Branch \(name)"
        case .commits(let shas):
            let count = shas.count
            return count == 1
                ? "Commit \(shas[0].prefix(8))"
                : "\(count) commits"
        }
    }

    var scopeTag: String {
        switch self {
        case .uncommitted: return "[REVIEW_SCOPE:uncommitted]"
        case .staged: return "[REVIEW_SCOPE:staged]"
        case .againstRef(let ref): return "[AGAINST:\(ref)]"
        case .branch(let name): return "[AGAINST:\(name)]"
        case .commits(let shas):
            if shas.count == 1 {
                return "[AGAINST:\(shas[0])^..\(shas[0])]"
            }
            let first = shas.last ?? ""
            let last = shas.first ?? ""
            return "[AGAINST:\(first)^..\(last)]"
        }
    }
}

// MARK: - Metrics

struct CodeReviewMetrics {
    let cards: [SwarmLiveCardState]
    let activeCount: Int
    let workers: [ReviewWorkerRow]
    let roundInfo: (round: String, maxRounds: String)?
}

struct ReviewWorkerRow: Identifiable {
    let id: String
    let description: String
    let severity: FindingSeverity
    let fileCount: Int
    let files: [String]
    let filesSummary: String
}

// MARK: - Helper Functions

func shouldDisplayCodeReviewMetrics(
    isRunning: Bool,
    hasReviewArtifacts: Bool
) -> Bool {
    isRunning || hasReviewArtifacts
}

func hasCodeReviewArtifactsCheck(
    cards: [SwarmLiveCardState],
    workerActivities: [TaskActivity],
    activities: [TaskActivity]
) -> Bool {
    !cards.isEmpty
        || !workerActivities.isEmpty
        || activities.contains(where: { $0.type == "review-fix-round" })
}

// MARK: - Severity Helpers

func reviewSeverityColor(_ severity: FindingSeverity) -> Color {
    switch severity {
    case .critical: return DesignSystem.Colors.error
    case .warning: return DesignSystem.Colors.warning
    case .suggestion: return DesignSystem.Colors.info
    case .info: return .secondary
    }
}

func reviewStatusLabel(_ status: FindingStatus) -> (String, Color) {
    switch status {
    case .open: return ("Open", DesignSystem.Colors.reviewColor)
    case .fixApplied, .patchApplied: return ("Applied", DesignSystem.Colors.success)
    case .patchPreparing: return ("Preparing", DesignSystem.Colors.info)
    case .patchReady: return ("Patch Ready", DesignSystem.Colors.info)
    case .patchApplying: return ("Applying", DesignSystem.Colors.info)
    case .patchFailed: return ("Patch Failed", DesignSystem.Colors.error)
    case .prOpened: return ("PR Open", DesignSystem.Colors.info)
    case .merged: return ("Merged", DesignSystem.Colors.success)
    case .blocked: return ("Blocked", DesignSystem.Colors.error)
    case .dismissed: return ("Dismissed", .secondary)
    case .wontFix: return ("Won't Fix", .secondary)
    }
}
