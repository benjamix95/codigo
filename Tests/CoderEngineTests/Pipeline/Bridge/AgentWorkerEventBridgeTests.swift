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

    private static func bridgeSequence(from eventId: String) -> UInt64? {
        let prefix = "evt_stream_"
        guard eventId.hasPrefix(prefix) else { return nil }
        let remainder = eventId.dropFirst(prefix.count)
        let sequenceString = remainder.split(separator: "_", maxSplits: 1).first
        return sequenceString.flatMap { UInt64($0) }
    }
}

