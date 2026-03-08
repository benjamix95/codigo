import SwiftUI
import CoderEngine

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

    /// Native debugger session state (LLDB-backed)
    @Published var nativeSession: NativeDebugSessionState = .idle

    /// Path esplicito del target usato per avviare la sessione native.
    @Published var nativeTargetPathInput: String = ""

    /// Argomenti CLI del target (separati da virgola o newline).
    @Published var nativeArgumentsInput: String = ""

    /// Comma-separated watch expressions used by native debugger.
    @Published var nativeWatchExpressionsInput: String = ""

    /// Draft fields per aggiunta breakpoint dalla tab Native.
    @Published var nativeBreakpointFilePathInput: String = ""
    @Published var nativeBreakpointLineInput: String = ""
    @Published var nativeBreakpointConditionInput: String = ""

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

    // MARK: - Extended Debug State (Fase 1 — Debug Engine Hardening)

    /// Risultato della selezione frame corrente.
    @Published var selectedFrameResult: FrameSelectionResult?

    /// Variabili locali del frame corrente.
    @Published var localVariables: [NativeVariable] = []

    /// Variabili globali/statiche.
    @Published var globalVariables: [NativeVariable] = []

    /// Argomenti del frame corrente.
    @Published var argumentVariables: [NativeVariable] = []

    /// Ultimo risultato di valutazione espressione.
    @Published var lastExpressionResult: ExpressionResult?

    /// Storico delle espressioni valutate con successo.
    @Published var expressionHistory: [ExpressionResult] = []

    /// Input per la REPL di expression evaluation.
    @Published var expressionInput: String = ""

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

    var errorCount: Int { filteredLogs.filter { $0.severity == .error }.count }
    var warningCount: Int { filteredLogs.filter { $0.severity == .warning }.count }

    var activeHypotheses: [DebugHypothesis] {
        hypotheses.filter { $0.status == .proposed || $0.status == .investigating }
    }

    var pendingResolutionAfterClean: String?

    static let maxFixLoopIterations = 5

    let nativeDebugConfiguration: DebugServiceConfiguration
    let nativeDebugService: DebugService

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
        self.nativeDebugService = nativeDebugService
            ?? DebugService(configuration: nativeDebugConfiguration)
    }
}
