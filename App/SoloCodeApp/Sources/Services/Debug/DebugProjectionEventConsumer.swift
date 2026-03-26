import Foundation
import CoderEngine

struct DebugProjectionUIEffects {
    var shouldEnableDebugMode = false
    var shouldRevealDebugPanel = false
}

@MainActor
final class DebugProjectionStoreBinding {
    weak var store: DebugStore?
    let applyEffects: @MainActor (DebugProjectionUIEffects) -> Void

    init(
        store: DebugStore,
        applyEffects: @escaping @MainActor (DebugProjectionUIEffects) -> Void = { _ in }
    ) {
        self.store = store
        self.applyEffects = applyEffects
    }
}

enum DebugProjectionEventConsumer {
    static func handles(_ event: NormalizedEvent) -> Bool {
        switch event {
        case .debugPhaseUpdate, .debugUserRequest, .debugResolved, .debugLog,
             .debugHypothesize, .debugMark, .debugInstrument, .debugClean,
             .debugSession, .debugNativeSession, .debugQuery,
             .debugTraceAnalyze, .debugSnapshot, .debugTimeline, .debugTestCheck,
             .activateDebugMode:
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
            if debugStore.phase == .idle,
               phase != .describing,
               phase != .resolved {
                debugStore.startDebugSession(
                    errorContext: detail?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                )
                switch phase {
                case .instrumenting, .verifying:
                    debugStore.setPhase(.fixing)
                default:
                    break
                }
            }
            let previousPhase = debugStore.phase
            // Warn if agent jumped to fixing without asking questions or proposing hypotheses
            if phase == .fixing
                && debugStore.clarificationQuestions.isEmpty
                && debugStore.hypotheses.isEmpty
                && previousPhase != .fixing {
                debugStore.skippedQuestionsWarning = true
                debugStore.addLog(
                    severity: .warning,
                    source: "debug_pipeline",
                    message: "Agent advanced to fixing without asking questions or proposing hypotheses",
                    category: "system"
                )
            }
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
                debugStore.isAwaitingReproduceConfirmation = true
            case "fix_confirmation":
                debugStore.clarificationQuestions = normalizedPrompt
                debugStore.isAwaitingFixConfirmation = true
            default:
                if debugStore.phase == .idle {
                    debugStore.setPhase(.describing)
                }
                debugStore.clarificationQuestions = normalizedPrompt
                debugStore.isAwaitingUserClarification = true
            }

        case .debugResolved(let summary):
            if debugStore.awaitingDebugClean {
                let normalizedSummary = summary.trimmingCharacters(in: .whitespacesAndNewlines)
                let merged = normalizedSummary.isEmpty ? "Debug session resolved" : normalizedSummary
                debugStore.pendingResolutionAfterClean = merged
                debugStore.addLog(
                    severity: .info,
                    source: "debug_resolve",
                    message: "Resolve received during cleanup — summary will apply after debug_clean succeeds",
                    detail: merged,
                    category: "system"
                )
                return effects
            }
            let normalizedSummary = summary.trimmingCharacters(in: .whitespacesAndNewlines)
            let resolvedSummary = normalizedSummary.isEmpty ? "Debug session resolved" : normalizedSummary
            debugStore.addResolutionSummaryFinding(summary: resolvedSummary)
            debugStore.resolveSession(summary: resolvedSummary)

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
                    evidence: payload.evidence,
                    confidence: payload.confidence,
                    rootCauseType: payload.rootCauseType,
                    relatedFiles: payload.relatedFiles,
                    relatedTests: payload.relatedTests
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
                // Generate finding when hypothesis is confirmed
                if status == .confirmed, let hypothesis = debugStore.hypotheses.first(where: { $0.id == hypothesisId }) {
                    debugStore.addFinding(fromHypothesis: hypothesis)
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
                    evidence: payload.evidence,
                    confidence: payload.confidence ?? 50,
                    rootCauseType: payload.rootCauseType ?? "",
                    relatedFiles: payload.relatedFiles,
                    relatedTests: payload.relatedTests
                )
            }

        case .debugMark(let payload):
            let marker = DebugMarker(
                filePath: payload.filePath,
                lineNumber: payload.lineNumber,
                markerComment: payload.comment,
                originalContent: payload.originalContent
            )
            debugStore.addDebugMarker(marker)
            debugStore.addFinding(fromMarker: marker)
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
                debugStore.configureLogPersistence(
                    workspacePath: payload.workspacePath,
                    sessionId: payload.sessionId
                )
                if shouldStartDebugSessionOnAutoActivate(currentPhase: debugStore.phase) {
                    debugStore.startDebugSession(errorContext: payload.detail ?? "")
                }
                if let sessionId = payload.sessionId, !sessionId.isEmpty {
                    debugStore.activeDebugSessionId = sessionId
                }
            case "clear":
                debugStore.resetSession()
            case "end", "stop":
                if debugStore.phase != .resolved {
                    debugStore.setPhase(.verifying)
                }
                debugStore.activeDebugSessionId = nil
            case "export":
                debugStore.lastSessionExport = payload.output ?? payload.detail ?? ""
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

        case .debugTraceAnalyze(let payload):
            let report = payload.output ?? payload.detail ?? ""
            debugStore.lastTraceAnalysis = report
            if !report.isEmpty {
                debugStore.addLog(
                    severity: .info,
                    source: "debug_trace_analyze",
                    message: payload.detail ?? "Trace analysis updated",
                    detail: payload.output,
                    category: "debug"
                )
            }

        case .debugSnapshot(let payload):
            let report = payload.output ?? payload.detail ?? ""
            debugStore.lastSnapshotReport = report
            if !report.isEmpty {
                debugStore.addLog(
                    severity: .info,
                    source: "debug_snapshot",
                    message: payload.detail ?? "Snapshot \(payload.action)",
                    detail: payload.output,
                    category: "debug"
                )
            }

        case .debugTimeline(let payload):
            let report = payload.output ?? payload.detail ?? ""
            debugStore.lastTimelineReport = report
            if !report.isEmpty {
                debugStore.addLog(
                    severity: .info,
                    source: "debug_timeline",
                    message: payload.detail ?? "Timeline generated",
                    detail: payload.output,
                    category: "debug"
                )
            }

        case .debugTestCheck(let payload):
            debugStore.lastTestCheckReport = payload.output ?? payload.detail ?? ""
            debugStore.addLog(
                severity: payload.overallStatus == "failed" ? .error : .info,
                source: "debug_test_check",
                message: payload.detail ?? "Xcode test verification",
                detail: payload.output,
                category: "test"
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
