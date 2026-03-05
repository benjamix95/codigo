import XCTest
@testable import CoderEngine

// MARK: - Mock Probe Delegate

private final class MockProbeDelegate: HealthProbeDelegate, @unchecked Sendable {
    var results: [String: [HealthProbeResult]] = [:]
    var callCounts: [String: Int] = [:]

    func setResults(
        for providerId: String,
        results: [HealthProbeResult]
    ) {
        self.results[providerId] = results
        self.callCounts[providerId] = 0
    }

    func probe(
        providerId: String,
        timeoutMs: Int
    ) async -> HealthProbeResult {
        let idx = callCounts[providerId] ?? 0
        callCounts[providerId] = idx + 1

        guard let list = results[providerId], idx < list.count else {
            return HealthProbeResult(
                providerId: providerId,
                success: false,
                errorMessage: "No mock configured"
            )
        }
        return list[idx]
    }
}

// MARK: - Mock Notification Delegate

private final class MockNotificationDelegate:
    HealthCheckerDelegate, @unchecked Sendable
{
    var healthChanges: [(String, ProviderHealthStatus, ProviderHealthStatus)] =
        []
    var fallbackTriggers: [String] = []

    func onProviderHealthChanged(
        providerId: String,
        oldStatus: ProviderHealthStatus,
        newStatus: ProviderHealthStatus
    ) async {
        healthChanges.append((providerId, oldStatus, newStatus))
    }

    func onFallbackTriggered(unhealthyProviderId: String) async {
        fallbackTriggers.append(unhealthyProviderId)
    }
}

// MARK: - Tests

final class ProviderHealthCheckerTests: XCTestCase {

    private func makeEntry(
        id: String,
        health: ProviderHealthStatus = .healthy
    ) -> ProviderCapabilityEntry {
        ProviderCapabilityEntry(
            providerId: id,
            healthStatus: health
        )
    }

    private func makeConfig(
        unhealthyThreshold: Int = 3,
        healthyThreshold: Int = 1,
        autoFallback: Bool = true
    ) -> HealthCheckConfig {
        HealthCheckConfig(
            probeTimeoutMs: 5_000,
            unhealthyThreshold: unhealthyThreshold,
            healthyThreshold: healthyThreshold,
            autoFallbackOnUnhealthy: autoFallback
        )
    }

    // MARK: - Registration

    func testRegisterProvider_tracksState() async {
        let probe = MockProbeDelegate()
        let checker = ProviderHealthChecker(
            probeDelegate: probe, config: makeConfig()
        )
        let entry = makeEntry(id: "codex")
        await checker.registerProvider(entry)
        let count = await checker.registeredCount
        XCTAssertEqual(count, 1)
    }

    func testRegisterAll_tracksAllProviders() async {
        let probe = MockProbeDelegate()
        let checker = ProviderHealthChecker(
            probeDelegate: probe, config: makeConfig()
        )
        let matrix = ProviderCapabilityMatrix(providers: [
            makeEntry(id: "codex"),
            makeEntry(id: "claude"),
            makeEntry(id: "gemini"),
        ])
        await checker.registerAll(from: matrix)
        let count = await checker.registeredCount
        XCTAssertEqual(count, 3)
    }

    // MARK: - Probe Success

    func testProbe_success_keepsHealthy() async {
        let probe = MockProbeDelegate()
        probe.setResults(for: "codex", results: [
            HealthProbeResult(providerId: "codex", success: true),
        ])
        let checker = ProviderHealthChecker(
            probeDelegate: probe, config: makeConfig()
        )
        await checker.registerProvider(makeEntry(id: "codex"))
        await checker.probeProvider("codex")

        let state = await checker.state(for: "codex")
        XCTAssertEqual(state?.healthStatus, .healthy)
        XCTAssertEqual(state?.consecutiveFailures, 0)
    }

    // MARK: - Transition to Unhealthy

    func testProbe_consecutiveFailures_becomesUnhealthy() async {
        let probe = MockProbeDelegate()
        let notifier = MockNotificationDelegate()

        probe.setResults(for: "codex", results: [
            HealthProbeResult(providerId: "codex", success: false),
            HealthProbeResult(providerId: "codex", success: false),
            HealthProbeResult(providerId: "codex", success: false),
        ])

        let checker = ProviderHealthChecker(
            probeDelegate: probe,
            notificationDelegate: notifier,
            config: makeConfig(unhealthyThreshold: 3)
        )
        await checker.registerProvider(makeEntry(id: "codex"))

        await checker.probeProvider("codex")
        await checker.probeProvider("codex")

        let midState = await checker.state(for: "codex")
        XCTAssertEqual(midState?.healthStatus, .healthy)

        await checker.probeProvider("codex")

        let finalState = await checker.state(for: "codex")
        XCTAssertEqual(finalState?.healthStatus, .unhealthy)
        XCTAssertEqual(notifier.healthChanges.count, 1)
        XCTAssertEqual(
            notifier.healthChanges.first?.2, .unhealthy
        )
    }

    // MARK: - Recovery Flow

