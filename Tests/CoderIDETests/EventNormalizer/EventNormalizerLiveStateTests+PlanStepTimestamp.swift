import XCTest
@testable import CoderIDE

extension EventNormalizerLiveStateTests {
    func testPlanStepUpdatePreservesEnvelopeTimestamp() {
        let expectedTimestamp = Date(timeIntervalSince1970: 1_751_111_111)
        let envelope = EventNormalizer.normalizeEnvelope(
            sourceProvider: "codex-cli",
            type: "plan_step_update",
            payload: [
                "step_id": "1",
                "status": "running",
                "title": "Update parser",
            ],
            timestamp: expectedTimestamp
        )

        guard let activity = envelope.events.compactMap({ event -> TaskActivity? in
            if case .taskActivity(let taskActivity) = event { return taskActivity }
            return nil
        }).last else {
            XCTFail("Missing taskActivity event")
            return
        }
        XCTAssertEqual(activity.timestamp, expectedTimestamp)
    }
}
