import XCTest
@testable import CoderEngine

final class BackpressureControllerTests: XCTestCase {

    // MARK: - Activation

    func testInitiallyInactive() async {
        let bp = BackpressureController()
        let active = await bp.isActive
        XCTAssertFalse(active)
    }

    func testActivateSignal() async {
        let bp = BackpressureController()
        await bp.activate(.workerQueueFull)

        let active = await bp.isActive
        XCTAssertTrue(active)
        let signals = await bp.currentSignals
        XCTAssertTrue(signals.contains(.workerQueueFull))
    }

    func testDeactivateSignal() async {
        let bp = BackpressureController()
        await bp.activate(.workerQueueFull)
        await bp.deactivate(.workerQueueFull)

        let active = await bp.isActive
        XCTAssertFalse(active)
    }

    func testDuplicateActivationCountsOnce() async {
        let bp = BackpressureController()
        await bp.activate(.workerQueueFull)
        await bp.activate(.workerQueueFull)

        let count = await bp.totalActivations
        XCTAssertEqual(count, 1)
    }

    // MARK: - Policies

    func testWorkerQueueFullPausesScheduling() async {
        let bp = BackpressureController()
        await bp.activate(.workerQueueFull)

        let shouldPause = await bp.shouldPauseScheduling
        XCTAssertTrue(shouldPause)
    }

    func testMemoryPressureReducesWorkers() async {
        let bp = BackpressureController()
        await bp.activate(.memoryPressure)

        let reduction = await bp.totalWorkerReduction
        XCTAssertEqual(reduction, 2)
    }

    func testEffectiveMaxWorkers() async {
        let bp = BackpressureController()
        await bp.activate(.memoryPressure)
        await bp.activate(.providerRateLimited)

        let effective = await bp.effectiveMaxWorkers(base: 4)
        XCTAssertEqual(effective, 1)
    }

    func testEffectiveMaxWorkersMinimumOne() async {
        let bp = BackpressureController()
        await bp.activate(.memoryPressure)

        let effective = await bp.effectiveMaxWorkers(base: 1)
        XCTAssertEqual(effective, 1)
    }

    // MARK: - Throttle

    func testMaxThrottleDelay() async {
        let bp = BackpressureController()
        await bp.activate(.providerRateLimited)
        await bp.activate(.workerQueueFull)

        let delay = await bp.maxThrottleDelayMs
        XCTAssertEqual(delay, 2000)
    }

    // MARK: - Reset

    func testReset() async {
        let bp = BackpressureController()
        await bp.activate(.workerQueueFull)
        await bp.reset()

        let active = await bp.isActive
        XCTAssertFalse(active)
        let count = await bp.totalActivations
        XCTAssertEqual(count, 0)
    }
}
