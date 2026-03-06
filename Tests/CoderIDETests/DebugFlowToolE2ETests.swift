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
            if case .taskActivity(let activity) = event {
                taskStore.addActivity(activity)
                continue
            }
            if DebugProjectionEventConsumer.handles(event) {
                _ = DebugProjectionEventConsumer.apply(event, to: debugStore)
            }
        }
    }
}
