import XCTest
@testable import CoderEngine

final class ProviderRouterTests: XCTestCase {

    private let router = ProviderRouter()

    // MARK: - Helper Factory

    private func makeProvider(
        id: String,
        readonly: Bool = true,
        write: Bool = false,
        sandbox: Bool = false,
        nativeTools: Bool = true,
        health: ProviderHealthStatus = .healthy,
        errorRate: Double = 0
    ) -> ProviderCapabilityEntry {
        ProviderCapabilityEntry(
            providerId: id,
            supportsReadonlySubagent: readonly,
            supportsWriteSubagent: write,
            supportsWorkspaceSandbox: sandbox,
            supportsNativeTools: nativeTools,
            healthStatus: health,
            errorRateLastHour: errorRate
        )
    }

    private func makeMatrix(
        _ providers: [ProviderCapabilityEntry]
    ) -> ProviderCapabilityMatrix {
        ProviderCapabilityMatrix(providers: providers)
    }

    // MARK: - RequiredCapabilities Tests

    func testCapabilityMapping_coder_requiresWriteAndSandbox() {
        let caps = router.requiredCapabilities(for: .coder)
        XCTAssertTrue(caps.needsWriteSubagent)
        XCTAssertTrue(caps.needsWorkspaceSandbox)
        XCTAssertTrue(caps.needsNativeTools)
        XCTAssertFalse(caps.needsReadonlySubagent)
    }

    func testCapabilityMapping_reviewer_requiresReadonly() {
        let caps = router.requiredCapabilities(for: .reviewer)
        XCTAssertTrue(caps.needsReadonlySubagent)
        XCTAssertTrue(caps.needsNativeTools)
        XCTAssertFalse(caps.needsWriteSubagent)
    }

    func testCapabilityMapping_explorer_requiresReadonly() {
        let caps = router.requiredCapabilities(for: .explorer)
        XCTAssertTrue(caps.needsReadonlySubagent)
        XCTAssertFalse(caps.needsWriteSubagent)
    }

    func testCapabilityMapping_debugger_requiresWriteAndSandbox() {
        let caps = router.requiredCapabilities(for: .debugger)
        XCTAssertTrue(caps.needsWriteSubagent)
        XCTAssertTrue(caps.needsWorkspaceSandbox)
    }

    func testCapabilityMapping_testWriter_requiresWrite() {
        let caps = router.requiredCapabilities(for: .testWriter)
        XCTAssertTrue(caps.needsWriteSubagent)
        XCTAssertTrue(caps.needsWorkspaceSandbox)
    }

    func testCapabilityMapping_docWriter_requiresWrite() {
        let caps = router.requiredCapabilities(for: .docWriter)
        XCTAssertTrue(caps.needsWriteSubagent)
    }

    func testCapabilityMapping_securityAuditor() {
        let caps = router.requiredCapabilities(for: .securityAuditor)
        XCTAssertTrue(caps.needsReadonlySubagent)
        XCTAssertTrue(caps.needsNativeTools)
    }

    func testCapabilityMapping_planner() {
        let caps = router.requiredCapabilities(for: .planner)
        XCTAssertTrue(caps.needsReadonlySubagent)
    }

    // MARK: - RequiredCapabilities isSatisfied

    func testIsSatisfied_fullMatch() {
        let caps = RequiredCapabilities(
            needsWriteSubagent: true,
            needsWorkspaceSandbox: true
        )
        let provider = makeProvider(
            id: "p1", write: true, sandbox: true
        )
        XCTAssertTrue(caps.isSatisfied(by: provider))
    }

    func testIsSatisfied_partialMismatch() {
        let caps = RequiredCapabilities(
            needsWriteSubagent: true,
            needsWorkspaceSandbox: true
        )
        let provider = makeProvider(
            id: "p1", write: true, sandbox: false
        )
        XCTAssertFalse(caps.isSatisfied(by: provider))
    }

    func testIsSatisfied_noRequirements() {
        let caps = RequiredCapabilities()
        let provider = makeProvider(id: "p1")
        XCTAssertTrue(caps.isSatisfied(by: provider))
    }

    // MARK: - MatchScore

    func testMatchScore_allMatched() {
        let caps = RequiredCapabilities(
            needsWriteSubagent: true,
            needsWorkspaceSandbox: true
        )
        let provider = makeProvider(
            id: "p1", write: true, sandbox: true
        )
        XCTAssertEqual(caps.matchScore(for: provider), 1.0)
    }

    func testMatchScore_halfMatched() {
        let caps = RequiredCapabilities(
            needsWriteSubagent: true,
            needsWorkspaceSandbox: true
        )
        let provider = makeProvider(
            id: "p1", write: true, sandbox: false
        )
        XCTAssertEqual(caps.matchScore(for: provider), 0.5)
    }

    func testMatchScore_noneMatched() {
        let caps = RequiredCapabilities(
            needsWriteSubagent: true,
            needsWorkspaceSandbox: true
        )
        let provider = makeProvider(
            id: "p1", write: false, sandbox: false
        )
        XCTAssertEqual(caps.matchScore(for: provider), 0.0)
    }

