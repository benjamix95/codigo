import CoderEngine
import SwiftUI

enum ReviewFindingHistoryStatusFilter: String, CaseIterable, Identifiable {
    case resumeQueue = "Resume"
    case open = "Open"
    case inProgress = "In Progress"
    case resolved = "Resolved"
    case all = "All"

    var id: String { rawValue }
}

enum ReviewFindingHistoryDomainFilter: String, CaseIterable, Identifiable {
    case all = "All Domains"
    case bug = "Bug"
    case security = "Security"

    var id: String { rawValue }
}

enum ReviewFindingHistorySeverityFilter: String, CaseIterable, Identifiable {
    case all = "All Severities"
    case critical = "Critical"
    case high = "High"
    case medium = "Medium"
    case low = "Low"
    case info = "Info"

    var id: String { rawValue }
}

extension HistoricalFindingRecord {
    var historyBucket: ReviewFindingHistoryStatusFilter {
        switch status {
        case .candidate, .verifying, .verified, .needsManualReview:
            return .open
        case .patchPreparing, .patchPrepared, .patchReviewed, .patchApplied, .revalidating, .fixFailed, .rollbackApplied:
            return .inProgress
        case .fixedVerified, .closed, .rejected:
            return .resolved
        }
    }

    var historyStatusLabel: String {
        status.rawValue
            .replacingOccurrences(of: "_", with: " ")
            .capitalized
    }

    var historyStatusColor: Color {
        switch historyBucket {
        case .resumeQueue:
            return DesignSystem.Colors.warning
        case .open:
            return DesignSystem.Colors.reviewColor
        case .inProgress:
            return DesignSystem.Colors.info
        case .resolved:
            return DesignSystem.Colors.success
        case .all:
            return .secondary
        }
    }

    var domainLabel: String {
        domain == .security ? "Security" : "Bug"
    }

    var sourceLabel: String {
        sourceOrigin?.isEmpty == false ? sourceOrigin! : domain.rawValue
    }

    var latestLifecycleLabel: String {
        if let verdict = revalidationVerdict?.rawValue {
            return verdict.replacingOccurrences(of: "_", with: " ").capitalized
        }
        if let patchApplyStatus = patchApplyStatus?.rawValue {
            return patchApplyStatus.replacingOccurrences(of: "_", with: " ").capitalized
        }
        return historyStatusLabel
    }

    func matches(statusFilter: ReviewFindingHistoryStatusFilter) -> Bool {
        switch statusFilter {
        case .resumeQueue:
            return resumeEligible
        case .open:
            return historyBucket == .open
        case .inProgress:
            return historyBucket == .inProgress
        case .resolved:
            return historyBucket == .resolved
        case .all:
            return true
        }
    }

    func matches(domainFilter: ReviewFindingHistoryDomainFilter) -> Bool {
        switch domainFilter {
        case .all:
            return true
        case .bug:
            return domain == .bug
        case .security:
            return domain == .security
        }
    }

    func matches(severityFilter: ReviewFindingHistorySeverityFilter) -> Bool {
        switch severityFilter {
        case .all:
            return true
        case .critical:
            return severity == .critical
        case .high:
            return severity == .high
        case .medium:
            return severity == .medium
        case .low:
            return severity == .low
        case .info:
            return severity == .info
        }
    }
}

struct ReviewHistoricalLiveWorkerState: Identifiable, Equatable {
    let id: String
    let title: String
    let detail: String
    let severity: FindingSeverity
    let status: SwarmCardStatus
    let files: [String]
    let fileCount: Int

    var statusLabel: String {
        status.rawValue.capitalized
    }
}

struct ReviewHistoricalLiveFileState: Identifiable, Equatable {
    let path: String
    let workerIDs: [String]
    let severity: FindingSeverity
    let status: SwarmCardStatus

    var id: String { path }

    var fileName: String {
        URL(fileURLWithPath: path).lastPathComponent
    }

    var statusLabel: String {
        status.rawValue.capitalized
    }
}

struct ReviewHistoricalLiveBoardState: Equatable {
    let title: String
    let subtitle: String
    let pipeline: ReviewPipelineJobState
    let workers: [ReviewHistoricalLiveWorkerState]
    let files: [ReviewHistoricalLiveFileState]
    let isRunning: Bool
}
