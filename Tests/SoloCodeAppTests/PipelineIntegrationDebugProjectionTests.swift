import XCTest
import CoderEngine
@testable import CoderIDE

@MainActor
final class PipelineIntegrationDebugProjectionTests: XCTestCase {
    func testRegisterDebugStoreFlushesBufferedEventsAndAppliesEffects() {
        let service = PipelineIntegrationService()
        let debugStore = DebugStore()
        let conversationId = UUID()
        var receivedEffects: [DebugProjectionUIEffects] = []

        service.handleRawEvent(
            RawEventPayload(
                jobId: "job-1",
                taskId: "task-1",
                rawType: "debug_phase_update",
                payload: [
                    "phase": "fixing",
                    "detail": "Applying fix"
                ]
            ),
            for: conversationId
        )

        service.registerDebugStore(
            debugStore,
            for: conversationId,
            applyEffects: { effects in
                receivedEffects.append(effects)
            }
        )

        XCTAssertEqual(debugStore.phase, .fixing)
        XCTAssertEqual(receivedEffects.count, 1)
        XCTAssertTrue(receivedEffects[0].shouldEnableDebugMode)
        XCTAssertTrue(receivedEffects[0].shouldRevealDebugPanel)
    }

    func testSuspendDebugProjectionBuffersLateEventsUntilResumed() {
        let service = PipelineIntegrationService()
        let debugStore = DebugStore()
        let conversationId = UUID()

        service.registerDebugStore(debugStore, for: conversationId)
        service.suspendDebugProjection(for: conversationId)

        service.handleRawEvent(
            RawEventPayload(
                jobId: "job-2",
                taskId: "task-2",
                rawType: "debug_phase_update",
                payload: [
                    "phase": "verifying"
                ]
            ),
            for: conversationId
        )

        XCTAssertEqual(debugStore.phase, .idle)

        service.resumeDebugProjection(for: conversationId)

        XCTAssertEqual(debugStore.phase, .verifying)
    }
}
