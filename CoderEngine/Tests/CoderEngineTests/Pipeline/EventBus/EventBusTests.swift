import XCTest
@testable import CoderEngine

final class EventBusTests: XCTestCase {

    // MARK: - Helpers

    private func makeEvent(
        eventId: String = "evt_1",
        jobId: String = "job_1",
        type: PipelineEventType = .taskStarted,
        idempotencyKey: String? = nil
    ) -> EventBusEvent {
        EventBusEvent(
            eventId: eventId,
            jobId: jobId,
            type: type,
            idempotencyKey: idempotencyKey ?? "key_\(eventId)"
        )
    }

    // MARK: - Publish & Subscribe

    func testPublish_deliversToMatchingSubscriber() async throws {
        let bus = EventBus(maxDeliveryAttempts: 1)

        let expectation = XCTestExpectation(description: "event received")
        var received: EventBusEvent?

        await bus.subscribe(EventSubscription(
            id: "sub_1",
            filter: EventSubscriptionFilter(eventTypes: [.taskStarted])
        ) { event in
            received = event
            expectation.fulfill()
        })

        try await bus.publish(makeEvent())

        await fulfillment(of: [expectation], timeout: 2.0)
        XCTAssertEqual(received?.eventId, "evt_1")
        XCTAssertEqual(received?.deliveryStatus, .pending)
    }

    func testPublish_doesNotDeliverToNonMatchingSubscriber() async throws {
        let bus = EventBus(maxDeliveryAttempts: 1)
        var called = false

        await bus.subscribe(EventSubscription(
            id: "sub_1",
            filter: EventSubscriptionFilter(eventTypes: [.rollbackStarted])
        ) { _ in
            called = true
        })

        try await bus.publish(makeEvent(type: .taskStarted))

        try await Task.sleep(nanoseconds: 200_000_000)
        XCTAssertFalse(called)
    }

    func testPublish_multipleSubs_allReceive() async throws {
        let bus = EventBus(maxDeliveryAttempts: 1)

        let exp1 = XCTestExpectation(description: "sub1")
        let exp2 = XCTestExpectation(description: "sub2")

        await bus.subscribe(EventSubscription(
            id: "sub_1",
            filter: EventSubscriptionFilter()
        ) { _ in exp1.fulfill() })

        await bus.subscribe(EventSubscription(
            id: "sub_2",
            filter: EventSubscriptionFilter()
        ) { _ in exp2.fulfill() })

        try await bus.publish(makeEvent())

        await fulfillment(of: [exp1, exp2], timeout: 2.0)
    }

    // MARK: - Idempotency

    func testPublish_duplicateIdempotencyKey_throws() async throws {
        let bus = EventBus(maxDeliveryAttempts: 1)

        await bus.subscribe(EventSubscription(
            id: "sub_1",
            filter: EventSubscriptionFilter()
        ) { _ in })

        try await bus.publish(makeEvent(idempotencyKey: "dup_key"))

        do {
            try await bus.publish(makeEvent(
                eventId: "evt_2",
                idempotencyKey: "dup_key"
            ))
            XCTFail("Dovrebbe aver lanciato duplicateIdempotencyKey")
        } catch let error as EventBusError {
            if case .duplicateIdempotencyKey(let key) = error {
                XCTAssertEqual(key, "dup_key")
            } else {
                XCTFail("Errore sbagliato: \(error)")
            }
        }
    }

