import XCTest
@testable import CoderEngine

final class ProviderCircuitBreakerTests: XCTestCase {

    // MARK: - Initial State

    func testInitialStateIsClosed() async {
        let cb = ProviderCircuitBreaker(providerId: "test")
        let phase = await cb.currentPhase
        XCTAssertEqual(phase, .closed)
    }

    func testInitialFailureCountIsZero() async {
        let cb = ProviderCircuitBreaker(providerId: "test")
        let count = await cb.failureCount
        XCTAssertEqual(count, 0)
    }

    // MARK: - Closed State

    func testClosedStateAllowsCalls() async {
        let cb = ProviderCircuitBreaker(providerId: "test")
        let decision = await cb.shouldAllow()
        if case .allow = decision {
            // expected
        } else {
            XCTFail("Expected .allow in closed state")
        }
    }

    func testSingleFailureDoesNotTrip() async {
        let cb = ProviderCircuitBreaker(
            providerId: "test",
            config: .init(maxConsecutiveFailures: 5)
        )
        await cb.recordFailure()
        let phase = await cb.currentPhase
        XCTAssertEqual(phase, .closed)
    }

    // MARK: - Tripping

    func testTripsAfterMaxConsecutiveFailures() async {
        let cb = ProviderCircuitBreaker(
            providerId: "test",
            config: .init(maxConsecutiveFailures: 3)
        )

        for _ in 0..<3 {
            await cb.recordFailure()
        }

        let phase = await cb.currentPhase
        XCTAssertEqual(phase, .open)
    }

    func testOpenStateRejectsCalls() async {
        let cb = ProviderCircuitBreaker(
            providerId: "test",
            config: .init(maxConsecutiveFailures: 1, cooldownSeconds: 60)
        )
        await cb.recordFailure()

        let decision = await cb.shouldAllow()
        if case .reject(let retryAfter) = decision {
            XCTAssertGreaterThan(retryAfter, 0)
        } else {
            XCTFail("Expected .reject in open state")
        }
    }

    // MARK: - Recovery

    func testSuccessResetsToClosed() async {
        let cb = ProviderCircuitBreaker(
            providerId: "test",
            config: .init(maxConsecutiveFailures: 2)
        )

        await cb.recordFailure()
        await cb.recordSuccess()

        let phase = await cb.currentPhase
        XCTAssertEqual(phase, .closed)
        let count = await cb.failureCount
        XCTAssertEqual(count, 0)
    }

    // MARK: - Cooldown and Half-Open (time-injected via `now:`)

    func testTransitionsToHalfOpenAfterCooldown() async {
        // cooldownSeconds clamped to max(1, ...) → usa 1s e simula il tempo
        let cb = ProviderCircuitBreaker(
            providerId: "test",
            config: .init(maxConsecutiveFailures: 1, cooldownSeconds: 1)
        )
        let t0 = Date()
        await cb.recordFailure(now: t0)

        let phase1 = await cb.currentPhase
        XCTAssertEqual(phase1, .open)

        // Simula 2 secondi dopo (> cooldown di 1s)
        let t1 = t0.addingTimeInterval(2)
        let decision = await cb.shouldAllow(now: t1)
        if case .allow = decision {
            // half-open consente una chiamata
        } else {
            XCTFail("Expected .allow after cooldown")
        }

        let phase2 = await cb.currentPhase
        XCTAssertEqual(phase2, .halfOpen)
    }

    func testHalfOpenSuccessRecoversToClosed() async {
        let cb = ProviderCircuitBreaker(
            providerId: "test",
            config: .init(maxConsecutiveFailures: 1, cooldownSeconds: 1)
        )
        let t0 = Date()
        await cb.recordFailure(now: t0)

        let t1 = t0.addingTimeInterval(2)
        _ = await cb.shouldAllow(now: t1) // transition to halfOpen

        await cb.recordSuccess()

        let phase = await cb.currentPhase
        XCTAssertEqual(phase, .closed)
    }

    func testHalfOpenFailureReturnsToOpen() async {
        let cb = ProviderCircuitBreaker(
            providerId: "test",
            config: .init(maxConsecutiveFailures: 1, cooldownSeconds: 1)
        )
        let t0 = Date()
        await cb.recordFailure(now: t0)

        let t1 = t0.addingTimeInterval(2)
        _ = await cb.shouldAllow(now: t1) // transition to halfOpen

        await cb.recordFailure(now: t1)

        let phase = await cb.currentPhase
        XCTAssertEqual(phase, .open)
    }

    // MARK: - Exponential Cooldown

    func testCooldownDoublesOnHalfOpenFailure() async {
        let cb = ProviderCircuitBreaker(
            providerId: "test",
            config: .init(
                maxConsecutiveFailures: 1,
                cooldownSeconds: 1,
                maxCooldownSeconds: 120
            )
        )

        let t0 = Date()
        // Trip
        await cb.recordFailure(now: t0)

        // Dopo cooldown di 1s → halfOpen
        let t1 = t0.addingTimeInterval(2)
        _ = await cb.shouldAllow(now: t1)

        // Fail in half-open → back to open, cooldown raddoppia a 2s
        await cb.recordFailure(now: t1)

        // Subito dopo: dovrebbe rifiutare con retryAfter > 1
        let t2 = t1.addingTimeInterval(0.1)
        let decision = await cb.shouldAllow(now: t2)
        if case .reject(let retryAfter) = decision {
            XCTAssertGreaterThan(retryAfter, 1.0)
        } else {
            XCTFail("Expected .reject with doubled cooldown")
        }
    }

    // MARK: - Registry

    func testRegistryReturnsSameInstanceForSameProvider() async {
        let registry = ProviderCircuitBreakerRegistry()
        let cb1 = await registry.breaker(for: "anthropic")
        let cb2 = await registry.breaker(for: "anthropic")
        XCTAssertTrue(cb1 === cb2)
    }

    func testRegistryReturnsDifferentInstancesForDifferentProviders() async {
        let registry = ProviderCircuitBreakerRegistry()
        let cb1 = await registry.breaker(for: "anthropic")
        let cb2 = await registry.breaker(for: "openai")
        XCTAssertFalse(cb1 === cb2)
    }
}
