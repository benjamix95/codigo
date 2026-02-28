import SwiftUI
import CoderEngine

// MARK: - Debug Flow Phase (linear: Describe → Reproduce → Fix → Verify → Resolve)

enum DebugFlowPhase: String, Equatable, CaseIterable {
    case idle
    // Phase 1: DESCRIBE THE BUG — Agent reads logs, errors, stack traces, gathers context
    case describing
    // Phase 2: REPRODUCE THE BUG — Agent adds instrumentation, user reproduces
    case reproducing
    // Phase 3: FIX — Agent hypothesizes, instruments, observes, fixes
    case fixing
    // Sub-phase of fixing: agent is actively inserting instrumentation (logging, asserts)
    case instrumenting
    // Phase 4: VERIFY THE FIX — Agent runs tests, checks for regressions
    case verifying
    // Terminal: Bug resolved
    case resolved

    /// Main linear phases for the progress bar.
    static var mainPhases: [DebugFlowPhase] { [.describing, .reproducing, .fixing, .verifying, .resolved] }

    /// Human-readable label for each phase
    var label: String {
        switch self {
        case .idle:          return ""
        case .describing:    return "Describe the Bug"
        case .reproducing:   return "Reproduce"
        case .fixing:        return "Fix"
        case .instrumenting: return "Instrumenting"
        case .verifying:     return "Verify the Fix"
        case .resolved:      return "Resolved"
        }
    }

    /// The main phase this sub-phase belongs to (for progress bar highlighting)
    var mainPhase: DebugFlowPhase {
        switch self {
        case .instrumenting: return .fixing
        default:             return self
        }
    }

    /// Phase index for progress bar (0-based among mainPhases)
    var phaseIndex: Int {
        DebugFlowPhase.mainPhases.firstIndex(of: mainPhase) ?? 0
    }

    /// Is this phase active (not idle, not resolved)?
    var isActive: Bool {
        self != .idle && self != .resolved
    }
}

/// Tracks a debug marker inserted by the agent into a source file
struct DebugMarker: Identifiable, Codable, Equatable {
    let id: UUID
    let filePath: String
    let lineNumber: Int          // line where marker was inserted
    let markerComment: String    // e.g. "// 🐛 DEBUG: ..."
    let originalContent: String? // original line content for clean revert
    let insertedAt: Date

    init(filePath: String, lineNumber: Int, markerComment: String, originalContent: String? = nil) {
        self.id = UUID()
        self.filePath = filePath
        self.lineNumber = lineNumber
        self.markerComment = markerComment
        self.originalContent = originalContent
        self.insertedAt = Date()
    }
}

// MARK: - Debug Entry Types

enum DebugEntrySeverity: String, Codable, CaseIterable {
    case error, warning, info, verbose, trace
    var icon: String {
        switch self {
        case .error:   return "xmark.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .info:    return "info.circle.fill"
        case .verbose: return "text.alignleft"
        case .trace:   return "waveform"
        }
    }
    var color: Color {
        switch self {
        case .error:   return DesignSystem.Colors.error
        case .warning: return DesignSystem.Colors.warning
        case .info:    return DesignSystem.Colors.info
        case .verbose: return .secondary
        case .trace:   return .secondary.opacity(0.6)
        }
    }
}

struct DebugLogEntry: Identifiable, Codable {
    let id: UUID
    let timestamp: Date
    let severity: DebugEntrySeverity
    let source: String        // file:line or module name
    let message: String
    let detail: String?       // stack trace, extra context
    let category: String?     // "compiler", "runtime", "test", "network", "custom"

    init(severity: DebugEntrySeverity, source: String, message: String, detail: String? = nil, category: String? = nil) {
        self.id = UUID()
        self.timestamp = Date()
        self.severity = severity
        self.source = source
        self.message = message
        self.detail = detail
        self.category = category
    }
}

struct DebugHypothesis: Identifiable, Codable {
    let id: UUID
    let title: String
    let description: String
    var status: HypothesisStatus
    var evidence: [String]      // supporting evidence collected
    let createdAt: Date

