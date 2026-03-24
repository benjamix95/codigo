import XCTest
@testable import CoderEngine

/// Test per il limite di concorrenza dell'EventDeliveryManager.
final class EventDeliveryManagerConcurrencyTests: XCTestCase {

    // MARK: - Helpers

    private func makeDLQ() -> DeadLetterQueue {
        DeadLetterQueue(maxSize: 100)
    }

    private func makeEvent(id: String = UUID().uuidString) -> EventBusEvent {
        EventBusEvent(
            eventId: id,
            type: "test",
            source: "test",
            payload: [:],
            timestamp: Date()
        )
    }

    private func makeSubscription(
        id: String = UUID().uuidString,
        handler: @escaping @Sendable (EventBusEvent) async throws -> Void = { _ in }
    ) -> EventSubscription {
        EventSubscription(id: id, eventType: "test", handler: handler)
    }

    // MARK: - Concurrency Limit

    func testMaxConcurrentDeliveriesDefault() async {
        let manager = EventDeliveryManager(deadLetterQueue: makeDLQ())
        let limit = await manager.maxConcurrentDeliveries
        XCTAssertEqual(limit, 32)
    }

    func testMaxConcurrentDeliveriesCustom() async {
        let manager = EventDeliveryManager(
            maxConcurrentDeliveries: 5,
            deadLetterQueue: makeDLQ()
        )
        let limit = await manager.maxConcurrentDeliveries
        XCTAssertEqual(limit, 5)
    }

    func testMaxConcurrentDeliveriesClampedToMinOne() async {
        let manager = EventDeliveryManager(
            maxConcurrentDeliveries: 0,
            deadLetterQueue: makeDLQ()
        )
        let limit = await manager.maxConcurrentDeliveries
        XCTAssertEqual(limit, 1)
    }

    // MARK: - Delivery

    func testSingleDeliverySucceeds() async {
        let dlq = makeDLQ()
        let manager = EventDeliveryManager(
            maxAttempts: 1,
            deadLetterQueue: dlq
        )
        let delivered = expectation(description: "delivered")
        let sub = makeSubscription { _ in
            delivered.fulfill()
        }

        await manager.deliver(event: makeEvent(), to: sub)
        await fulfillment(of: [delivered], timeout: 5)

        let total = await manager.totalDelivered
        XCTAssertEqual(total, 1)
    }

    func testDeliveryFailureGoesToDLQ() async {
        let dlq = makeDLQ()
        let manager = EventDeliveryManager(
            maxAttempts: 1,
            baseDelayMs: 1,
            deadLetterQueue: dlq
        )
        let sub = makeSubscription { _ in
            throw NSError(domain: "test", code: 1)
        }

        await manager.deliver(event: makeEvent(), to: sub)

        // Aspetta che il task completi
        try? await Task.sleep(nanoseconds: 500_000_000)

        let failed = await manager.totalFailed
        XCTAssertEqual(failed, 1)

        let dlqSize = await dlq.count()
        XCTAssertEqual(dlqSize, 1)
    }

    func testDuplicateDeliveryIgnored() async {
        let dlq = makeDLQ()
        let manager = EventDeliveryManager(
            maxAttempts: 1,
            deadLetterQueue: dlq
        )
        var callCount = 0
        let sub = makeSubscription(id: "sub1") { _ in
            callCount += 1
        }
        let event = makeEvent(id: "evt1")

        // Consegna lo stesso evento allo stesso subscriber due volte
        await manager.deliver(event: event, to: sub)
        await manager.deliver(event: event, to: sub)

        try? await Task.sleep(nanoseconds: 500_000_000)

        // Il secondo deliver dovrebbe essere ignorato (stessa recordKey)
        let total = await manager.totalDelivered
        XCTAssertEqual(total, 1)
    }

    // MARK: - Metrics

    func testSuccessRateWithMixedResults() async {
        let dlq = makeDLQ()
        let manager = EventDeliveryManager(
            maxAttempts: 1,
            baseDelayMs: 1,
            deadLetterQueue: dlq
        )

        let successSub = makeSubscription(id: "s1") { _ in }
        let failSub = makeSubscription(id: "s2") { _ in
            throw NSError(domain: "test", code: 1)
        }

        await manager.deliver(event: makeEvent(id: "e1"), to: successSub)
        await manager.deliver(event: makeEvent(id: "e2"), to: failSub)

        try? await Task.sleep(nanoseconds: 1_000_000_000)

        let rate = await manager.successRate()
        XCTAssertEqual(rate, 0.5, accuracy: 0.01)
    }

    func testSuccessRateEmptyIsOne() async {
        let manager = EventDeliveryManager(deadLetterQueue: makeDLQ())
        let rate = await manager.successRate()
        XCTAssertEqual(rate, 1.0)
    }

    // MARK: - Cancel All

    func testCancelAllClearsPending() async {
        let manager = EventDeliveryManager(deadLetterQueue: makeDLQ())
        await manager.cancelAll()
        let pending = await manager.pendingCount()
        XCTAssertEqual(pending, 0)
    }

    // MARK: - Reset

    func testResetClearsAllState() async {
        let dlq = makeDLQ()
        let manager = EventDeliveryManager(
            maxAttempts: 1,
            deadLetterQueue: dlq
        )
        let sub = makeSubscription { _ in }
        await manager.deliver(event: makeEvent(), to: sub)

        try? await Task.sleep(nanoseconds: 500_000_000)

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

    // MARK: - Backoff Calculation

    func testBackoffFirstAttempt() async {
        let manager = EventDeliveryManager(
            baseDelayMs: 100,
            maxDelayMs: 5000,
            deadLetterQueue: makeDLQ()
        )
        let delay = await manager.calculateBackoff(attempt: 1)
        XCTAssertEqual(delay, 100) // base * 2^0 = 100
    }

    func testBackoffGrowsExponentially() async {
        let manager = EventDeliveryManager(
            baseDelayMs: 100,
            maxDelayMs: 50000,
            deadLetterQueue: makeDLQ()
        )
        let delay1 = await manager.calculateBackoff(attempt: 1)
        let delay3 = await manager.calculateBackoff(attempt: 3)
        XCTAssertGreaterThan(delay3, delay1)
    }

    func testBackoffClampedToMax() async {
        let manager = EventDeliveryManager(
            baseDelayMs: 100,
            maxDelayMs: 500,
            deadLetterQueue: makeDLQ()
        )
        let delay = await manager.calculateBackoff(attempt: 20)
        XCTAssertLessThanOrEqual(delay, 500)
    }
}
