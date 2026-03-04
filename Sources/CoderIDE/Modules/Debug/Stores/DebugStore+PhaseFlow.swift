import Foundation

extension DebugStore {
    // MARK: - Phase Management

    func startDebugSession(errorContext: String = "") {
        logs.removeAll()
        hypotheses.removeAll()
        breakpoints.removeAll()
        runtimeLogs.removeAll()
        instrumentationPoints.removeAll()
        debugMarkers.removeAll()
        nativeSession = .idle
        resetNativeInputs()
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
        resetLogFilters()
        addLog(severity: .info, source: "debug_session", message: "Debug session started", category: "system")
    }

    func setPhase(_ newPhase: DebugFlowPhase) {
        let currentPhase = phase
        if currentPhase == newPhase {
            if newPhase == .reproducing && currentRunId == nil {
                currentRunId = UUID().uuidString
            }
            return
        }

        if newPhase == .describing, currentPhase == .idle || currentPhase == .resolved {
            startDebugSession(errorContext: errorSummary)
            return
        }

        guard Self.isValidTransition(from: currentPhase, to: newPhase) else {
            addLog(
                severity: .warning,
                source: "debug_set_phase",
                message: "Ignored invalid phase transition \(currentPhase.rawValue) → \(newPhase.rawValue)",
                category: "system"
            )
            return
        }

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
        nativeSession = .idle
        resetNativeInputs()
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
        resetLogFilters()
    }

    private static func isValidTransition(from: DebugFlowPhase, to: DebugFlowPhase) -> Bool {
        if from == to { return true }
        switch from {
        case .idle:
            return to == .describing
        case .describing:
            return to == .reproducing || to == .fixing || to == .resolved
        case .reproducing:
            return to == .fixing || to == .instrumenting || to == .verifying || to == .resolved
        case .fixing:
            return to == .instrumenting || to == .verifying || to == .resolved
        case .instrumenting:
            return to == .fixing || to == .reproducing || to == .verifying || to == .resolved
        case .verifying:
            return to == .fixing || to == .instrumenting || to == .reproducing || to == .resolved
        case .resolved:
            return to == .idle || to == .describing
        }
    }
}
