import XCTest
@testable import CoderEngine

final class AgentWorkerEventBridgeTests: XCTestCase {
    func testConcurrentWorkerEventsProduceUniqueMonotonicBridgeSequences() async throws {
        let bus = EventBus(maxDeliveryAttempts: 1)
        let bridge = AgentWorkerEventBridge(eventBus: bus, jobId: "job-seq")
        let expectedEventCount = 60
        let expectation = XCTestExpectation(description: "all worker events delivered")
        expectation.expectedFulfillmentCount = expectedEventCount

        var eventIds: [String] = []
        await bus.subscribe(EventSubscription(
            id: "sub-all",
            filter: EventSubscriptionFilter()
        ) { event in
            eventIds.append(event.eventId)
            expectation.fulfill()
        })

        await withTaskGroup(of: Void.self) { group in
            for index in 0..<20 {
                group.addTask {
                    await bridge.worker(
                        jobId: "ignored",
                        taskId: "task-\(index)",
                        didEmitTextDelta: "delta-\(index)"
                    )
                }
                group.addTask {
                    await bridge.worker(
                        jobId: "ignored",
                        taskId: "task-\(index)",
                        didReplace: "replace-\(index)"
                    )
                }
                group.addTask {
                    await bridge.worker(
                        jobId: "ignored",
                        taskId: "task-\(index)",
                        didEmitRaw: "raw",
                        payload: ["index": "\(index)"]
                    )
                }
            }
        }

        await fulfillment(of: [expectation], timeout: 5.0)

        let sequenceNumbers = eventIds.compactMap(Self.bridgeSequence(from:))
        XCTAssertEqual(sequenceNumbers.count, expectedEventCount)
        XCTAssertEqual(Set(sequenceNumbers).count, expectedEventCount)
        XCTAssertEqual(sequenceNumbers.sorted(), Array(1...UInt64(expectedEventCount)))
    }

    // MARK: - Event ID / Idempotency Key Format Regression

    func testEventIdAndIdempotencyKeyFormatMatchesContract() async throws {
        let bus = EventBus(maxDeliveryAttempts: 1)
        let jobId = "job-fmt"
        let bridge = AgentWorkerEventBridge(eventBus: bus, jobId: jobId)
        let taskId = "task-fmt"

        let expectation = XCTestExpectation(description: "3 events delivered")
        expectation.expectedFulfillmentCount = 3

        var capturedEvents: [EventBusEvent] = []
        await bus.subscribe(EventSubscription(
            id: "sub-fmt",
            filter: EventSubscriptionFilter()
        ) { event in
            capturedEvents.append(event)
            expectation.fulfill()
        })

        await bridge.worker(jobId: "ignored", taskId: taskId, didEmitTextDelta: "hello")
        await bridge.worker(jobId: "ignored", taskId: taskId, didReplace: "world")
        await bridge.worker(jobId: "ignored", taskId: taskId, didEmitRaw: "raw_type", payload: [:])

        await fulfillment(of: [expectation], timeout: 5.0)

        let sorted = capturedEvents.sorted { $0.sequenceNumber < $1.sequenceNumber }
        XCTAssertEqual(sorted.count, 3)

        // Delta
        let delta = sorted[0]
        XCTAssertEqual(delta.eventId, "evt_stream_1_delta_\(taskId)")
        XCTAssertEqual(delta.idempotencyKey, "\(jobId)_delta_1_\(taskId)")

        // Replace
        let replace = sorted[1]
        XCTAssertEqual(replace.eventId, "evt_stream_2_replace_\(taskId)")
        XCTAssertEqual(replace.idempotencyKey, "\(jobId)_replace_2_\(taskId)")

        // Raw
        let raw = sorted[2]
        XCTAssertEqual(raw.eventId, "evt_stream_3_raw_\(taskId)")
        XCTAssertEqual(raw.idempotencyKey, "\(jobId)_raw_3_\(taskId)")
    }

    private static func bridgeSequence(from eventId: String) -> UInt64? {
        let prefix = "evt_stream_"
        guard eventId.hasPrefix(prefix) else { return nil }
        let remainder = eventId.dropFirst(prefix.count)
        let sequenceString = remainder.split(separator: "_", maxSplits: 1).first
        return sequenceString.flatMap { UInt64($0) }
    }
}