    func testMatchScore_noRequirements_returns1() {
        let caps = RequiredCapabilities()
        let provider = makeProvider(id: "p1")
        XCTAssertEqual(caps.matchScore(for: provider), 1.0)
    }

    // MARK: - Select: Basic Routing

    func testSelect_singleProvider_fullMatch() {
        let provider = makeProvider(
            id: "codex", write: true, sandbox: true
        )
        let matrix = makeMatrix([provider])

        let result = router.select(matrix: matrix, role: .coder)
        switch result {
        case .success(let selection):
            XCTAssertEqual(selection.provider.providerId, "codex")
            XCTAssertEqual(selection.reason, .capabilityMatch)
            XCTAssertEqual(selection.candidatesCount, 1)
        case .failure(let error):
            XCTFail("Expected success, got \(error)")
        }
    }

    func testSelect_multipleProviders_bestScoreWins() {
        let p1 = makeProvider(
            id: "codex", write: true, sandbox: true,
            errorRate: 0.1
        )
        let p2 = makeProvider(
            id: "claude", write: true, sandbox: true,
            errorRate: 0.0
        )
        let matrix = makeMatrix([p1, p2])

        let result = router.select(matrix: matrix, role: .coder)
        switch result {
        case .success(let selection):
            XCTAssertEqual(selection.provider.providerId, "claude")
        case .failure(let error):
            XCTFail("Expected success, got \(error)")
        }
    }

    func testSelect_noProviders_returnsError() {
        let matrix = makeMatrix([])
        let result = router.select(matrix: matrix, role: .coder)
        switch result {
        case .success:
            XCTFail("Expected failure")
        case .failure(let error):
            XCTAssertEqual(error, .noProvidersAvailable)
        }
    }

    // MARK: - Select: Health Filtering

    func testSelect_allUnhealthy_returnsError() {
        let p1 = makeProvider(
            id: "codex", write: true, sandbox: true,
            health: .unhealthy
        )
        let matrix = makeMatrix([p1])

        let result = router.select(matrix: matrix, role: .coder)
        switch result {
        case .success:
            XCTFail("Expected failure")
        case .failure(let error):
            XCTAssertEqual(error, .allProvidersUnhealthy)
        }
    }

    func testSelect_unhealthyFiltered_healthySelected() {
        let unhealthy = makeProvider(
            id: "codex", write: true, sandbox: true,
            health: .unhealthy
        )
        let healthy = makeProvider(
            id: "claude", write: true, sandbox: true,
            health: .healthy
        )
        let matrix = makeMatrix([unhealthy, healthy])

        let result = router.select(matrix: matrix, role: .coder)
        switch result {
        case .success(let selection):
            XCTAssertEqual(selection.provider.providerId, "claude")
        case .failure(let error):
            XCTFail("Expected success, got \(error)")
        }
    }

    func testSelect_recoveringProviderNotExcluded() {
        let recovering = makeProvider(
            id: "codex", write: true, sandbox: true,
            health: .recovering
        )
        let matrix = makeMatrix([recovering])

        let result = router.select(matrix: matrix, role: .coder)
        switch result {
        case .success(let selection):
            XCTAssertEqual(selection.provider.providerId, "codex")
        case .failure(let error):
            XCTFail("Expected success, got \(error)")
        }
    }

    // MARK: - Select: Fallback to Reduced Capability

    func testSelect_noFullMatch_fallbackToReduced() {
        let readOnly = makeProvider(
            id: "gemini", readonly: true, write: false, sandbox: false
        )
        let matrix = makeMatrix([readOnly])

        let result = router.select(matrix: matrix, role: .coder)
        switch result {
        case .success(let selection):
            XCTAssertEqual(selection.provider.providerId, "gemini")
            XCTAssertEqual(selection.reason, .fallbackReduced)
        case .failure(let error):
            XCTFail("Expected fallback success, got \(error)")
        }
    }

    // MARK: - Select: Ranking with Latency and Cost

    func testSelect_rankingConsidersLatency() {
        let fast = makeProvider(
            id: "fast", write: true, sandbox: true
        )
        let slow = makeProvider(
            id: "slow", write: true, sandbox: true
        )
        let matrix = makeMatrix([fast, slow])
        let latencies = ["fast": 100.0, "slow": 20_000.0]

        let result = router.select(
            matrix: matrix, role: .coder, latencies: latencies
        )
        switch result {
        case .success(let selection):
            XCTAssertEqual(selection.provider.providerId, "fast")
        case .failure(let error):
            XCTFail("Expected success, got \(error)")
        }
    }

    func testSelect_rankingConsidersCost() {
        let cheap = makeProvider(
            id: "cheap", write: true, sandbox: true
        )
        let expensive = makeProvider(
            id: "expensive", write: true, sandbox: true
        )
        let matrix = makeMatrix([cheap, expensive])
        let costScores = ["cheap": 0.9, "expensive": 0.1]

        let result = router.select(
            matrix: matrix, role: .coder, costScores: costScores
        )
        switch result {
        case .success(let selection):
            XCTAssertEqual(selection.provider.providerId, "cheap")
        case .failure(let error):
            XCTFail("Expected success, got \(error)")
        }
    }