    func testProbe_recovery_unhealthyToRecoveringToHealthy() async {
        let probe = MockProbeDelegate()
        let notifier = MockNotificationDelegate()
        let config = makeConfig(
            unhealthyThreshold: 2, healthyThreshold: 2
        )

        probe.setResults(for: "codex", results: [
            HealthProbeResult(providerId: "codex", success: false),
            HealthProbeResult(providerId: "codex", success: false),
            HealthProbeResult(providerId: "codex", success: true),
            HealthProbeResult(providerId: "codex", success: true),
        ])

        let checker = ProviderHealthChecker(
            probeDelegate: probe,
            notificationDelegate: notifier,
            config: config
        )
        await checker.registerProvider(makeEntry(id: "codex"))

        await checker.probeProvider("codex")
        await checker.probeProvider("codex")
        let afterFail = await checker.state(for: "codex")
        XCTAssertEqual(afterFail?.healthStatus, .unhealthy)

        await checker.probeProvider("codex")
        let afterFirstSuccess = await checker.state(for: "codex")
        XCTAssertEqual(afterFirstSuccess?.healthStatus, .recovering)

        await checker.probeProvider("codex")
        let afterRecovery = await checker.state(for: "codex")
        XCTAssertEqual(afterRecovery?.healthStatus, .healthy)
    }

    // MARK: - Recovery Interrupted

    func testProbe_recoveringFailure_backToUnhealthy() async {
        let probe = MockProbeDelegate()
        let config = makeConfig(
            unhealthyThreshold: 1, healthyThreshold: 3
        )

        probe.setResults(for: "codex", results: [
            HealthProbeResult(providerId: "codex", success: false),
            HealthProbeResult(providerId: "codex", success: true),
            HealthProbeResult(providerId: "codex", success: false),
        ])

        let checker = ProviderHealthChecker(
            probeDelegate: probe, config: config
        )
        await checker.registerProvider(makeEntry(id: "codex"))

        await checker.probeProvider("codex")
        let afterFail = await checker.state(for: "codex")
        XCTAssertEqual(afterFail?.healthStatus, .unhealthy)

        await checker.probeProvider("codex")
        let afterSuccess = await checker.state(for: "codex")
        XCTAssertEqual(afterSuccess?.healthStatus, .recovering)

        await checker.probeProvider("codex")
        let afterRelapse = await checker.state(for: "codex")
        XCTAssertEqual(afterRelapse?.healthStatus, .unhealthy)
    }

    // MARK: - Fallback Trigger

    func testFallback_triggeredOnUnhealthy() async {
        let probe = MockProbeDelegate()
        let notifier = MockNotificationDelegate()
        let config = makeConfig(
            unhealthyThreshold: 1, autoFallback: true
        )

        probe.setResults(for: "codex", results: [
            HealthProbeResult(providerId: "codex", success: false),
        ])

        let checker = ProviderHealthChecker(
            probeDelegate: probe,
            notificationDelegate: notifier,
            config: config
        )
        await checker.registerProvider(makeEntry(id: "codex"))
        await checker.probeProvider("codex")

        XCTAssertEqual(notifier.fallbackTriggers, ["codex"])
        let fallbacks = await checker.totalFallbacksTriggered
        XCTAssertEqual(fallbacks, 1)
    }

    func testFallback_notTriggered_whenDisabled() async {
        let probe = MockProbeDelegate()
        let notifier = MockNotificationDelegate()
        let config = makeConfig(
            unhealthyThreshold: 1, autoFallback: false
        )

        probe.setResults(for: "codex", results: [
            HealthProbeResult(providerId: "codex", success: false),
        ])

        let checker = ProviderHealthChecker(
            probeDelegate: probe,
            notificationDelegate: notifier,
            config: config
        )
        await checker.registerProvider(makeEntry(id: "codex"))
        await checker.probeProvider("codex")

        XCTAssertTrue(notifier.fallbackTriggers.isEmpty)
    }

    // MARK: - IsAvailableForRouting

    func testIsAvailableForRouting_healthy() async {
        let probe = MockProbeDelegate()
        let checker = ProviderHealthChecker(
            probeDelegate: probe, config: makeConfig()
        )
        await checker.registerProvider(makeEntry(id: "codex"))
        let avail = await checker.isAvailableForRouting("codex")
        XCTAssertTrue(avail)
    }

    func testIsAvailableForRouting_unhealthy() async {
        let probe = MockProbeDelegate()
        let config = makeConfig(unhealthyThreshold: 1)

        probe.setResults(for: "codex", results: [
            HealthProbeResult(providerId: "codex", success: false),
        ])

        let checker = ProviderHealthChecker(
            probeDelegate: probe, config: config
        )
        await checker.registerProvider(makeEntry(id: "codex"))
        await checker.probeProvider("codex")

        let avail = await checker.isAvailableForRouting("codex")
        XCTAssertFalse(avail)
    }

    func testIsAvailableForRouting_unknownProvider() async {
        let probe = MockProbeDelegate()
        let checker = ProviderHealthChecker(
            probeDelegate: probe, config: makeConfig()
        )
        let avail = await checker.isAvailableForRouting("unknown")
        XCTAssertFalse(avail)
    }

