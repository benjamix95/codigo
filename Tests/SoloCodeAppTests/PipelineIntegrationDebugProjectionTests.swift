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

    func testRegisterDebugStoreAfterSuspendFlushesBufferedWithoutExplicitResume() {
        let service = PipelineIntegrationService()
        let debugStore = DebugStore()
        let conversationId = UUID()

        service.registerDebugStore(debugStore, for: conversationId)
        service.suspendDebugProjection(for: conversationId)

        service.handleRawEvent(
            RawEventPayload(
                jobId: "job-rebind",
                taskId: "task-rebind",
                rawType: "debug_phase_update",
                payload: [
                    "phase": "instrumenting",
                    "detail": "Instrumentation"
                ]
            ),
            for: conversationId
        )

        XCTAssertEqual(debugStore.phase, .idle)

        service.registerDebugStore(debugStore, for: conversationId)

        XCTAssertEqual(debugStore.phase, .instrumenting)
    }

    func testActivateDebugModeStartsDescribingSessionAndRevealsPanel() {
        let service = PipelineIntegrationService()
        let debugStore = DebugStore()
        let conversationId = UUID()
        var receivedEffects: [DebugProjectionUIEffects] = []

        service.registerDebugStore(
            debugStore,
            for: conversationId,
            applyEffects: { effects in
                receivedEffects.append(effects)
            }
        )

        service.handleRawEvent(
            RawEventPayload(
                jobId: "job-activate",
                taskId: "task-activate",
                rawType: "activate_debug_mode",
                payload: [
                    "reason": "Investigate crash on launch"
                ]
            ),
            for: conversationId
        )

        XCTAssertEqual(debugStore.phase, .describing)
        XCTAssertEqual(debugStore.errorSummary, "Investigate crash on launch")
        XCTAssertTrue(receivedEffects.contains { $0.shouldEnableDebugMode })
        XCTAssertTrue(receivedEffects.contains { $0.shouldRevealDebugPanel })
    }

    func testIsDebugProjectionSuppressedTracksSuspendResume() {
        let service = PipelineIntegrationService()
        let conversationId = UUID()
        XCTAssertFalse(service.isDebugProjectionSuppressed(for: conversationId))
        service.suspendDebugProjection(for: conversationId)
        XCTAssertTrue(service.isDebugProjectionSuppressed(for: conversationId))
        service.resumeDebugProjection(for: conversationId)
        XCTAssertFalse(service.isDebugProjectionSuppressed(for: conversationId))
    }

    func testUnregisterPreservesDebugProjectionSuppressState() {
        let service = PipelineIntegrationService()
        let conversationId = UUID()
        service.suspendDebugProjection(for: conversationId)
        service.unregisterDebugStore(for: conversationId)
        XCTAssertTrue(service.isDebugProjectionSuppressed(for: conversationId))
    }

    func testDiscardWithoutRuntimeClearsPendingDebugBufferAndProjectionState() {
        let service = PipelineIntegrationService()
        let conversationId = UUID()
        service.handleRawEvent(
            RawEventPayload(
                jobId: "job-discard-no-runtime",
                taskId: "task-discard-no-runtime",
                rawType: "debug_phase_update",
                payload: [
                    "phase": "fixing",
                    "detail": "orphan"
                ]
            ),
            for: conversationId
        )
        XCTAssertEqual(service.pendingDebugEventsByConversation[conversationId]?.count, 1)
        let discarded = service.discardConversationRuntime(for: conversationId)
        XCTAssertFalse(discarded)
        XCTAssertNil(service.pendingDebugEventsByConversation[conversationId])
        XCTAssertNil(service.debugStoresByConversation[conversationId])
        XCTAssertFalse(service.isDebugProjectionSuppressed(for: conversationId))
    }

    func testPendingBufferedDebugEventCountWhileSuppressed() {
        let service = PipelineIntegrationService()
        let conversationId = UUID()
        XCTAssertEqual(service.pendingBufferedDebugEventCount(for: conversationId), 0)
        service.suspendDebugProjection(for: conversationId)
        let revAfterSuspend = service.debugProjectionBufferRevision
        XCTAssertGreaterThan(revAfterSuspend, 0)
        service.handleRawEvent(
            RawEventPayload(
                jobId: "job-pend-1",
                taskId: "task-pend-1",
                rawType: "debug_phase_update",
                payload: [
                    "phase": "verifying",
                    "detail": "held"
                ]
            ),
            for: conversationId
        )
        XCTAssertEqual(service.pendingBufferedDebugEventCount(for: conversationId), 1)
        XCTAssertGreaterThan(service.debugProjectionBufferRevision, revAfterSuspend)
    }

    func testDebugEventBufferedQueueNeverExceedsConfiguredLimit() {
        let service = PipelineIntegrationService()
        let conversationId = UUID()
        for index in 0..<600 {
            service.handleRawEvent(
                RawEventPayload(
                    jobId: "job-buffer-\(index)",
                    taskId: "task-buffer-\(index)",
                    rawType: "debug_phase_update",
                    payload: [
                        "phase": index % 2 == 0 ? "fixing" : "verifying",
                        "detail": "bulk \(index)"
                    ]
                ),
                for: conversationId
            )
        }
        XCTAssertEqual(service.pendingDebugEventsByConversation[conversationId]?.count, 500)
    }

    func testRegisterWithReactivateFalseKeepsBufferedEventsUntilResume() {
        let service = PipelineIntegrationService()
        let debugStore = DebugStore()
        let conversationId = UUID()
        service.registerDebugStore(debugStore, for: conversationId, reactivateProjection: true)
        service.suspendDebugProjection(for: conversationId)
        service.handleRawEvent(
            RawEventPayload(
                jobId: "job-suspend-buffer",
                taskId: "task-suspend-buffer",
                rawType: "debug_phase_update",
                payload: [
                    "phase": "fixing",
                    "detail": "Applied"
                ]
            ),
            for: conversationId
        )
        XCTAssertEqual(debugStore.phase, .idle)
        service.unregisterDebugStore(for: conversationId)
        service.registerDebugStore(
            debugStore,
            for: conversationId,
            reactivateProjection: false,
            applyEffects: { _ in }
        )
        XCTAssertTrue(service.isDebugProjectionSuppressed(for: conversationId))
        XCTAssertEqual(debugStore.phase, .idle)
        service.resumeDebugProjection(for: conversationId)
        XCTAssertEqual(debugStore.phase, .fixing)
    }
}
