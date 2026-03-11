import Foundation

actor DebugExecutionCoordinator {
    private let service: DebugService
    private var lifecycleMetrics = DebugLifecycleMetrics.empty

    init(service: DebugService) {
        self.service = service
    }

    func execute(_ command: DebugExecutionCommand) async -> NativeDebugSessionState {
        let startedAt = Date()
        let state = await run(command)
        let recoveryCount = await service.recoveryStatus()?.totalRecoveryAttempts ?? 0
        let finishedAt = Date()
        let metrics = DebugStageMetrics(
            stage: command.stage,
            startedAt: startedAt,
            finishedAt: finishedAt,
            durationMs: max(Int(finishedAt.timeIntervalSince(startedAt) * 1000), 0),
            success: state.status != .error,
            adapter: state.adapter,
            breakpointCount: state.breakpointsCount,
            watchCount: state.watchVariables.count,
            recoveryCount: recoveryCount,
            failureReason: state.lastError
        )

        lifecycleMetrics.record(metrics)
        var enrichedState = state
        enrichedState.metrics = lifecycleMetrics
        enrichedState.payloadVersion = NativeDebugSessionState.currentPayloadVersion
        return enrichedState
    }

    func snapshotMetrics() -> DebugLifecycleMetrics {
        lifecycleMetrics
    }

    private func run(_ command: DebugExecutionCommand) async -> NativeDebugSessionState {
        switch command {
        case .start(let targetPath, let arguments, let breakpoints, let watchExpressions):
            return await service.startSession(
                targetPath: targetPath,
                arguments: arguments,
                breakpoints: breakpoints,
                watchExpressions: watchExpressions
            )
        case .stop:
            return await service.stopSession()
        case .syncBreakpoints(let breakpoints):
            return await service.syncBreakpoints(breakpoints)
        case .syncWatches(let expressions):
            return await service.syncWatches(expressions)
        case .refresh:
            return await service.refresh()
        case .stepIn:
            return await service.stepIn()
        case .stepOut:
            return await service.stepOut()
        case .stepOver:
            return await service.stepOver()
        }
    }
}