    enum HypothesisStatus: String, Codable {
        case proposed, investigating, confirmed, rejected
        var icon: String {
            switch self {
            case .proposed:      return "lightbulb.fill"
            case .investigating: return "magnifyingglass"
            case .confirmed:     return "checkmark.circle.fill"
            case .rejected:      return "xmark.circle"
            }
        }
        var color: Color {
            switch self {
            case .proposed:      return DesignSystem.Colors.warning
            case .investigating: return DesignSystem.Colors.info
            case .confirmed:     return DesignSystem.Colors.success
            case .rejected:      return .secondary
            }
        }
    }

    init(
        id: UUID = UUID(),
        title: String,
        description: String,
        status: HypothesisStatus = .proposed,
        evidence: [String] = [],
        createdAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.description = description
        self.status = status
        self.evidence = evidence
        self.createdAt = createdAt
    }
}

/// Runtime log entry collected from .codigo/debug.log (Cursor-style JSONL).
/// Captures variable states, execution paths, timing — written by agent instrumentation.
struct RuntimeLogEntry: Identifiable, Codable {
    let id: String
    let timestamp: Date
    let location: String          // file:line where the log was emitted
    let message: String
    let data: [String: String]    // arbitrary key-value data (variable values, timing, etc.)
    let sessionId: String?
    let runId: String?            // groups logs from a single reproduce run
    let hypothesisId: String?     // links to the hypothesis this log supports

    init(
        location: String,
        message: String,
        data: [String: String] = [:],
        sessionId: String? = nil,
        runId: String? = nil,
        hypothesisId: String? = nil
    ) {
        self.id = UUID().uuidString
        self.timestamp = Date()
        self.location = location
        self.message = message
        self.data = data
        self.sessionId = sessionId
        self.runId = runId
        self.hypothesisId = hypothesisId
    }
}

/// Tracks an instrumentation point the agent inserted (logging, assert, timing).
/// Richer than DebugMarker — includes hypothesisId and type.
struct InstrumentationPoint: Identifiable, Codable, Equatable {
    let id: UUID
    let filePath: String
    let lineNumber: Int
    let type: InstrumentationType
    let code: String               // the instrumentation code inserted
    let hypothesisId: String?      // which hypothesis this instruments
    let insertedAt: Date

    enum InstrumentationType: String, Codable, Equatable {
        case logging      // print/NSLog/os_log
        case assertion     // assert/precondition
        case timing        // timing measurement
        case variable      // variable state capture
    }

    init(filePath: String, lineNumber: Int, type: InstrumentationType, code: String, hypothesisId: String? = nil) {
        self.id = UUID()
        self.filePath = filePath
        self.lineNumber = lineNumber
        self.type = type
        self.code = code
        self.hypothesisId = hypothesisId
        self.insertedAt = Date()
    }
}

struct DebugBreakpoint: Identifiable, Codable {
    let id: UUID
    let filePath: String
    let line: Int
    let condition: String?
    var isActive: Bool

    init(filePath: String, line: Int, condition: String? = nil) {
        self.id = UUID()
        self.filePath = filePath
        self.line = line
        self.condition = condition
        self.isActive = true
    }
}

// MARK: - Debug Store

@MainActor
final class DebugStore: ObservableObject {
    @Published var phase: DebugFlowPhase = .idle
    @Published var logs: [DebugLogEntry] = []
    @Published var hypotheses: [DebugHypothesis] = []
    @Published var breakpoints: [DebugBreakpoint] = []
    @Published var streamingContent: String = ""
    @Published var errorSummary: String = ""
    @Published var clarificationQuestions: String = ""
    @Published var resolutionSummary: String = ""

    /// Debug markers inserted in files by the agent (tracked for cleanup)
    @Published var debugMarkers: [DebugMarker] = []

    /// Cursor-style runtime logs collected from .codigo/debug.log
    @Published var runtimeLogs: [RuntimeLogEntry] = []

    /// Instrumentation points the agent has inserted (richer than markers)
    @Published var instrumentationPoints: [InstrumentationPoint] = []

