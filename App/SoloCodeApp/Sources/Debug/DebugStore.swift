import Combine
import SwiftUI
import CoderEngine

@MainActor
final class DebugStore: ObservableObject {
    // MARK: - Grouped Published State (44 → 7 structs)

    @Published var flow = DebugFlowState()
    @Published var markers = DebugMarkerState()
    @Published var nativeInput = DebugNativeInputState()
    @Published var session = DebugSessionState()
    @Published var variables = DebugVariablesState()
    @Published var filters = DebugFilterState()
    @Published var reports = DebugReportState()

    // MARK: - Backward-compatible accessors: Flow

    var phase: DebugFlowPhase {
        get { flow.phase }
        set { flow.phase = newValue }
    }
    var logs: [DebugLogEntry] {
        get { flow.logs }
        set { flow.logs = newValue }
    }
    var hypotheses: [DebugHypothesis] {
        get { flow.hypotheses }
        set { flow.hypotheses = newValue }
    }
    var breakpoints: [DebugBreakpoint] {
        get { flow.breakpoints }
        set { flow.breakpoints = newValue }
    }
    var streamingContent: String {
        get { flow.streamingContent }
        set { flow.streamingContent = newValue }
    }
    var errorSummary: String {
        get { flow.errorSummary }
        set { flow.errorSummary = newValue }
    }
    var clarificationQuestions: String {
        get { flow.clarificationQuestions }
        set { flow.clarificationQuestions = newValue }
    }
    var resolutionSummary: String {
        get { flow.resolutionSummary }
        set { flow.resolutionSummary = newValue }
    }

    // MARK: - Backward-compatible accessors: Markers

    var debugMarkers: [DebugMarker] {
        get { markers.debugMarkers }
        set { markers.debugMarkers = newValue }
    }
    var runtimeLogs: [RuntimeLogEntry] {
        get { markers.runtimeLogs }
        set { markers.runtimeLogs = newValue }
    }
    var instrumentationPoints: [InstrumentationPoint] {
        get { markers.instrumentationPoints }
        set { markers.instrumentationPoints = newValue }
    }

    // MARK: - Backward-compatible accessors: Native Input

    var nativeSession: NativeDebugSessionState {
        get { nativeInput.nativeSession }
        set { nativeInput.nativeSession = newValue }
    }
    var nativeTargetPathInput: String {
        get { nativeInput.nativeTargetPathInput }
        set { nativeInput.nativeTargetPathInput = newValue }
    }
    var nativeArgumentsInput: String {
        get { nativeInput.nativeArgumentsInput }
        set { nativeInput.nativeArgumentsInput = newValue }
    }
    var nativeWatchExpressionsInput: String {
        get { nativeInput.nativeWatchExpressionsInput }
        set { nativeInput.nativeWatchExpressionsInput = newValue }
    }
    var nativeBreakpointFilePathInput: String {
        get { nativeInput.nativeBreakpointFilePathInput }
        set { nativeInput.nativeBreakpointFilePathInput = newValue }
    }
    var nativeBreakpointLineInput: String {
        get { nativeInput.nativeBreakpointLineInput }
        set { nativeInput.nativeBreakpointLineInput = newValue }
    }
    var nativeBreakpointConditionInput: String {
        get { nativeInput.nativeBreakpointConditionInput }
        set { nativeInput.nativeBreakpointConditionInput = newValue }
    }

    // MARK: - Backward-compatible accessors: Session

    var currentRunId: String? {
        get { session.currentRunId }
        set { session.currentRunId = newValue }
    }
    var activeDebugSessionId: String? {
        get { session.activeDebugSessionId }
        set { session.activeDebugSessionId = newValue }
    }
    var debugWorkspacePath: String? {
        get { session.debugWorkspacePath }
        set { session.debugWorkspacePath = newValue }
    }
    var debugFlowDiagram: String {
        get { session.debugFlowDiagram }
        set { session.debugFlowDiagram = newValue }
    }
    var fixLoopIteration: Int {
        get { session.fixLoopIteration }
        set { session.fixLoopIteration = newValue }
    }
    var userConfirmedReproduce: Bool {
        get { session.userConfirmedReproduce }
        set { session.userConfirmedReproduce = newValue }
    }
    var awaitingDebugClean: Bool {
        get { session.awaitingDebugClean }
        set { session.awaitingDebugClean = newValue }
    }

    // MARK: - Backward-compatible accessors: Variables

