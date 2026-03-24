import CoderEngine
import Foundation

// MARK: - DebugFlowState

/// Core debug flow state: phase, logs, hypotheses, breakpoints, text content.
struct DebugFlowState {
    var phase: DebugFlowPhase = .idle
    var logs: [DebugLogEntry] = []
    var hypotheses: [DebugHypothesis] = []
    var breakpoints: [DebugBreakpoint] = []
    var streamingContent: String = ""
    var errorSummary: String = ""
    var clarificationQuestions: String = ""
    var resolutionSummary: String = ""
}

// MARK: - DebugMarkerState

/// Debug markers, runtime logs, and instrumentation points.
struct DebugMarkerState {
    var debugMarkers: [DebugMarker] = []
    var runtimeLogs: [RuntimeLogEntry] = []
    var instrumentationPoints: [InstrumentationPoint] = []
}

// MARK: - DebugNativeInputState

/// Native debugger session and form input fields.
struct DebugNativeInputState {
    var nativeSession: NativeDebugSessionState = .idle
    var nativeTargetPathInput: String = ""
    var nativeArgumentsInput: String = ""
    var nativeWatchExpressionsInput: String = ""
    var nativeBreakpointFilePathInput: String = ""
    var nativeBreakpointLineInput: String = ""
    var nativeBreakpointConditionInput: String = ""
}

// MARK: - DebugSessionState

/// Session identifiers, workspace, flow diagram, iteration counters.
struct DebugSessionState {
    var currentRunId: String?
    var activeDebugSessionId: String?
    var debugWorkspacePath: String?
    var debugFlowDiagram: String = ""
    var fixLoopIteration: Int = 0
    var userConfirmedReproduce: Bool = false
    var awaitingDebugClean: Bool = false
}

// MARK: - DebugVariablesState

/// Native debugger variable inspection and expression evaluation state.
struct DebugVariablesState {
    var selectedFrameResult: FrameSelectionResult?
    var localVariables: [NativeVariable] = []
    var globalVariables: [NativeVariable] = []
    var argumentVariables: [NativeVariable] = []
    var lastExpressionResult: ExpressionResult?
    var expressionHistory: [ExpressionResult] = []
    var expressionInput: String = ""
}

// MARK: - DebugFilterState

/// Log panel filter controls.
struct DebugFilterState {
    var severityFilter: Set<DebugEntrySeverity> = Set(DebugEntrySeverity.allCases)
    var categoryFilter: String?
    var searchQuery: String = ""
}

// MARK: - DebugReportState

/// Findings, awaiting flags, report snapshots, stream logs.
struct DebugReportState {
    var debugFindings: [DebugFinding] = []
    var isAwaitingUserClarification: Bool = false
    var isAwaitingReproduceConfirmation: Bool = false
    var isAwaitingFixConfirmation: Bool = false
    var skippedQuestionsWarning: Bool = false
    var lastTraceAnalysis: String = ""
    var lastSnapshotReport: String = ""
    var lastTimelineReport: String = ""
    var lastTestCheckReport: String = ""
    var lastSessionExport: String = ""
    var streamLogs: [DebugStreamLogEntry] = []
    var streamLogNewCount: Int = 0
}