    /// Current reproduce run ID (groups runtime logs from a single reproduce)
    @Published var currentRunId: String?

    /// Mermaid diagram code for the debug flow (static or agent-generated)
    @Published var debugFlowDiagram: String = ""

    /// How many times the fix loop has iterated (Hypothesize→Instrument→Observe→Verify→Fix)
    @Published var fixLoopIteration: Int = 0

    /// Whether the user confirmed they reproduced the bug (after reproduce phase)
    @Published var userConfirmedReproduce = false

    /// While true, the panel is waiting for debug_clean completion before resolving.
    @Published var awaitingDebugClean = false

    /// Filters for log panel
    @Published var severityFilter: Set<DebugEntrySeverity> = Set(DebugEntrySeverity.allCases)
    @Published var categoryFilter: String? = nil
    @Published var searchQuery: String = ""

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

    var errorCount: Int { logs.filter { $0.severity == .error }.count }
    var warningCount: Int { logs.filter { $0.severity == .warning }.count }

    var activeHypotheses: [DebugHypothesis] {
        hypotheses.filter { $0.status == .proposed || $0.status == .investigating }
    }

    private var pendingResolutionAfterClean: String?

    // MARK: - Log Management

    func addLog(_ entry: DebugLogEntry) {
        logs.append(entry)
        // Keep last 2000 entries
        if logs.count > 2000 {
            logs.removeFirst(logs.count - 2000)
        }
    }

    func addLog(severity: DebugEntrySeverity, source: String, message: String, detail: String? = nil, category: String? = nil) {
        addLog(DebugLogEntry(severity: severity, source: source, message: message, detail: detail, category: category))
    }

    func clearLogs() {
        logs.removeAll()
    }

    // MARK: - Hypothesis Management

    @discardableResult
    func addHypothesis(
        id: UUID? = nil,
        title: String,
        description: String,
        status: DebugHypothesis.HypothesisStatus = .proposed,
        evidence: String? = nil
    ) -> UUID {
        let resolvedId = id ?? UUID()
        if let idx = hypotheses.firstIndex(where: { $0.id == resolvedId }) {
            hypotheses[idx].status = status
            if !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                hypotheses[idx] = DebugHypothesis(
                    id: resolvedId,
                    title: title,
                    description: description,
                    status: status,
                    evidence: hypotheses[idx].evidence,
                    createdAt: hypotheses[idx].createdAt
                )
            }
            if let evidence, !evidence.isEmpty {
                hypotheses[idx].evidence.append(evidence)
            }
            return resolvedId
        }

