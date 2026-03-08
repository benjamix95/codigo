import XCTest
@testable import CoderEngine

final class DeadLetterQueueTests: XCTestCase {

    // MARK: - Helpers

    private func makeEvent(
        eventId: String = "evt_1",
        jobId: String = "job_1"
    ) -> EventBusEvent {
        EventBusEvent(
            eventId: eventId,
            jobId: jobId,
            type: .taskFailed,
            idempotencyKey: "key_\(eventId)",
            deliveryAttempts: 3
        )
    }

    // MARK: - Enqueue

    func testEnqueue_incrementsCount() async {
        let dlq = DeadLetterQueue(capacity: 100)

        await dlq.enqueue(makeEvent(), reason: .maxAttemptsExceeded(3))

        let count = await dlq.count()
        XCTAssertEqual(count, 1)

        let total = await dlq.totalEnqueued
        XCTAssertEqual(total, 1)
    }

    func testEnqueue_multipleEntries() async {
        let dlq = DeadLetterQueue(capacity: 100)

        await dlq.enqueue(
            makeEvent(eventId: "e1"),
            reason: .maxAttemptsExceeded(3)
        )
        await dlq.enqueue(
            makeEvent(eventId: "e2"),
            reason: .noSubscribers
        )

        let count = await dlq.count()
        XCTAssertEqual(count, 2)
    }

    // MARK: - Capacity & Eviction

    func testEnqueue_evictsOldestWhenFull() async {
        let dlq = DeadLetterQueue(capacity: 2)

        await dlq.enqueue(
            makeEvent(eventId: "e1"),
            reason: .noSubscribers
        )
        await dlq.enqueue(
            makeEvent(eventId: "e2"),
            reason: .noSubscribers
        )
        await dlq.enqueue(
            makeEvent(eventId: "e3"),
            reason: .noSubscribers
        )

        let count = await dlq.count()
        XCTAssertEqual(count, 2)

        let evicted = await dlq.totalEvicted
        XCTAssertEqual(evicted, 1)

        let recent = await dlq.recent(limit: 10)
        let ids = recent.map { $0.event.eventId }
        XCTAssertFalse(ids.contains("e1"), "e1 dovrebbe essere stato evicted")
        XCTAssertTrue(ids.contains("e2"))
        XCTAssertTrue(ids.contains("e3"))
    }

    // MARK: - Alert

    func testAlert_firesWhenThresholdReached() async {
        let dlq = DeadLetterQueue(capacity: 10, alertThreshold: 2)

        let exp = XCTestExpectation(description: "alert fired")
        var receivedAlert: DLQAlert?

        await dlq.onAlert { alert in
            receivedAlert = alert
            exp.fulfill()
        }

        await dlq.enqueue(makeEvent(eventId: "e1"), reason: .noSubscribers)
        await dlq.enqueue(makeEvent(eventId: "e2"), reason: .noSubscribers)

        await fulfillment(of: [exp], timeout: 2.0)
        XCTAssertNotNil(receivedAlert)
        XCTAssertEqual(receivedAlert?.threshold, 2)
        XCTAssertEqual(receivedAlert?.currentSize, 2)
    }

    // MARK: - Query by Job

    func testEntriesForJob_filtersCorrectly() async {
        let dlq = DeadLetterQueue(capacity: 100)

        await dlq.enqueue(
            makeEvent(eventId: "e1", jobId: "job_A"),
            reason: .noSubscribers
        )
        await dlq.enqueue(
            makeEvent(eventId: "e2", jobId: "job_B"),
            reason: .noSubscribers
        )
        await dlq.enqueue(
            makeEvent(eventId: "e3", jobId: "job_A"),
            reason: .maxAttemptsExceeded(3)
        )

        let jobA = await dlq.entriesForJob("job_A")
        XCTAssertEqual(jobA.count, 2)

        let jobB = await dlq.entriesForJob("job_B")
        XCTAssertEqual(jobB.count, 1)
    }

    // MARK: - Reason Breakdown

    func testReasonBreakdown_countsCorrectly() async {
        let dlq = DeadLetterQueue(capacity: 100)

        await dlq.enqueue(
            makeEvent(eventId: "e1"),
            reason: .noSubscribers
        )
        await dlq.enqueue(
            makeEvent(eventId: "e2"),
            reason: .noSubscribers
        )
        await dlq.enqueue(
            makeEvent(eventId: "e3"),
            reason: .maxAttemptsExceeded(3)
        )

        let breakdown = await dlq.reasonBreakdown()
        XCTAssertEqual(breakdown["no_subscribers"], 2)
        XCTAssertEqual(breakdown["max_attempts_exceeded"], 1)
    }

    // MARK: - Drain

    func testDrain_returnsAllAndClears() async {
        let dlq = DeadLetterQueue(capacity: 100)

        await dlq.enqueue(makeEvent(eventId: "e1"), reason: .noSubscribers)
        await dlq.enqueue(makeEvent(eventId: "e2"), reason: .noSubscribers)

        let drained = await dlq.drain()
        XCTAssertEqual(drained.count, 2)

        let remaining = await dlq.count()
        XCTAssertEqual(remaining, 0)
    }

    func testDrainJob_onlyDrainsTargetJob() async {
        let dlq = DeadLetterQueue(capacity: 100)

        await dlq.enqueue(
            makeEvent(eventId: "e1", jobId: "job_A"),
            reason: .noSubscribers
        )
        await dlq.enqueue(
            makeEvent(eventId: "e2", jobId: "job_B"),
            reason: .noSubscribers
        )

        let drained = await dlq.drainJob("job_A")
        XCTAssertEqual(drained.count, 1)
        XCTAssertEqual(drained[0].event.jobId, "job_A")

        let remaining = await dlq.count()
        XCTAssertEqual(remaining, 1)
    }

    // MARK: - Recent

    func testRecent_limitsOutput() async {
        let dlq = DeadLetterQueue(capacity: 100)

        for i in 1...10 {
            await dlq.enqueue(
                makeEvent(eventId: "e\(i)"),
                reason: .noSubscribers
            )
        }

        let recent = await dlq.recent(limit: 3)
        XCTAssertEqual(recent.count, 3)
        XCTAssertEqual(recent.last?.event.eventId, "e10")
    }

    // MARK: - DeadLetterReason

    func testDeadLetterReason_descriptions() {
        let r1 = DeadLetterReason.maxAttemptsExceeded(3)
        XCTAssertEqual(r1.description, "max_attempts_exceeded(3)")

        let r2 = DeadLetterReason.noSubscribers
        XCTAssertEqual(r2.description, "no_subscribers")

        let r3 = DeadLetterReason.handlerError("timeout")
        XCTAssertEqual(r3.description, "handler_error: timeout")

        let r4 = DeadLetterReason.invalidEvent("missing field")
        XCTAssertEqual(r4.description, "invalid_event: missing field")
    }

    // MARK: - Reset

    func testReset_clearsEverything() async {
        let dlq = DeadLetterQueue(capacity: 100)

        await dlq.enqueue(makeEvent(), reason: .noSubscribers)
        await dlq.reset()

        let count = await dlq.count()
        let total = await dlq.totalEnqueued
        let evicted = await dlq.totalEvicted
        let alerts = await dlq.alertCount()
        let breakdown = await dlq.reasonBreakdown()

        XCTAssertEqual(count, 0)
        XCTAssertEqual(total, 0)
        XCTAssertEqual(evicted, 0)
        XCTAssertEqual(alerts, 0)
        XCTAssertTrue(breakdown.isEmpty)
    }
}
