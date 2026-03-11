import Foundation

enum DebugExecutionStage: String, Codable, Equatable, CaseIterable {
    case start
    case stop
    case syncBreakpoints = "sync_breakpoints"
    case syncWatches = "sync_watches"
    case refresh
    case stepIn = "step_in"
    case stepOut = "step_out"
    case stepOver = "step_over"
}

struct DebugStageMetrics: Codable, Equatable {
    let stage: DebugExecutionStage
    let startedAt: Date
    let finishedAt: Date
    let durationMs: Int
    let success: Bool
    let adapter: String
    let breakpointCount: Int
    let watchCount: Int
    let recoveryCount: Int
    let failureReason: String?
}

struct DebugLifecycleMetrics: Codable, Equatable {
    static let schemaVersion = 1

    var version: Int
    var totalOperations: Int
    var successfulOperations: Int
    var failedOperations: Int
    var totalRecoveries: Int
    var cumulativeDurationMs: Int
    var lastStage: DebugStageMetrics?

    static var empty: DebugLifecycleMetrics {
        DebugLifecycleMetrics(
            version: schemaVersion,
            totalOperations: 0,
            successfulOperations: 0,
            failedOperations: 0,
            totalRecoveries: 0,
            cumulativeDurationMs: 0,
            lastStage: nil
        )
    }

    mutating func record(_ stage: DebugStageMetrics) {
        version = Self.schemaVersion
        totalOperations += 1
        if stage.success {
            successfulOperations += 1
        } else {
            failedOperations += 1
        }
        totalRecoveries = max(totalRecoveries, stage.recoveryCount)
        cumulativeDurationMs += stage.durationMs
        lastStage = stage
    }
}

enum DebugExecutionCommand {
    case start(
        targetPath: String,
        arguments: [String],
        breakpoints: [DebugBreakpoint],
        watchExpressions: [String]
    )
    case stop
    case syncBreakpoints([DebugBreakpoint])
    case syncWatches([String])
    case refresh
    case stepIn
    case stepOut
    case stepOver

    var stage: DebugExecutionStage {
        switch self {
        case .start: return .start
        case .stop: return .stop
        case .syncBreakpoints: return .syncBreakpoints
        case .syncWatches: return .syncWatches
        case .refresh: return .refresh
        case .stepIn: return .stepIn
        case .stepOut: return .stepOut
        case .stepOver: return .stepOver
        }
    }
}