        var h = DebugHypothesis(id: resolvedId, title: title, description: description)
        h.status = status
        if let evidence, !evidence.isEmpty {
            h.evidence.append(evidence)
        }
        hypotheses.append(h)
        return h.id
    }

    @discardableResult
    func updateHypothesis(id: UUID, status: DebugHypothesis.HypothesisStatus, evidence: String? = nil) -> Bool {
        guard let idx = hypotheses.firstIndex(where: { $0.id == id }) else { return false }
        hypotheses[idx].status = status
        if let ev = evidence, !ev.isEmpty {
            hypotheses[idx].evidence.append(ev)
        }
        return true
    }

    // MARK: - Breakpoint Management

    func addBreakpoint(filePath: String, line: Int, condition: String? = nil) {
        let bp = DebugBreakpoint(filePath: filePath, line: line, condition: condition)
        breakpoints.append(bp)
    }

    func removeBreakpoint(id: UUID) {
        breakpoints.removeAll { $0.id == id }
    }

    func toggleBreakpoint(id: UUID) {
        guard let idx = breakpoints.firstIndex(where: { $0.id == id }) else { return }
        breakpoints[idx].isActive.toggle()
    }

    // MARK: - Runtime Log Management

    func addRuntimeLog(_ entry: RuntimeLogEntry) {
        runtimeLogs.append(entry)
        if runtimeLogs.count > 2000 {
            runtimeLogs.removeFirst(runtimeLogs.count - 2000)
        }
    }

    func addRuntimeLog(location: String, message: String, data: [String: String] = [:], hypothesisId: String? = nil) {
        addRuntimeLog(RuntimeLogEntry(
            location: location,
            message: message,
            data: data,
            runId: currentRunId,
            hypothesisId: hypothesisId
        ))
    }

    /// Runtime logs for the current run (filtered by runId)
    var currentRunLogs: [RuntimeLogEntry] {
        guard let runId = currentRunId else { return runtimeLogs }
        return runtimeLogs.filter { $0.runId == runId }
    }

    /// Runtime logs linked to a specific hypothesis
    func runtimeLogs(for hypothesisId: String) -> [RuntimeLogEntry] {
        runtimeLogs.filter { $0.hypothesisId == hypothesisId }
    }

    func clearRuntimeLogs() {
        runtimeLogs.removeAll()
    }

    // MARK: - Instrumentation Management

    func addInstrumentation(_ point: InstrumentationPoint) {
        instrumentationPoints.append(point)
    }

    func addInstrumentation(filePath: String, lineNumber: Int, type: InstrumentationPoint.InstrumentationType, code: String, hypothesisId: String? = nil) {
        addInstrumentation(InstrumentationPoint(
            filePath: filePath,
            lineNumber: lineNumber,
            type: type,
            code: code,
            hypothesisId: hypothesisId
        ))
    }

    func removeInstrumentation(id: UUID) {
        instrumentationPoints.removeAll { $0.id == id }
    }

    /// Number of files with instrumentation
    var instrumentedFileCount: Int {
        Set(instrumentationPoints.map(\.filePath)).count
    }

    /// Remove all instrumentation (called by "Mark Fixed")
    func cleanAllInstrumentation() -> [InstrumentationPoint] {
        let points = instrumentationPoints
        instrumentationPoints.removeAll()
        return points
    }

    // MARK: - Phase Management

    func startDebugSession(errorContext: String = "") {
        logs.removeAll()
        hypotheses.removeAll()
        breakpoints.removeAll()
        runtimeLogs.removeAll()
        instrumentationPoints.removeAll()
        debugMarkers.removeAll()
        phase = .describing
        errorSummary = errorContext
        streamingContent = ""
        clarificationQuestions = ""
        resolutionSummary = ""
        userConfirmedReproduce = false
        awaitingDebugClean = false
        pendingResolutionAfterClean = nil
        currentRunId = nil
        fixLoopIteration = 0
        debugFlowDiagram = Self.defaultDebugFlowDiagram
        addLog(severity: .info, source: "debug_session", message: "Debug session started", category: "system")
    }

    func setPhase(_ newPhase: DebugFlowPhase) {
        phase = newPhase
        if newPhase == .reproducing && currentRunId == nil {
            currentRunId = UUID().uuidString
        }
    }

    /// Start a new reproduce run (generates new runId, clears old runtime logs for this run)
    func startNewRun() {
        currentRunId = UUID().uuidString
        addLog(severity: .info, source: "debug_session", message: "New reproduce run started: \(currentRunId ?? "?")", category: "system")
    }

    static let maxFixLoopIterations = 5

    /// Loop back from verify to instrument (verify failed → more instrumentation needed)
    func loopBackToInstrument(reason: String) {
        fixLoopIteration += 1
        if fixLoopIteration > Self.maxFixLoopIterations {
            phase = .verifying
            addLog(severity: .error, source: "debug_session",
                   message: "Fix loop limit reached (\(Self.maxFixLoopIterations) iterations). Manual intervention required.",
                   detail: reason, category: "system")
            return
        }
        phase = .instrumenting
        addLog(severity: .warning, source: "debug_session", message: "Verify failed (iteration \(fixLoopIteration)): \(reason). Looping back to instrument.", category: "system")
    }

    func resolveSession(summary: String) {
        resolutionSummary = summary
        awaitingDebugClean = false
        pendingResolutionAfterClean = nil
        phase = .resolved
        addLog(severity: .info, source: "debug_session", message: "Debug session resolved: \(summary)", category: "system")
    }

    func resetSession() {
        phase = .idle
        logs.removeAll()
        hypotheses.removeAll()
        breakpoints.removeAll()
        runtimeLogs.removeAll()
        instrumentationPoints.removeAll()
        debugMarkers.removeAll()
        streamingContent = ""
        errorSummary = ""
        clarificationQuestions = ""
        resolutionSummary = ""
        userConfirmedReproduce = false
        awaitingDebugClean = false
        pendingResolutionAfterClean = nil
        currentRunId = nil
        fixLoopIteration = 0
        debugFlowDiagram = ""
    }

    // MARK: - Debug Markers

    func addDebugMarker(_ marker: DebugMarker) {
        debugMarkers.append(marker)
    }

    func removeDebugMarker(id: UUID) {
        debugMarkers.removeAll { $0.id == id }
    }

    /// Number of files with debug markers
    var markedFileCount: Int {
        Set(debugMarkers.map(\.filePath)).count
    }

    /// Remove all debug markers from tracked files (revert lines)
    func cleanAllDebugMarkers() -> [(filePath: String, markers: [DebugMarker])] {
        let grouped = Dictionary(grouping: debugMarkers, by: \.filePath)
        let result = grouped.map { ($0.key, $0.value) }
        debugMarkers.removeAll()
        return result
    }

    // MARK: - Proceed / Fixed Flow

    func confirmReproduced() {
        userConfirmedReproduce = true
        phase = .fixing
        addLog(severity: .info, source: "debug_session", message: "Bug reproduced — proceeding to fix phase", category: "system")
    }

    /// Begin Mark Fixed in verifying phase. Returns the list of files expected to be cleaned.
    func beginMarkFixed(summary: String) -> [String] {
        let normalizedSummary = summary.trimmingCharacters(in: .whitespacesAndNewlines)
        pendingResolutionAfterClean = normalizedSummary.isEmpty ? "Debug session resolved" : normalizedSummary
        awaitingDebugClean = true
        phase = .verifying

        let files = Set(debugMarkers.map(\.filePath) + instrumentationPoints.map(\.filePath)).sorted()
        addLog(
            severity: .info,
            source: "debug_session",
            message: "Mark Fixed requested — waiting for debug_clean",
            detail: files.isEmpty ? nil : files.joined(separator: ", "),
            category: "system"
        )
        return files
    }

    /// Apply debug_clean result; resolve only when cleanup succeeds.
    func applyDebugCleanResult(success: Bool, detail: String?) {
        guard awaitingDebugClean else { return }

        if success {
            _ = cleanAllDebugMarkers()
            _ = cleanAllInstrumentation()
            let summary = pendingResolutionAfterClean ?? resolutionSummary
            resolveSession(summary: summary.isEmpty ? "Debug session resolved" : summary)
            if let detail, !detail.isEmpty {
                addLog(severity: .info, source: "debug_clean", message: detail, category: "system")
            }
        } else {
            awaitingDebugClean = false
            pendingResolutionAfterClean = nil
            phase = .verifying
            addLog(
                severity: .warning,
                source: "debug_clean",
                message: "debug_clean failed; session remains in verifying",
                detail: detail,
                category: "system"
            )
        }
    }

    /// Backward-compatible helper (legacy flow). Prefer beginMarkFixed + applyDebugCleanResult.
    func markFixed(summary: String) -> (markers: [(filePath: String, markers: [DebugMarker])], instrumentation: [InstrumentationPoint]) {
        let markers = cleanAllDebugMarkers()
        let instrumentation = cleanAllInstrumentation()
        resolveSession(summary: summary)
        return (markers, instrumentation)
    }

    // MARK: - Default Debug Flow Diagram

    static let defaultDebugFlowDiagram = """
    flowchart LR
        A[Describe] --> B[Reproduce]
        B --> C[Fix]
        C --> D[Verify]
        D --> E[Resolve]
        C -.-> C1[Hypothesize]
        C1 -.-> C2[Instrument]
        C2 -.-> C3[Observe]
    """
}
