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
        var activeDebugSessionId: String?
        var debugWorkspacePath: String?
        var debugFlowDiagram: String
        var lastTraceAnalysis: String
        var lastSnapshotReport: String
        var lastTimelineReport: String
        var lastTestCheckReport: String
        var lastSessionExport: String
        var fixLoopIteration: Int
        var userConfirmedReproduce: Bool
        var awaitingDebugClean: Bool
        var isAwaitingUserClarification: Bool
        var isAwaitingReproduceConfirmation: Bool
        var isAwaitingFixConfirmation: Bool
        var skippedQuestionsWarning: Bool
        var pendingResolutionAfterClean: String?
        var debugFindings: [DebugFinding]
        var streamLogs: [DebugStreamLogEntry]
        var streamLogNewCount: Int
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
            activeDebugSessionId: activeDebugSessionId,
            debugWorkspacePath: debugWorkspacePath,
            debugFlowDiagram: debugFlowDiagram,
            lastTraceAnalysis: lastTraceAnalysis,
            lastSnapshotReport: lastSnapshotReport,
            lastTimelineReport: lastTimelineReport,
            lastTestCheckReport: lastTestCheckReport,
            lastSessionExport: lastSessionExport,
            fixLoopIteration: fixLoopIteration,
            userConfirmedReproduce: userConfirmedReproduce,
            awaitingDebugClean: awaitingDebugClean,
            isAwaitingUserClarification: isAwaitingUserClarification,
            isAwaitingReproduceConfirmation: isAwaitingReproduceConfirmation,
            isAwaitingFixConfirmation: isAwaitingFixConfirmation,
            skippedQuestionsWarning: skippedQuestionsWarning,
            pendingResolutionAfterClean: pendingResolutionAfterClean,
            debugFindings: debugFindings,
            streamLogs: streamLogs,
            streamLogNewCount: streamLogNewCount,
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
        cancelDebugSessionWatchdogTasks()
        stopLogFileMonitor()

        flow = DebugFlowState(
            phase: snapshot.phase,
            logs: snapshot.logs,
            hypotheses: snapshot.hypotheses,
            breakpoints: snapshot.breakpoints,
            streamingContent: snapshot.streamingContent,
            errorSummary: snapshot.errorSummary,
            clarificationQuestions: snapshot.clarificationQuestions,
            resolutionSummary: snapshot.resolutionSummary
        )
        markers = DebugMarkerState(
            debugMarkers: snapshot.debugMarkers,
            runtimeLogs: snapshot.runtimeLogs,
            instrumentationPoints: snapshot.instrumentationPoints
        )
        session = DebugSessionState(
            currentRunId: snapshot.currentRunId,
            activeDebugSessionId: snapshot.activeDebugSessionId,
            debugWorkspacePath: snapshot.debugWorkspacePath,
            debugFlowDiagram: snapshot.debugFlowDiagram,
            fixLoopIteration: snapshot.fixLoopIteration,
            userConfirmedReproduce: snapshot.userConfirmedReproduce,
            awaitingDebugClean: snapshot.awaitingDebugClean
        )
        nativeInput = DebugNativeInputState(
            nativeSession: snapshot.nativeSession,
            nativeTargetPathInput: snapshot.nativeTargetPathInput,
            nativeArgumentsInput: snapshot.nativeArgumentsInput,
            nativeWatchExpressionsInput: snapshot.nativeWatchExpressionsInput,
            nativeBreakpointFilePathInput: snapshot.nativeBreakpointFilePathInput,
            nativeBreakpointLineInput: snapshot.nativeBreakpointLineInput,
            nativeBreakpointConditionInput: snapshot.nativeBreakpointConditionInput
        )
        filters = DebugFilterState(
            severityFilter: snapshot.severityFilter,
            categoryFilter: snapshot.categoryFilter,
            searchQuery: snapshot.searchQuery
        )
        reports = DebugReportState(
            debugFindings: snapshot.debugFindings,
            isAwaitingUserClarification: snapshot.isAwaitingUserClarification,
            isAwaitingReproduceConfirmation: snapshot.isAwaitingReproduceConfirmation,
            isAwaitingFixConfirmation: snapshot.isAwaitingFixConfirmation,
            skippedQuestionsWarning: snapshot.skippedQuestionsWarning,
            lastTraceAnalysis: snapshot.lastTraceAnalysis,
            lastSnapshotReport: snapshot.lastSnapshotReport,
            lastTimelineReport: snapshot.lastTimelineReport,
            lastTestCheckReport: snapshot.lastTestCheckReport,
            lastSessionExport: snapshot.lastSessionExport,
            streamLogs: snapshot.streamLogs,
            streamLogNewCount: snapshot.streamLogNewCount
        )
        pendingResolutionAfterClean = snapshot.pendingResolutionAfterClean

        reconcileWatchdogAndLogMonitorAfterBulkSessionRestore()
    }
}
