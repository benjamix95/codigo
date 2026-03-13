import CoderEngine
import Foundation
import SwiftUI

// MARK: - Tabs

enum CodeReviewTab: String, CaseIterable {
    case commands = "Commands"
    case findings = "Findings"
    case history = "Findings History"
    case timeline = "Timeline"
    case chat = "Chat"
    case settings = "Settings"

    var icon: String {
        switch self {
        case .commands: return "terminal"
        case .findings: return "exclamationmark.triangle"
        case .history: return "clock.arrow.circlepath"
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
    case workspace
    case againstRef(String)
    case branch(String)
    case commits([String])

    var displayDescription: String {
        switch self {
        case .uncommitted: return "Uncommitted changes"
        case .staged: return "Staged changes"
        case .workspace: return "Workspace source files"
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
        case .workspace: return "[REVIEW_SCOPE:workspace]"
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
        case .closed: return ("Closed", .secondary)
    }
}

struct ReviewPipelineToolExecution: Identifiable, Equatable {
    enum Status: Equatable {
        case pending
        case running
        case completed
    }

    let id: String
    let title: String
    let status: Status
    let findingsCount: Int
}

struct ReviewPipelineGateState: Equatable {
    let title: String
    let isReady: Bool
}

struct ReviewPipelineJobState: Equatable {
    let title: String
    let phase: String
    let progressPercent: Int
    let stepsCompleted: Int
    let stepsTotal: Int
    let toolsTotal: Int
    let toolsCompleted: Int
    let toolsRunning: Int
    let candidateCount: Int
    let verifiedCount: Int
    let publishedFindingCount: Int
    let hiddenFindingCount: Int
    let gates: [ReviewPipelineGateState]
    let tools: [ReviewPipelineToolExecution]
    let phaseLedger: [ReviewPipelinePhaseLedgerEntry]
    let bundleModes: [String]
    let isTerminal: Bool

    var phaseLabel: String {
        switch phase {
        case "queued", "discovery": return "Avvio"
        case "audit": return "Controlli"
        case "verification": return "Verifica"
        case "patch_preparation": return "Preparazione fix"
        case "publish_ready", "completed": return "Risultati pronti"
        default: return phase.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }

    var visibleStepsTotal: Int { 5 }

    var visibleStepNumber: Int {
        switch phase {
        case "queued", "discovery": return 5
        case "audit": return 4
        case "verification": return 3
        case "patch_preparation": return 2
        case "publish_ready", "completed": return 1
        default:
            let normalized = min(max(stepsCompleted, 1), visibleStepsTotal)
            return visibleStepsTotal - normalized + 1
        }
    }

    var progressText: String { "\(progressPercent)%" }

    var phaseColor: Color {
        switch phase {
        case "completed", "publish_ready":
            return DesignSystem.Colors.success
        case "patch_preparation":
            return DesignSystem.Colors.info
        case "verification":
            return DesignSystem.Colors.warning
        case "audit", "discovery", "queued":
            return DesignSystem.Colors.reviewColor
        default:
            return .secondary
        }
    }
}

enum ReviewPanelWarmState: String, Equatable {
    case idle
    case warming
    case ready
    case failed
}

struct ReviewPanelDerivedState {
    let sessionId: String
    let mutationSequence: UInt64
    let liveCandidates: [ReviewCandidate]
    let verifiedFindings: [CodeReviewFinding]
    let publishReadyFindings: [CodeReviewFinding]
    let publishedSeverityCounts: [FindingSeverity: Int]
    let pipelineJobState: ReviewPipelineJobState?
    let projection: VerifiedFindingsProjectionSnapshot
    let verifiedEnvelope: VerifiedFindingsSessionEnvelope?
    let phaseLedger: [ReviewPipelinePhaseLedgerEntry]
    let fileLedger: [ReviewPipelineFileLedgerEntry]
    let warmState: ReviewPanelWarmState
    let emptyStateTitle: String
    let emptyStateSubtitle: String
}
