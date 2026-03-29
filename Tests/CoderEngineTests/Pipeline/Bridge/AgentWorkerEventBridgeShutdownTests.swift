import XCTest
@testable import CoderEngine
import os

final class AgentWorkerEventBridgeShutdownTests: XCTestCase {

    // MARK: - A3 Regression: isShutdown data race protection

    func testShutdownPreventsSubsequentPublish() async throws {
        let bus = EventBus(maxDeliveryAttempts: 1)
        let bridge = AgentWorkerEventBridge(eventBus: bus, jobId: "job-shutdown")

        let preShutdownExpectation = XCTestExpectation(description: "pre-shutdown event")
        let receivedCount = OSAllocatedUnfairLock(initialState: 0)
        await bus.subscribe(EventSubscription(
            id: "sub-shutdown",
            filter: EventSubscriptionFilter()
        ) { _ in
            receivedCount.withLock { $0 += 1 }
            preShutdownExpectation.fulfill()
        })

        // Emit one event before shutdown — should be delivered.
        await bridge.worker(jobId: "ignored", taskId: "t1", didEmitTextDelta: "before")
        await fulfillment(of: [preShutdownExpectation], timeout: 5.0)
        XCTAssertEqual(receivedCount.withLock { $0 }, 1)

        // Shutdown the bridge.
        bridge.shutdown()

        // Emit events after shutdown — should NOT be delivered.
        await bridge.worker(jobId: "ignored", taskId: "t2", didEmitTextDelta: "after-delta")
        await bridge.worker(jobId: "ignored", taskId: "t3", didReplace: "after-replace")
        await bridge.worker(jobId: "ignored", taskId: "t4", didEmitRaw: "raw", payload: [:])

        // Small delay to ensure any straggler events would have been delivered.
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(receivedCount.withLock { $0 }, 1, "No events should be published after shutdown")
    }

    func testConcurrentShutdownAndPublishDoesNotCrash() async throws {
        let bus = EventBus(maxDeliveryAttempts: 1)
        let bridge = AgentWorkerEventBridge(eventBus: bus, jobId: "job-race")

        await bus.subscribe(EventSubscription(
            id: "sub-race",
            filter: EventSubscriptionFilter()
        ) { _ in })

        // Hammer shutdown and publish concurrently — must not crash.
        await withTaskGroup(of: Void.self) { group in
            for i in 0..<50 {
                group.addTask {
                    await bridge.worker(
                        jobId: "ignored",
                        taskId: "task-\(i)",
                        didEmitTextDelta: "delta-\(i)"
                    )
                }
                if i == 25 {
                    group.addTask {
                        bridge.shutdown()
                    }
                }
            }
        }
        // If we reach here without crash, the lock is working.
    }

    // MARK: - B1 Regression: String format correctness after interpolation removal

    func testEventIdAndIdempotencyKeyFormatIsCorrect() async throws {
        let bus = EventBus(maxDeliveryAttempts: 1)
        let bridge = AgentWorkerEventBridge(eventBus: bus, jobId: "job-fmt")

        let capturedEvents = OSAllocatedUnfairLock(initialState: [EventBusEvent]())
        let expectation = XCTestExpectation(description: "3 events")
        expectation.expectedFulfillmentCount = 3

        await bus.subscribe(EventSubscription(
            id: "sub-fmt",
            filter: EventSubscriptionFilter()
        ) { event in
            capturedEvents.withLock { $0.append(event) }
            expectation.fulfill()
        })

        await bridge.worker(jobId: "ignored", taskId: "abc", didEmitTextDelta: "d")
        await bridge.worker(jobId: "ignored", taskId: "def", didReplace: "r")
        await bridge.worker(jobId: "ignored", taskId: "ghi", didEmitRaw: "raw", payload: [:])

        await fulfillment(of: [expectation], timeout: 5.0)

        let recorded = capturedEvents.withLock { $0 }

        let delta = recorded.first { $0.type == .textDelta }!
        XCTAssertEqual(delta.eventId, "evt_stream_1_delta_abc")
        XCTAssertEqual(delta.idempotencyKey, "job-fmt_delta_1_abc")

        let replace = recorded.first { $0.type == .textReplace }!
        XCTAssertEqual(replace.eventId, "evt_stream_2_replace_def")
        XCTAssertEqual(replace.idempotencyKey, "job-fmt_replace_2_def")

        let raw = recorded.first { $0.type == .rawAgentEvent }!
        XCTAssertEqual(raw.eventId, "evt_stream_3_raw_ghi")
        XCTAssertEqual(raw.idempotencyKey, "job-fmt_raw_3_ghi")
    }
}
