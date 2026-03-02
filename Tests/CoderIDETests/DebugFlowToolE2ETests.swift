import XCTest
@testable import CoderIDE

@MainActor
final class DebugFlowToolE2ETests: XCTestCase {
    func testToolDrivenDebugFlowCycleAndTimeline() {
        let debugStore = DebugStore()
        let taskStore = TaskActivityStore()

        debugStore.startDebugSession(errorContext: "Crash on launch")
        XCTAssertEqual(debugStore.phase, .describing)

        ingest(
            type: "debug_phase_update",
            payload: ["phase": "reproducing"],
            debugStore: debugStore,
            taskStore: taskStore
        )
        XCTAssertEqual(debugStore.phase, .reproducing)

        debugStore.confirmReproduced()
        XCTAssertEqual(debugStore.phase, .fixing)

        let hypothesisId = UUID()
        ingest(
            type: "debug_hypothesize",
            payload: [
                "action": "propose",
                "hypothesis_id": hypothesisId.uuidString,
                "hypothesis_title": "Nil dereference in parser",
                "description": "Parser state can be nil after reset",
                "hypothesis_status": "proposed",
                "status": "completed"
            ],
            debugStore: debugStore,
            taskStore: taskStore
        )
        XCTAssertEqual(debugStore.hypotheses.count, 1)

        ingest(
            type: "debug_mark",
            payload: [
                "marker_info": "Sources/App.swift|42|added debug print",
                "status": "completed"
            ],
            debugStore: debugStore,
            taskStore: taskStore
        )
        XCTAssertEqual(debugStore.debugMarkers.count, 1)

        ingest(
            type: "debug_log",
            payload: [
                "severity": "info",
                "source": "Sources/App.swift:42",
                "message": "state=nil",
                "category": "runtime",
                "status": "completed"
            ],
            debugStore: debugStore,
            taskStore: taskStore
        )
        XCTAssertEqual(debugStore.runtimeLogs.count, 1)

        debugStore.phase = .verifying
        _ = debugStore.beginMarkFixed(summary: "Fixed parser nil crash")
        XCTAssertTrue(debugStore.awaitingDebugClean)

        ingest(
            type: "debug_clean",
            payload: [
                "detail": "Removed 1 debug markers from 1 files",
                "cleaned_markers": "1",
                "cleaned_files": "1",
                "status": "completed"
            ],
            debugStore: debugStore,
            taskStore: taskStore
        )

        XCTAssertEqual(debugStore.phase, .resolved)
        XCTAssertFalse(debugStore.awaitingDebugClean)
        XCTAssertEqual(debugStore.resolutionSummary, "Fixed parser nil crash")

        taskStore.flushPending()
        let visibleTypes = Set(taskStore.concreteRecentActivities(limit: 50).map(\.type))
        XCTAssertTrue(visibleTypes.contains("debug_hypothesize"))
        XCTAssertTrue(visibleTypes.contains("debug_mark"))
        XCTAssertTrue(visibleTypes.contains("debug_log"))
        XCTAssertTrue(visibleTypes.contains("debug_clean"))
    }

    private func ingest(
        type: String,
        payload: [String: String],
        debugStore: DebugStore,
        taskStore: TaskActivityStore
    ) {
        let envelope = EventNormalizer.normalizeEnvelope(
            sourceProvider: "test",
            type: type,
            payload: payload
        )
        taskStore.addEnvelope(envelope)

        for event in envelope.events {
            switch event {
            case .taskActivity(let activity):
                taskStore.addActivity(activity)
            case .debugPhaseUpdate(let phase, _):
                debugStore.setPhase(phase)
            case .debugUserRequest(let kind, _):
                if kind == "reproduce" {
                    debugStore.setPhase(.reproducing)
                }
            case .debugResolved(let summary):
                debugStore.resolveSession(summary: summary)
            case .debugLog(let logPayload):
                debugStore.addLog(
                    severity: logPayload.severity,
                    source: logPayload.source,
                    message: logPayload.message,
                    detail: logPayload.detail,
                    category: logPayload.category
                )
                if logPayload.category == "runtime" || logPayload.category == "instrumentation" {
                    debugStore.addRuntimeLog(
                        location: logPayload.source,
                        message: logPayload.message,
                        data: logPayload.data,
                        hypothesisId: logPayload.hypothesisId
                    )
                }
            case .debugHypothesize(let hypothesisPayload):
                switch hypothesisPayload.action {
                case "update":
                    if let id = hypothesisPayload.hypothesisId,
                       let status = hypothesisPayload.status
                    {
                        _ = debugStore.updateHypothesis(id: id, status: status, evidence: hypothesisPayload.evidence)
                    }
                default:
                    let title = hypothesisPayload.title ?? ""
                    let description = hypothesisPayload.description ?? ""
                    _ = debugStore.addHypothesis(
                        id: hypothesisPayload.hypothesisId,
                        title: title,
                        description: description,
                        status: hypothesisPayload.status ?? .proposed,
                        evidence: hypothesisPayload.evidence
                    )
                }
            case .debugMark(let markerPayload):
                debugStore.addDebugMarker(DebugMarker(
                    filePath: markerPayload.filePath,
                    lineNumber: markerPayload.lineNumber,
                    markerComment: markerPayload.comment
                ))
            case .debugInstrument(let instrumentPayload):
                let type: InstrumentationPoint.InstrumentationType
                switch instrumentPayload.type {
                case "assert": type = .assertion
                case "timing": type = .timing
                case "variable": type = .variable
                default: type = .logging
                }
                debugStore.addInstrumentation(
                    filePath: instrumentPayload.filePath,
                    lineNumber: instrumentPayload.lineNumber,
                    type: type,
                    code: instrumentPayload.label ?? instrumentPayload.expression ?? "instrumentation",
                    hypothesisId: instrumentPayload.hypothesisId
                )
            case .debugClean(let cleanPayload):
                let status = (cleanPayload.status ?? "completed").lowercased()
                let success = status != "failed" && status != "error"
                debugStore.applyDebugCleanResult(success: success, detail: cleanPayload.detail)
            case .debugSession(let sessionPayload):
                switch sessionPayload.action {
                case "start":
                    if debugStore.phase == .idle || debugStore.phase == .resolved {
                        debugStore.startDebugSession(errorContext: sessionPayload.detail ?? "")
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
            case .debugQuery(let queryPayload):
                let detail = queryPayload.detail ?? "Debug query \(queryPayload.format)"
                debugStore.addLog(
                    severity: .info,
                    source: "debug_query",
                    message: detail,
                    detail: queryPayload.output,
                    category: "debug"
                )
            case .activatePlanMode, .activateDebugMode,
                 .instantGrep, .todoWrite, .todoRead, .planStepUpdate, .mermaidRender:
                break
            }
        }
    }
}
