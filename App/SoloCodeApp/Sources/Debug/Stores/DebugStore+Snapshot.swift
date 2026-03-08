extension DebugStore {
    struct SessionSnapshot {
        var phase: DebugFlowPhase
        var logs: [DebugLogEntry]
        var hypotheses: [DebugHypothesis]
        var breakpoints: [DebugBreakpoint]
        var streamingContent: String
        var errorSummary: String
        var clarificationQuestions: String
        var resolutionSummary: String
        var debugMarkers: [DebugMarker]
        var runtimeLogs: [RuntimeLogEntry]
        var instrumentationPoints: [InstrumentationPoint]
        var currentRunId: String?
        var debugFlowDiagram: String
        var fixLoopIteration: Int
        var userConfirmedReproduce: Bool
        var awaitingDebugClean: Bool
        var pendingResolutionAfterClean: String?
        var severityFilter: Set<DebugEntrySeverity>
        var categoryFilter: String?
        var searchQuery: String
        var nativeSession: NativeDebugSessionState
        var nativeTargetPathInput: String
        var nativeArgumentsInput: String
        var nativeWatchExpressionsInput: String
        var nativeBreakpointFilePathInput: String
        var nativeBreakpointLineInput: String
        var nativeBreakpointConditionInput: String
    }

    func snapshot() -> SessionSnapshot {
        SessionSnapshot(
            phase: phase,
            logs: logs,
            hypotheses: hypotheses,
            breakpoints: breakpoints,
            streamingContent: streamingContent,
            errorSummary: errorSummary,
            clarificationQuestions: clarificationQuestions,
            resolutionSummary: resolutionSummary,
            debugMarkers: debugMarkers,
            runtimeLogs: runtimeLogs,
            instrumentationPoints: instrumentationPoints,
            currentRunId: currentRunId,
            debugFlowDiagram: debugFlowDiagram,
            fixLoopIteration: fixLoopIteration,
            userConfirmedReproduce: userConfirmedReproduce,
            awaitingDebugClean: awaitingDebugClean,
            pendingResolutionAfterClean: pendingResolutionAfterClean,
            severityFilter: severityFilter,
            categoryFilter: categoryFilter,
            searchQuery: searchQuery,
            nativeSession: nativeSession,
            nativeTargetPathInput: nativeTargetPathInput,
            nativeArgumentsInput: nativeArgumentsInput,
            nativeWatchExpressionsInput: nativeWatchExpressionsInput,
            nativeBreakpointFilePathInput: nativeBreakpointFilePathInput,
            nativeBreakpointLineInput: nativeBreakpointLineInput,
            nativeBreakpointConditionInput: nativeBreakpointConditionInput
        )
    }

    func restore(from snapshot: SessionSnapshot) {
        phase = snapshot.phase
        logs = snapshot.logs
        hypotheses = snapshot.hypotheses
        breakpoints = snapshot.breakpoints
        streamingContent = snapshot.streamingContent
        errorSummary = snapshot.errorSummary
        clarificationQuestions = snapshot.clarificationQuestions
        resolutionSummary = snapshot.resolutionSummary
        debugMarkers = snapshot.debugMarkers
        runtimeLogs = snapshot.runtimeLogs
        instrumentationPoints = snapshot.instrumentationPoints
        currentRunId = snapshot.currentRunId
        debugFlowDiagram = snapshot.debugFlowDiagram
        fixLoopIteration = snapshot.fixLoopIteration
        userConfirmedReproduce = snapshot.userConfirmedReproduce
        awaitingDebugClean = snapshot.awaitingDebugClean
        pendingResolutionAfterClean = snapshot.pendingResolutionAfterClean
        severityFilter = snapshot.severityFilter
        categoryFilter = snapshot.categoryFilter
        searchQuery = snapshot.searchQuery
        nativeSession = snapshot.nativeSession
        nativeTargetPathInput = snapshot.nativeTargetPathInput
        nativeArgumentsInput = snapshot.nativeArgumentsInput
        nativeWatchExpressionsInput = snapshot.nativeWatchExpressionsInput
        nativeBreakpointFilePathInput = snapshot.nativeBreakpointFilePathInput
        nativeBreakpointLineInput = snapshot.nativeBreakpointLineInput
        nativeBreakpointConditionInput = snapshot.nativeBreakpointConditionInput
    }
}