    // MARK: - ComputeScore

    func testComputeScore_perfectProvider() {
        let caps = RequiredCapabilities(
            needsWriteSubagent: true,
            needsWorkspaceSandbox: true
        )
        let provider = makeProvider(
            id: "perfect", write: true, sandbox: true,
            errorRate: 0
        )
        let score = router.computeScore(
            provider: provider,
            required: caps,
            latencies: ["perfect": 0],
            costScores: ["perfect": 1.0]
        )
        XCTAssertEqual(score, 1.0, accuracy: 0.001)
    }

    func testComputeScore_highErrorRate_lowerScore() {
        let caps = RequiredCapabilities(
            needsWriteSubagent: true
        )
        let good = makeProvider(
            id: "good", write: true, errorRate: 0.0
        )
        let bad = makeProvider(
            id: "bad", write: true, errorRate: 0.5
        )

        let scoreGood = router.computeScore(
            provider: good, required: caps,
            latencies: [:], costScores: [:]
        )
        let scoreBad = router.computeScore(
            provider: bad, required: caps,
            latencies: [:], costScores: [:]
        )
        XCTAssertGreaterThan(scoreGood, scoreBad)
    }

    // MARK: - Fallback Chain

    func testFallbackChain_firstAvailableSelected() {
        let p1 = makeProvider(
            id: "codex", write: true, sandbox: true
        )
        let p2 = makeProvider(
            id: "claude", write: true, sandbox: true
        )
        let matrix = makeMatrix([p1, p2])

        let result = router.selectWithFallback(
            matrix: matrix,
            role: .coder,
            fallbackChain: ["codex", "claude"]
        )
        switch result {
        case .success(let selection):
            XCTAssertEqual(selection.provider.providerId, "codex")
            XCTAssertEqual(selection.reason, .capabilityMatch)
        case .failure(let error):
            XCTFail("Expected success, got \(error)")
        }
    }

    func testFallbackChain_skipsFailedProviders() {
        let p1 = makeProvider(
            id: "codex", write: true, sandbox: true
        )
        let p2 = makeProvider(
            id: "claude", write: true, sandbox: true
        )
        let matrix = makeMatrix([p1, p2])

        let result = router.selectWithFallback(
            matrix: matrix,
            role: .coder,
            fallbackChain: ["codex", "claude"],
            failedProviders: ["codex"]
        )
        switch result {
        case .success(let selection):
            XCTAssertEqual(selection.provider.providerId, "claude")
            XCTAssertEqual(selection.reason, .fallbackReduced)
        case .failure(let error):
            XCTFail("Expected success, got \(error)")
        }
    }

    func testFallbackChain_skipsUnhealthyProvider() {
        let unhealthy = makeProvider(
            id: "codex", write: true, sandbox: true,
            health: .unhealthy
        )
        let healthy = makeProvider(
            id: "claude", write: true, sandbox: true,
            health: .healthy
        )
        let matrix = makeMatrix([unhealthy, healthy])

        let result = router.selectWithFallback(
            matrix: matrix,
            role: .coder,
            fallbackChain: ["codex", "claude"]
        )
        switch result {
        case .success(let selection):
            XCTAssertEqual(selection.provider.providerId, "claude")
        case .failure(let error):
            XCTFail("Expected success, got \(error)")
        }
    }

    func testFallbackChain_allExhausted_returnsError() {
        let matrix = makeMatrix([
            makeProvider(id: "codex"),
            makeProvider(id: "claude"),
        ])

        let result = router.selectWithFallback(
            matrix: matrix,
            role: .coder,
            fallbackChain: ["codex", "claude"],
            failedProviders: ["codex", "claude"]
        )
        switch result {
        case .success:
            XCTFail("Expected failure")
        case .failure(let error):
            if case .fallbackExhausted(let role, _) = error {
                XCTAssertEqual(role, .coder)
            } else {
                XCTFail("Expected fallbackExhausted error")
            }
        }
    }

    func testFallbackChain_providerNotInMatrix_skipped() {
        let p1 = makeProvider(id: "codex", write: true, sandbox: true)
        let matrix = makeMatrix([p1])

        let result = router.selectWithFallback(
            matrix: matrix,
            role: .coder,
            fallbackChain: ["unknown", "codex"]
        )
        switch result {
        case .success(let selection):
            XCTAssertEqual(selection.provider.providerId, "codex")
        case .failure(let error):
            XCTFail("Expected success, got \(error)")
        }
    }

    // MARK: - ProviderRoutingError Equatable

    func testProviderRoutingError_equatable() {
        XCTAssertEqual(
            ProviderRoutingError.noProvidersAvailable,
            ProviderRoutingError.noProvidersAvailable
        )
        XCTAssertEqual(
            ProviderRoutingError.allProvidersUnhealthy,
            ProviderRoutingError.allProvidersUnhealthy
        )
        XCTAssertNotEqual(
            ProviderRoutingError.noProvidersAvailable,
            ProviderRoutingError.allProvidersUnhealthy
        )
    }
}