    // MARK: - Run Probe Cycle

    func testRunProbeCycle_probesAllProviders() async {
        let probe = MockProbeDelegate()
        probe.setResults(for: "codex", results: [
            HealthProbeResult(providerId: "codex", success: true),
        ])
        probe.setResults(for: "claude", results: [
            HealthProbeResult(providerId: "claude", success: true),
        ])

        let checker = ProviderHealthChecker(
            probeDelegate: probe, config: makeConfig()
        )
        await checker.registerAll(from: ProviderCapabilityMatrix(
            providers: [
                makeEntry(id: "codex"),
                makeEntry(id: "claude"),
            ]
        ))
        await checker.runProbeCycle()

        let total = await checker.totalProbesExecuted
        XCTAssertEqual(total, 2)
    }

    // MARK: - Apply Health States

    func testApplyHealthStates_updatesMatrix() async {
        let probe = MockProbeDelegate()
        let config = makeConfig(unhealthyThreshold: 1)

        probe.setResults(for: "codex", results: [
            HealthProbeResult(providerId: "codex", success: false),
        ])
        probe.setResults(for: "claude", results: [
            HealthProbeResult(providerId: "claude", success: true),
        ])

        let checker = ProviderHealthChecker(
            probeDelegate: probe, config: config
        )
        let matrix = ProviderCapabilityMatrix(providers: [
            makeEntry(id: "codex"),
            makeEntry(id: "claude"),
        ])
        await checker.registerAll(from: matrix)
        await checker.runProbeCycle()

        let updated = await checker.applyHealthStates(to: matrix)

        let codexEntry = updated.provider(byId: "codex")
        XCTAssertEqual(codexEntry?.healthStatus, .unhealthy)

        let claudeEntry = updated.provider(byId: "claude")
        XCTAssertEqual(claudeEntry?.healthStatus, .healthy)
    }

    // MARK: - Error Rate Window

    func testErrorRate_calculatedFromWindow() async {
        let probe = MockProbeDelegate()
        probe.setResults(for: "codex", results: [
            HealthProbeResult(providerId: "codex", success: true),
            HealthProbeResult(providerId: "codex", success: false),
            HealthProbeResult(providerId: "codex", success: true),
            HealthProbeResult(providerId: "codex", success: false),
        ])

        let checker = ProviderHealthChecker(
            probeDelegate: probe, config: makeConfig()
        )
        await checker.registerProvider(makeEntry(id: "codex"))

        for _ in 0..<4 {
            await checker.probeProvider("codex")
        }

        let state = await checker.state(for: "codex")
        XCTAssertEqual(state?.errorRate ?? -1, 0.5, accuracy: 0.01)
    }

    // MARK: - Stats

    func testStats_tracked() async {
        let probe = MockProbeDelegate()
        let config = makeConfig(unhealthyThreshold: 1)

        probe.setResults(for: "codex", results: [
            HealthProbeResult(providerId: "codex", success: false),
        ])

        let notifier = MockNotificationDelegate()
        let checker = ProviderHealthChecker(
            probeDelegate: probe,
            notificationDelegate: notifier,
            config: config
        )
        await checker.registerProvider(makeEntry(id: "codex"))
        await checker.probeProvider("codex")

        let stats = await checker.stats
        XCTAssertEqual(stats.probes, 1)
        XCTAssertEqual(stats.statusChanges, 1)
        XCTAssertEqual(stats.fallbacks, 1)
    }

    // MARK: - ProviderHealthState

    func testProviderHealthState_errorRate_empty() {
        let state = ProviderHealthState(providerId: "test")
        XCTAssertEqual(state.errorRate, 0)
    }

    func testProviderHealthState_errorRate_allSuccess() {
        var state = ProviderHealthState(providerId: "test")
        state.errorRateWindow = [true, true, true]
        XCTAssertEqual(state.errorRate, 0)
    }

    func testProviderHealthState_errorRate_allFailure() {
        var state = ProviderHealthState(providerId: "test")
        state.errorRateWindow = [false, false, false]
        XCTAssertEqual(state.errorRate, 1.0)
    }

    // MARK: - Healthy/Unhealthy Provider Lists

    func testHealthyProviderIds() async {
        let probe = MockProbeDelegate()
        let config = makeConfig(unhealthyThreshold: 1)

        probe.setResults(for: "codex", results: [
            HealthProbeResult(providerId: "codex", success: false),
        ])
        probe.setResults(for: "claude", results: [
            HealthProbeResult(providerId: "claude", success: true),
        ])

        let checker = ProviderHealthChecker(
            probeDelegate: probe, config: config
        )
        await checker.registerAll(from: ProviderCapabilityMatrix(
            providers: [
                makeEntry(id: "codex"),
                makeEntry(id: "claude"),
            ]
        ))
        await checker.runProbeCycle()

        let healthy = await checker.healthyProviderIds
        let unhealthy = await checker.unhealthyProviderIds
        XCTAssertTrue(healthy.contains("claude"))
        XCTAssertFalse(healthy.contains("codex"))
        XCTAssertTrue(unhealthy.contains("codex"))
    }
}
