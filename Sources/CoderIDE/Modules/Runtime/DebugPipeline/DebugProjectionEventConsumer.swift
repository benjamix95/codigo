import Foundation
import CoderEngine

struct DebugProjectionUIEffects {
    var shouldEnableDebugMode = false
    var shouldRevealDebugPanel = false
}

enum DebugProjectionEventConsumer {
    static func handles(_ event: NormalizedEvent) -> Bool {
        switch event {
        case .debugPhaseUpdate, .debugUserRequest, .debugResolved, .debugLog,
             .debugHypothesize, .debugMark, .debugInstrument, .debugClean,
             .debugSession, .debugNativeSession, .debugQuery, .activateDebugMode:
            return true
        default:
            return false
        }
    }

    @MainActor
    static func apply(
        _ event: NormalizedEvent,
        to debugStore: DebugStore
    ) -> DebugProjectionUIEffects {
        var effects = DebugProjectionUIEffects()

        switch event {
        case .debugPhaseUpdate(let phase, let detail):
            effects.shouldEnableDebugMode = true
            effects.shouldRevealDebugPanel = true
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

        case .debugUserRequest(let kind, let prompt):
            effects.shouldEnableDebugMode = true
            effects.shouldRevealDebugPanel = true
            let normalizedKind = kind.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let normalizedPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !normalizedPrompt.isEmpty else { return effects }
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

        case .debugResolved(let summary):
            if debugStore.awaitingDebugClean {
                debugStore.addLog(
                    severity: .warning,
                    source: "debug_resolve",
                    message: "Ignoring debug_resolve while waiting for debug_clean",
                    category: "system"
                )
                return effects
            }
            let normalizedSummary = summary.trimmingCharacters(in: .whitespacesAndNewlines)
            debugStore.resolveSession(
                summary: normalizedSummary.isEmpty ? "Debug session resolved" : normalizedSummary
            )

        case .debugLog(let payload):
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

        case .debugHypothesize(let payload):
            switch payload.action {
            case "update":
                guard let hypothesisId = payload.hypothesisId,
                      let status = payload.status else { return effects }
                let updated = debugStore.updateHypothesis(
                    id: hypothesisId,
                    status: status,
                    evidence: payload.evidence
                )
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
                guard !title.isEmpty else { return effects }
                let description = payload.description ?? ""
                let _ = debugStore.addHypothesis(
                    id: payload.hypothesisId,
                    title: title,
                    description: description,
                    status: payload.status ?? .proposed,
                    evidence: payload.evidence
                )
            }

        case .debugMark(let payload):
            debugStore.addDebugMarker(DebugMarker(
                filePath: payload.filePath,
                lineNumber: payload.lineNumber,
                markerComment: payload.comment,
                originalContent: payload.originalContent
            ))
            if debugStore.phase == .fixing {
                debugStore.setPhase(.instrumenting)
            }

        case .debugInstrument(let payload):
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

        case .debugClean(let payload):
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
                return effects
            }

            let normalizedStatus = (payload.status ?? "completed").lowercased()
            let cleanSucceeded = !(normalizedStatus == "failed" || normalizedStatus == "error")

            if debugStore.awaitingDebugClean {
                debugStore.applyDebugCleanResult(success: cleanSucceeded, detail: payload.detail)
                return effects
            }

            if cleanSucceeded {
                _ = debugStore.cleanAllDebugMarkers()
                _ = debugStore.cleanAllInstrumentation()
                if let detail = payload.detail, !detail.isEmpty {
                    debugStore.addLog(
                        severity: .info,
                        source: "debug_clean",
                        message: detail,
                        category: "system"
                    )
                }
            }

        case .debugSession(let payload):
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

        case .debugNativeSession(let payload):
            effects.shouldEnableDebugMode = true
            effects.shouldRevealDebugPanel = true
            debugStore.applyNativePipelineProjection(
                state: payload.state,
                breakpoints: payload.breakpoints,
                arguments: payload.arguments,
                watchExpressions: payload.watchExpressions
            )

        case .debugQuery(let payload):
            let detail = payload.detail ?? "Debug query \(payload.format)"
            debugStore.addLog(
                severity: .info,
                source: "debug_query",
                message: detail,
                detail: payload.output,
                category: "debug"
            )

        case .activateDebugMode(let reason):
            effects.shouldEnableDebugMode = true
            effects.shouldRevealDebugPanel = true
            let normalizedReason = reason?.trimmingCharacters(in: .whitespacesAndNewlines)
            if shouldStartDebugSessionOnAutoActivate(currentPhase: debugStore.phase) {
                debugStore.startDebugSession(errorContext: normalizedReason ?? "")
            } else if let normalizedReason, !normalizedReason.isEmpty, debugStore.errorSummary.isEmpty {
                debugStore.errorSummary = normalizedReason
            }

        default:
            break
        }

        return effects
    }
}
