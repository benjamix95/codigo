import CoderEngine

extension ChatPanelView {
    @MainActor
    internal func handleDebugPhaseUpdate(phase: DebugFlowPhase, detail: String?) {
        debugToggleEnabled = true
        showDebugPanel = true
        if coderMode != .debug {
            selectMode(.debug)
        }
        let previousPhase = debugStore.phase
        debugStore.setPhase(phase)
        let shouldClearQuestions = phase == .fixing
            || phase == .instrumenting
            || phase == .verifying
            || phase == .resolved
        if shouldClearQuestions, previousPhase != phase, !debugStore.clarificationQuestions.isEmpty {
            debugStore.clarificationQuestions = ""
        }
        if let detail, !detail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            debugStore.addLog(
                severity: .info,
                source: "debug_set_phase",
                message: "Phase → \(phase.label)",
                detail: detail,
                category: "system"
            )
        }
    }

    @MainActor
    internal func handleDebugUserRequest(kind: String, prompt: String) {
        let normalizedKind = kind.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let normalizedPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedPrompt.isEmpty else { return }

        debugToggleEnabled = true
        showDebugPanel = true
        if coderMode != .debug {
            selectMode(.debug)
        }

        switch normalizedKind {
        case "reproduce":
            if debugStore.phase == .idle || debugStore.phase == .describing {
                debugStore.setPhase(.reproducing)
            }
            debugStore.clarificationQuestions = normalizedPrompt
        default:
            if debugStore.phase == .idle {
                debugStore.setPhase(.describing)
            }
            debugStore.clarificationQuestions = normalizedPrompt
        }
    }

    @MainActor
    internal func handleDebugResolved(summary: String) {
        if debugStore.awaitingDebugClean {
            debugStore.addLog(
                severity: .warning,
                source: "debug_resolve",
                message: "Ignoring debug_resolve while waiting for debug_clean",
                category: "system"
            )
            return
        }
        let normalizedSummary = summary.trimmingCharacters(in: .whitespacesAndNewlines)
        debugStore.resolveSession(
            summary: normalizedSummary.isEmpty ? "Debug session resolved" : normalizedSummary
        )
    }

    @MainActor
    internal func handleDebugLogPayload(_ payload: DebugLogToolPayload) {
        debugStore.addLog(
            severity: payload.severity,
            source: payload.source,
            message: payload.message,
            detail: payload.detail,
            category: payload.category
        )

        let isRuntimeLike = payload.category == "runtime"
            || payload.category == "instrumentation"
            || !payload.data.isEmpty
            || !(payload.hypothesisId ?? "").isEmpty
        if isRuntimeLike {
            debugStore.addRuntimeLog(
                location: payload.source,
                message: payload.message,
                data: payload.data,
                hypothesisId: payload.hypothesisId,
                runId: payload.runId
            )
        }
    }

    @MainActor
    internal func handleDebugHypothesizePayload(_ payload: DebugHypothesizeToolPayload) {
        switch payload.action {
        case "update":
            guard let hypothesisId = payload.hypothesisId,
                  let status = payload.status
            else {
                return
            }
            let updated = debugStore.updateHypothesis(id: hypothesisId, status: status, evidence: payload.evidence)
            if !updated {
                debugStore.addLog(
                    severity: .warning,
                    source: "debug_hypothesize",
                    message: "Hypothesis update ignored: unknown id",
                    detail: payload.hypothesisIdRaw,
                    category: "debug"
                )
            }
        default:
            let title = (payload.title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty else { return }
            let description = payload.description ?? ""
            let _ = debugStore.addHypothesis(
                id: payload.hypothesisId,
                title: title,
                description: description,
                status: payload.status ?? .proposed,
                evidence: payload.evidence
            )
        }
    }

    @MainActor
    internal func handleDebugMarkPayload(_ payload: DebugMarkToolPayload) {
        debugStore.addDebugMarker(DebugMarker(
            filePath: payload.filePath,
            lineNumber: payload.lineNumber,
            markerComment: payload.comment,
            originalContent: payload.originalContent
        ))
        if debugStore.phase == .fixing {
            debugStore.setPhase(.instrumenting)
        }
    }

    @MainActor
    internal func handleDebugInstrumentPayload(_ payload: DebugInstrumentToolPayload) {
        let instrumentationType: InstrumentationPoint.InstrumentationType
        switch payload.type {
        case "assert":
            instrumentationType = .assertion
        case "timing":
            instrumentationType = .timing
        case "variable":
            instrumentationType = .variable
        default:
            instrumentationType = .logging
        }
        let displayLabel = payload.label?.isEmpty == false
            ? (payload.label ?? "")
            : (payload.expression ?? "instrumentation")
        debugStore.addInstrumentation(
            filePath: payload.filePath,
            lineNumber: payload.lineNumber,
            type: instrumentationType,
            code: displayLabel,
            hypothesisId: payload.hypothesisId
        )
        if debugStore.phase == .fixing {
            debugStore.setPhase(.instrumenting)
        }
    }

    @MainActor
    internal func handleDebugCleanPayload(_ payload: DebugCleanToolPayload) {
        if payload.dryRun {
            if let detail = payload.detail, !detail.isEmpty {
                debugStore.addLog(
                    severity: .info,
                    source: "debug_clean",
                    message: "Dry-run preview received (cleanup not applied)",
                    detail: detail,
                    category: "system"
                )
            }
            return
        }

        let normalizedStatus = (payload.status ?? "completed").lowercased()
        let cleanSucceeded = !(normalizedStatus == "failed" || normalizedStatus == "error")

        if debugStore.awaitingDebugClean {
            debugStore.applyDebugCleanResult(success: cleanSucceeded, detail: payload.detail)
            return
        }

        if cleanSucceeded {
            _ = debugStore.cleanAllDebugMarkers()
            _ = debugStore.cleanAllInstrumentation()
            if let detail = payload.detail, !detail.isEmpty {
                debugStore.addLog(severity: .info, source: "debug_clean", message: detail, category: "system")
            }
        }
    }

    @MainActor
    internal func handleDebugSessionPayload(_ payload: DebugSessionToolPayload) {
        switch payload.action {
        case "start":
            if shouldStartDebugSessionOnAutoActivate(currentPhase: debugStore.phase) {
                debugStore.startDebugSession(errorContext: payload.detail ?? "")
            }
        case "clear":
            debugStore.resetSession()
        case "end", "stop":
            if debugStore.phase != .resolved {
                debugStore.setPhase(.verifying)
            }
        default:
            break
        }
    }

    @MainActor
    internal func handleDebugQueryPayload(_ payload: DebugQueryToolPayload) {
        let detail = payload.detail ?? "Debug query \(payload.format)"
        debugStore.addLog(
            severity: .info,
            source: "debug_query",
            message: detail,
            detail: payload.output,
            category: "debug"
        )
    }
}