    func testPublish_allowsReusingIdempotencyKeyAfterPrune() async throws {
        let bus = EventBus(
            maxDeliveryAttempts: 1,
            maxTrackedIdempotencyKeys: 100,
            idempotencyKeyMaxAge: 3600
        )

        await bus.subscribe(EventSubscription(
            id: "sub_1",
            filter: EventSubscriptionFilter()
        ) { _ in })

        try await bus.publish(makeEvent(eventId: "evt_1", idempotencyKey: "prune_key"))
        await bus.pruneIdempotencyKeys(olderThan: 0)

        do {
            try await bus.publish(
                makeEvent(eventId: "evt_2", idempotencyKey: "prune_key")
            )
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testPublish_evictsOldestIdempotencyKeysWhenCapacityReached() async throws {
        let bus = EventBus(
            maxDeliveryAttempts: 1,
            maxTrackedIdempotencyKeys: 2,
            idempotencyKeyMaxAge: 3600
        )

        await bus.subscribe(EventSubscription(
            id: "sub_1",
            filter: EventSubscriptionFilter()
        ) { _ in })

        try await bus.publish(makeEvent(eventId: "evt_1", idempotencyKey: "k1"))
        try await bus.publish(makeEvent(eventId: "evt_2", idempotencyKey: "k2"))
        try await bus.publish(makeEvent(eventId: "evt_3", idempotencyKey: "k3"))

        do {
            try await bus.publish(makeEvent(eventId: "evt_4", idempotencyKey: "k1"))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        do {
            try await bus.publish(makeEvent(eventId: "evt_5", idempotencyKey: "k3"))
            XCTFail("Dovrebbe aver lanciato duplicateIdempotencyKey")
        } catch let error as EventBusError {
            if case .duplicateIdempotencyKey(let key) = error {
                XCTAssertEqual(key, "k3")
            } else {
                XCTFail("Errore sbagliato: \(error)")
            }
        }
    }

    // MARK: - Sequence Number

    func testPublish_incrementsSequenceNumber() async throws {
        let bus = EventBus(maxDeliveryAttempts: 1)

        var sequences: [UInt64] = []

        await bus.subscribe(EventSubscription(
            id: "sub_1",
            filter: EventSubscriptionFilter()
        ) { event in
            sequences.append(event.sequenceNumber)
        })

        try await bus.publish(makeEvent(eventId: "e1", idempotencyKey: "k1"))
        try await bus.publish(makeEvent(eventId: "e2", idempotencyKey: "k2"))
        try await bus.publish(makeEvent(eventId: "e3", idempotencyKey: "k3"))

        try await Task.sleep(nanoseconds: 300_000_000)
        XCTAssertEqual(sequences, [1, 2, 3])
    }

    // MARK: - Unsubscribe

    func testUnsubscribe_removesSubscriber() async throws {
        let bus = EventBus(maxDeliveryAttempts: 1)
        var count = 0

        await bus.subscribe(EventSubscription(
            id: "sub_1",
            filter: EventSubscriptionFilter()
        ) { _ in count += 1 })

        try await bus.publish(makeEvent(eventId: "e1", idempotencyKey: "k1"))
        try await Task.sleep(nanoseconds: 200_000_000)
        XCTAssertEqual(count, 1)

        await bus.unsubscribe(id: "sub_1")
        let deadLetterCount = await bus.deadLetterCount()
        let subCount = await bus.subscriberCount()
        XCTAssertEqual(subCount, 0)
        XCTAssertTrue(deadLetterCount >= 0)
    }

    // MARK: - No Subscribers → DLQ

    func testPublish_noSubscribers_goesToDLQ() async throws {
        let bus = EventBus(maxDeliveryAttempts: 1)

        try await bus.publish(makeEvent())

        let dlqCount = await bus.deadLetterCount()
        XCTAssertEqual(dlqCount, 1)
    }

    // MARK: - Shutdown

    func testShutdown_rejectsNewPublish() async {
        let bus = EventBus(maxDeliveryAttempts: 1)
        await bus.shutdown()

        do {
            try await bus.publish(makeEvent())
            XCTFail("Dovrebbe aver lanciato busShutdown")
        } catch let error as EventBusError {
            XCTAssertEqual(error, .busShutdown)
        } catch {
            XCTFail("Errore inatteso: \(error)")
        }
    }

    // MARK: - Filter

    func testFilter_matchesByJobId() {
        let filter = EventSubscriptionFilter(jobId: "job_1")

        let event1 = makeEvent(jobId: "job_1")
        let event2 = makeEvent(jobId: "job_2")

        XCTAssertTrue(filter.matches(event1))
        XCTAssertFalse(filter.matches(event2))
    }

    func testFilter_matchesByEventType() {
        let filter = EventSubscriptionFilter(
            eventTypes: [.taskStarted, .taskCompleted]
        )

        let e1 = makeEvent(type: .taskStarted)
        let e2 = makeEvent(type: .taskFailed)

        XCTAssertTrue(filter.matches(e1))
        XCTAssertFalse(filter.matches(e2))
    }

    func testFilter_emptyFilter_matchesAll() {
        let filter = EventSubscriptionFilter()
        let event = makeEvent()
        XCTAssertTrue(filter.matches(event))
    }

    // MARK: - Validation

    func testPublish_invalidEvent_throws() async {
        let bus = EventBus(maxDeliveryAttempts: 1)

        let invalid = EventBusEvent(
            eventId: "",
            jobId: "job_1",
            type: .taskStarted,
            idempotencyKey: "k1"
        )

        do {
            try await bus.publish(invalid)
            XCTFail("Dovrebbe aver lanciato errore di validazione")
        } catch {
            XCTAssertTrue(error is PipelineValidationError)
        }
    }
}
