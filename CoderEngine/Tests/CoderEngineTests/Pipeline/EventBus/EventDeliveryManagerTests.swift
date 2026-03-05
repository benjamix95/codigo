import XCTest
@testable import CoderEngine

final class EventDeliveryManagerTests: XCTestCase {

    // MARK: - Helpers

    private func makeEvent(
        eventId: String = "evt_1",
        idempotencyKey: String = "key_1"
    ) -> EventBusEvent {
        EventBusEvent(
            eventId: eventId,
            jobId: "job_1",
            type: .taskStarted,
            idempotencyKey: idempotencyKey
        )
    }

    private func makeDLQ() -> DeadLetterQueue {
        DeadLetterQueue(capacity: 100)
    }

    // MARK: - Successful Delivery

    func testDeliver_successOnFirstAttempt() async {
        let dlq = makeDLQ()
        let manager = EventDeliveryManager(
            maxAttempts: 3,
            baseDelayMs: 10,
            deadLetterQueue: dlq
        )

        let exp = XCTestExpectation(description: "delivered")
        var deliveredEvent: EventBusEvent?

        let sub = EventSubscription(
            id: "sub_1",
            filter: EventSubscriptionFilter()
        ) { event in
            deliveredEvent = event
            exp.fulfill()
        }

        await manager.deliver(event: makeEvent(), to: sub)

        await fulfillment(of: [exp], timeout: 2.0)
        XCTAssertNotNil(deliveredEvent)

        let delivered = await manager.totalDelivered
        XCTAssertEqual(delivered, 1)

        let failed = await manager.totalFailed
        XCTAssertEqual(failed, 0)

        let dlqCount = await dlq.count()
        XCTAssertEqual(dlqCount, 0)
    }

    // MARK: - Metrics

    func testSuccessRate_allSuccess() async {
        let dlq = makeDLQ()
        let manager = EventDeliveryManager(
            maxAttempts: 1,
            baseDelayMs: 10,
            deadLetterQueue: dlq
        )

        let sub = EventSubscription(
            id: "sub_1",
            filter: EventSubscriptionFilter()
        ) { _ in }

        await manager.deliver(
            event: makeEvent(eventId: "e1", idempotencyKey: "k1"),
            to: sub
        )
        await manager.deliver(
            event: makeEvent(eventId: "e2", idempotencyKey: "k2"),
            to: sub
        )

        let rate = await manager.successRate()
        XCTAssertEqual(rate, 1.0)
    }

    // MARK: - Backoff Calculation

    func testBackoff_exponentialGrowth() async {
        let dlq = makeDLQ()
        let manager = EventDeliveryManager(
            maxAttempts: 5,
            baseDelayMs: 100,
            maxDelayMs: 5000,
            deadLetterQueue: dlq
        )

        let d1 = await manager.calculateBackoff(attempt: 1)
        let d2 = await manager.calculateBackoff(attempt: 2)
        let d3 = await manager.calculateBackoff(attempt: 3)

        XCTAssertTrue(d2 > d1, "Backoff deve crescere: d2(\(d2)) > d1(\(d1))")
        XCTAssertTrue(d3 > d2, "Backoff deve crescere: d3(\(d3)) > d2(\(d2))")
    }

    func testBackoff_neverExceedsMax() async {
        let dlq = makeDLQ()
        let manager = EventDeliveryManager(
            maxAttempts: 5,
            baseDelayMs: 100,
            maxDelayMs: 500,
            deadLetterQueue: dlq
        )

        let d10 = await manager.calculateBackoff(attempt: 10)
        XCTAssertTrue(d10 <= 500, "Backoff non deve superare maxDelay")
    }

    // MARK: - Recent Attempts

    func testRecentAttempts_tracksHistory() async {
        let dlq = makeDLQ()
        let manager = EventDeliveryManager(
            maxAttempts: 1,
            baseDelayMs: 10,
            deadLetterQueue: dlq
        )

        let sub = EventSubscription(
            id: "sub_1",
            filter: EventSubscriptionFilter()
        ) { _ in }

        await manager.deliver(event: makeEvent(), to: sub)

        let attempts = await manager.recentAttempts()
        XCTAssertEqual(attempts.count, 1)
        XCTAssertTrue(attempts[0].success)
        XCTAssertEqual(attempts[0].eventId, "evt_1")
        XCTAssertEqual(attempts[0].subscriptionId, "sub_1")
    }

    // MARK: - Pending Count

    func testPendingCount_zeroAfterDelivery() async {
        let dlq = makeDLQ()
        let manager = EventDeliveryManager(
            maxAttempts: 1,
            baseDelayMs: 10,
            deadLetterQueue: dlq
        )

        let sub = EventSubscription(
            id: "sub_1",
            filter: EventSubscriptionFilter()
        ) { _ in }

        await manager.deliver(event: makeEvent(), to: sub)

        let pending = await manager.pendingCount()
        XCTAssertEqual(pending, 0)
    }

    // MARK: - Reset

    func testReset_clearsState() async {
        let dlq = makeDLQ()
        let manager = EventDeliveryManager(
            maxAttempts: 1,
            baseDelayMs: 10,
            deadLetterQueue: dlq
        )

        let sub = EventSubscription(
            id: "sub_1",
            filter: EventSubscriptionFilter()
        ) { _ in }

        await manager.deliver(event: makeEvent(), to: sub)
        await manager.reset()

        let delivered = await manager.totalDelivered
        let failed = await manager.totalFailed
        let pending = await manager.pendingCount()
        let attempts = await manager.recentAttempts()

        XCTAssertEqual(delivered, 0)
        XCTAssertEqual(failed, 0)
        XCTAssertEqual(pending, 0)
        XCTAssertTrue(attempts.isEmpty)
    }
}