    var selectedFrameResult: FrameSelectionResult? {
        get { variables.selectedFrameResult }
        set { variables.selectedFrameResult = newValue }
    }
    var localVariables: [NativeVariable] {
        get { variables.localVariables }
        set { variables.localVariables = newValue }
    }
    var globalVariables: [NativeVariable] {
        get { variables.globalVariables }
        set { variables.globalVariables = newValue }
    }
    var argumentVariables: [NativeVariable] {
        get { variables.argumentVariables }
        set { variables.argumentVariables = newValue }
    }
    var lastExpressionResult: ExpressionResult? {
        get { variables.lastExpressionResult }
        set { variables.lastExpressionResult = newValue }
    }
    var expressionHistory: [ExpressionResult] {
        get { variables.expressionHistory }
        set { variables.expressionHistory = newValue }
    }
    var expressionInput: String {
        get { variables.expressionInput }
        set { variables.expressionInput = newValue }
    }

    // MARK: - Backward-compatible accessors: Filters

    var severityFilter: Set<DebugEntrySeverity> {
        get { filters.severityFilter }
        set { filters.severityFilter = newValue }
    }
    var categoryFilter: String? {
        get { filters.categoryFilter }
        set { filters.categoryFilter = newValue }
    }
    var searchQuery: String {
        get { filters.searchQuery }
        set { filters.searchQuery = newValue }
    }

    var filteredLogs: [DebugLogEntry] {
        logs.filter { entry in
            guard severityFilter.contains(entry.severity) else { return false }
            if let cat = categoryFilter, entry.category != cat { return false }
            if !searchQuery.isEmpty {
                let q = searchQuery.lowercased()
                return entry.message.lowercased().contains(q)
                    || entry.source.lowercased().contains(q)
                    || (entry.detail?.lowercased().contains(q) ?? false)
            }
            return true
        }
    }

    var errorCount: Int { filteredLogs.filter { $0.severity == .error }.count }
    var warningCount: Int { filteredLogs.filter { $0.severity == .warning }.count }

    var activeHypotheses: [DebugHypothesis] {
        hypotheses.filter { $0.status == .proposed || $0.status == .investigating }
    }

    var pendingResolutionAfterClean: String?

    // MARK: - Backward-compatible accessors: Reports

    var debugFindings: [DebugFinding] {
        get { reports.debugFindings }
        set { reports.debugFindings = newValue }
    }
    var isAwaitingUserClarification: Bool {
        get { reports.isAwaitingUserClarification }
        set { reports.isAwaitingUserClarification = newValue }
    }
    var isAwaitingReproduceConfirmation: Bool {
        get { reports.isAwaitingReproduceConfirmation }
        set { reports.isAwaitingReproduceConfirmation = newValue }
    }
    var isAwaitingFixConfirmation: Bool {
        get { reports.isAwaitingFixConfirmation }
        set { reports.isAwaitingFixConfirmation = newValue }
    }
    var skippedQuestionsWarning: Bool {
        get { reports.skippedQuestionsWarning }
        set { reports.skippedQuestionsWarning = newValue }
    }
    var lastTraceAnalysis: String {
        get { reports.lastTraceAnalysis }
        set { reports.lastTraceAnalysis = newValue }
    }
    var lastSnapshotReport: String {
        get { reports.lastSnapshotReport }
        set { reports.lastSnapshotReport = newValue }
    }
    var lastTimelineReport: String {
        get { reports.lastTimelineReport }
        set { reports.lastTimelineReport = newValue }
    }
    var lastTestCheckReport: String {
        get { reports.lastTestCheckReport }
        set { reports.lastTestCheckReport = newValue }
    }
    var lastSessionExport: String {
        get { reports.lastSessionExport }
        set { reports.lastSessionExport = newValue }
    }
    var streamLogs: [DebugStreamLogEntry] {
        get { reports.streamLogs }
        set { reports.streamLogs = newValue }
    }
    var streamLogNewCount: Int {
        get { reports.streamLogNewCount }
        set { reports.streamLogNewCount = newValue }
    }
    var streamLogCancellable: AnyCancellable?

    var logFileMonitorSource: DispatchSourceFileSystemObject?
    var logFileMonitorHandle: FileHandle?

    static let maxFixLoopIterations = 5

    let nativeDebugConfiguration: DebugServiceConfiguration
    let nativeDebugService: DebugService
    let nativeDebugCoordinator: DebugExecutionCoordinator

    var isNativeDebugEnabled: Bool {
        nativeDebugConfiguration.nativeDebuggerEnabled
    }

    var nativeDebugDisabledReason: String? {
        nativeDebugConfiguration.disabledReason
    }

    init(
        nativeDebugConfiguration: DebugServiceConfiguration = .load(),
        nativeDebugService: DebugService? = nil
    ) {
        self.nativeDebugConfiguration = nativeDebugConfiguration
        let resolvedService = nativeDebugService
            ?? DebugService(configuration: nativeDebugConfiguration)
        self.nativeDebugService = resolvedService
        self.nativeDebugCoordinator = DebugExecutionCoordinator(service: resolvedService)
        setupStreamLogRelay()
    }
}
