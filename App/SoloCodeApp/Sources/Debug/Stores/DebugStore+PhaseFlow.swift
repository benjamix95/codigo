import Foundation

extension DebugStore {
    // MARK: - Phase Management

    func startDebugSession(errorContext: String = "") {
        cancelDebugSessionWatchdogTasks()
        logs.removeAll()
        hypotheses.removeAll()
        breakpoints.removeAll()
        runtimeLogs.removeAll()
        instrumentationPoints.removeAll()
        debugMarkers.removeAll()
        clearStreamLogs()
        nativeSession = .idle
        resetNativeInputs()
        phase = .describing
        errorSummary = errorContext
        streamingContent = ""
        clarificationQuestions = ""
        resolutionSummary = ""
        userConfirmedReproduce = false
        awaitingDebugClean = false
        isAwaitingUserClarification = false
        isAwaitingReproduceConfirmation = false
        isAwaitingFixConfirmation = false
        skippedQuestionsWarning = false
        debugFindings.removeAll()
        pendingResolutionAfterClean = nil
        currentRunId = nil
        lastTraceAnalysis = ""
        lastSnapshotReport = ""
        lastTimelineReport = ""
        lastTestCheckReport = ""
        lastSessionExport = ""
        fixLoopIteration = 0
        debugFlowDiagram = Self.defaultDebugFlowDiagram
        resetLogFilters()
        addLog(severity: .info, source: "debug_session", message: "Debug session started", category: "system")

        // Auto-load runtime logs from disk and start monitoring
        loadRuntimeLogsFromDisk(path: activeDebugLogPath)
        startLogFileMonitor(path: activeDebugLogPath)
    }

    @discardableResult
    func setPhase(_ newPhase: DebugFlowPhase) -> Bool {
        let currentPhase = phase
        if currentPhase == newPhase {
            if newPhase == .reproducing && currentRunId == nil {
                currentRunId = UUID().uuidString
            }
            rescheduleDebugIdleWarningIfNeeded()
            return true
        }

        if newPhase == .describing, currentPhase == .idle || currentPhase == .resolved {
            startDebugSession(errorContext: errorSummary)
            return true
        }

        guard Self.isValidTransition(from: currentPhase, to: newPhase) else {
            addLog(
                severity: .warning,
                source: "debug_set_phase",
                message: "Ignored invalid phase transition \(currentPhase.rawValue) → \(newPhase.rawValue)",
                category: "system"
            )
            return false
        }

        if newPhase == .reproducing {
            clearStreamLogs()
        } else if newPhase == .verifying, currentPhase == .fixing {
            clearStreamLogs()
        }
        phase = newPhase
        if newPhase == .reproducing && currentRunId == nil {
            currentRunId = UUID().uuidString
        }
        return true
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
        cancelDebugSessionWatchdogTasks()
        resolutionSummary = summary
        awaitingDebugClean = false
        pendingResolutionAfterClean = nil
        phase = .resolved
        addLog(severity: .info, source: "debug_session", message: "Debug session resolved: \(summary)", category: "system")
    }

    func resetSession() {
        cancelDebugSessionWatchdogTasks()
        stopLogFileMonitor()
        phase = .idle
        logs.removeAll()
        hypotheses.removeAll()
        breakpoints.removeAll()
        runtimeLogs.removeAll()
        instrumentationPoints.removeAll()
        debugMarkers.removeAll()
        clearStreamLogs()
        nativeSession = .idle
        resetNativeInputs()
        streamingContent = ""
        errorSummary = ""
        clarificationQuestions = ""
        resolutionSummary = ""
        userConfirmedReproduce = false
        awaitingDebugClean = false
        isAwaitingUserClarification = false
        isAwaitingReproduceConfirmation = false
        isAwaitingFixConfirmation = false
        skippedQuestionsWarning = false
        debugFindings.removeAll()
        pendingResolutionAfterClean = nil
        currentRunId = nil
        activeDebugSessionId = nil
        debugWorkspacePath = nil
        lastTraceAnalysis = ""
        lastSnapshotReport = ""
        lastTimelineReport = ""
        lastTestCheckReport = ""
        lastSessionExport = ""
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
