import XCTest
@testable import CoderEngine

final class PipelineMetricsTests: XCTestCase {

    // MARK: - MetricKey

    func testMetricKey_has32Cases() {
        XCTAssertEqual(MetricKey.allCases.count, 32)
    }

    func testMetricKey_rawValues_areSnakeCase() {
        for key in MetricKey.allCases {
            XCTAssertTrue(
                key.rawValue.contains("_"),
                "\(key.rawValue) should be snake_case"
            )
        }
    }

    // MARK: - Record & Query

    func testRecord_andRetrieve() async {
        let m = PipelineMetrics()
        await m.record(key: .jobDurationMs, value: 1500)
        let samples = await m.samples(forKey: .jobDurationMs)
        XCTAssertEqual(samples.count, 1)
        XCTAssertEqual(samples.first?.value, 1500)
    }

    func testRecord_multipleSamples() async {
        let m = PipelineMetrics()
        await m.record(key: .taskRetryCount, value: 1)
        await m.record(key: .taskRetryCount, value: 2)
        await m.record(key: .taskRetryCount, value: 3)
        let count = await m.count()
        XCTAssertEqual(count, 3)
    }

    func testSamples_forJob_filters() async {
        let m = PipelineMetrics()
        await m.record(key: .lockWaitMs, value: 10, jobId: "j1")
        await m.record(key: .lockWaitMs, value: 20, jobId: "j2")
        let j1 = await m.samples(forJob: "j1")
        XCTAssertEqual(j1.count, 1)
        XCTAssertEqual(j1.first?.value, 10)
    }

    func testSamples_forJob_withKey() async {
        let m = PipelineMetrics()
        await m.record(key: .lockWaitMs, value: 10, jobId: "j1")
        await m.record(key: .patchRejectRate, value: 0.5, jobId: "j1")
        let filtered = await m.samples(forJob: "j1", key: .lockWaitMs)
        XCTAssertEqual(filtered.count, 1)
    }

    // MARK: - Latest Value

    func testLatestValue_returnsLast() async {
        let m = PipelineMetrics()
        await m.record(key: .providerLatencyMs, value: 100)
        await m.record(key: .providerLatencyMs, value: 200)
        let latest = await m.latestValue(forKey: .providerLatencyMs)
        XCTAssertEqual(latest, 200)
    }

    func testLatestValue_nilIfEmpty() async {
        let m = PipelineMetrics()
        let val = await m.latestValue(forKey: .contextSizeTokens)
        XCTAssertNil(val)
    }

    // MARK: - Average

    func testAverage_computesCorrectly() async {
        let m = PipelineMetrics()
        await m.record(key: .patchSizeLines, value: 10)
        await m.record(key: .patchSizeLines, value: 20)
        await m.record(key: .patchSizeLines, value: 30)
        let avg = await m.average(forKey: .patchSizeLines)
        XCTAssertEqual(avg, 20.0)
    }

    func testAverage_nilIfEmpty() async {
        let m = PipelineMetrics()
        let avg = await m.average(forKey: .tokensInOut)
        XCTAssertNil(avg)
    }

    // MARK: - Snapshot

    func testSnapshot_containsLatestPerKey() async {
        let m = PipelineMetrics()
        await m.record(key: .rollbackCount, value: 1)
        await m.record(key: .rollbackSuccessRate, value: 100)
        await m.record(key: .rollbackCount, value: 3)
        let snap = await m.snapshot()
        XCTAssertEqual(snap[.rollbackCount], 3)
        XCTAssertEqual(snap[.rollbackSuccessRate], 100)
    }

    // MARK: - SLO Check

    func testSLO_noViolation_whenMet() async {
        let m = PipelineMetrics(sloDefinitions: [
            SLODefinition(
                key: .rollbackSuccessRate,
                threshold: 100, isUpperBound: false
            ),
        ])
        await m.record(key: .rollbackSuccessRate, value: 100)
        let violations = await m.checkSLOs()
        XCTAssertTrue(violations.isEmpty)
    }

    func testSLO_violation_whenNotMet() async {
        let m = PipelineMetrics(sloDefinitions: [
            SLODefinition(
                key: .rollbackSuccessRate,
                threshold: 100, isUpperBound: false
            ),
        ])
        await m.record(key: .rollbackSuccessRate, value: 90)
        let violations = await m.checkSLOs()
        XCTAssertEqual(violations.count, 1)
        XCTAssertEqual(violations.first?.actualValue, 90)
    }

    func testSLO_upperBound_violation() async {
        let m = PipelineMetrics(sloDefinitions: [
            SLODefinition(
                key: .circuitBreakerTripCount,
                threshold: 5, isUpperBound: true
            ),
        ])
        await m.record(key: .circuitBreakerTripCount, value: 10)
        let violations = await m.checkSLOs()
        XCTAssertEqual(violations.count, 1)
    }

    func testSLO_upperBound_ok() async {
        let m = PipelineMetrics(sloDefinitions: [
            SLODefinition(
                key: .circuitBreakerTripCount,
                threshold: 5, isUpperBound: true
            ),
        ])
        await m.record(key: .circuitBreakerTripCount, value: 3)
        let violations = await m.checkSLOs()
        XCTAssertTrue(violations.isEmpty)
    }

    // MARK: - SLODefinition

    func testSLODefinition_isMet_upperBound() {
        let slo = SLODefinition(
            key: .lockWaitMs, threshold: 100, isUpperBound: true
        )
        XCTAssertTrue(slo.isMet(by: 50))
        XCTAssertTrue(slo.isMet(by: 100))
        XCTAssertFalse(slo.isMet(by: 101))
    }

    func testSLODefinition_isMet_lowerBound() {
        let slo = SLODefinition(
            key: .rollbackSuccessRate, threshold: 95, isUpperBound: false
        )
        XCTAssertTrue(slo.isMet(by: 100))
        XCTAssertTrue(slo.isMet(by: 95))
        XCTAssertFalse(slo.isMet(by: 94))
    }

    // MARK: - Reset

    func testReset_clearsAll() async {
        let m = PipelineMetrics()
        await m.record(key: .jobDurationMs, value: 500)
        await m.reset()
        let count = await m.count()
        XCTAssertEqual(count, 0)
    }

    // MARK: - MetricSample

    func testMetricSample_defaultTimestamp() {
        let s = MetricSample(key: .lockWaitMs, value: 42)
        XCTAssertEqual(s.value, 42)
        XCTAssertNil(s.jobId)
        XCTAssertTrue(s.labels.isEmpty)
    }
}
