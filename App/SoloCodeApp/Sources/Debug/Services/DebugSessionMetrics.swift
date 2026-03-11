import Foundation

struct DebugSessionMetrics: Codable, Equatable, Sendable {
    let totalOperations: Int
    let successfulOperations: Int
    let failedOperations: Int
    let totalRecoveries: Int
    let cumulativeDurationMs: Int
    let averageDurationMs: Int
    let lastStage: DebugExecutionStage?
}

extension DebugLifecycleMetrics {
    var sessionMetrics: DebugSessionMetrics {
        let average = totalOperations == 0 ? 0 : cumulativeDurationMs / totalOperations
        return DebugSessionMetrics(
            totalOperations: totalOperations,
            successfulOperations: successfulOperations,
            failedOperations: failedOperations,
            totalRecoveries: totalRecoveries,
            cumulativeDurationMs: cumulativeDurationMs,
            averageDurationMs: average,
            lastStage: lastStage?.stage
        )
    }
}

extension NativeDebugSessionState {
    var sessionMetrics: DebugSessionMetrics {
        metrics.sessionMetrics
    }
}
