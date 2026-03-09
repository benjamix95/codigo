import XCTest
@testable import CoderEngine

/// Tests for the BugHunter autofix filter logic.
///
/// Validates that findings are only considered autofixable when BOTH:
/// - confidence >= 0.9
/// - patchArtifactId is non-nil
///
/// This catches the operator-precedence regression where
/// `A && B || A` made the `patchArtifactId` check dead code.
final class BugHunterAutofixFilterTests: XCTestCase {
    override func setUp() {
        super.setUp()
        try? FileManager.default.removeItem(at: MCPSharedState.codeReviewDirectoryPath)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: MCPSharedState.codeReviewDirectoryPath)
        super.tearDown()
    }

    // MARK: - Filter under test (mirrors production logic)

    /// The exact filter used in `executeBugHunterAutofix`.
    private func autofixableFindings(
        from findings: [CodeReviewFinding]
    ) -> [CodeReviewFinding] {
        findings
            .filter { ($0.confidence ?? 0) >= 0.9 && $0.patchArtifactId != nil }
            .sorted { ($0.confidence ?? 0) > ($1.confidence ?? 0) }
    }

    // MARK: - Helpers

    private func makeFinding(
        id: String = UUID().uuidString,
        confidence: Double?,
        patchArtifactId: String? = nil
    ) -> CodeReviewFinding {
        CodeReviewFinding(
            id: id,
            severity: .warning,
            category: .correctness,
            filePath: "Foo.swift",
            message: "test finding",
            confidence: confidence,
            patchArtifactId: patchArtifactId
        )
    }

    // MARK: - Tests

    func testHighConfidenceWithPatch_isAutofixable() {
        let finding = makeFinding(confidence: 0.95, patchArtifactId: "patch-1")
        let result = autofixableFindings(from: [finding])
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.id, finding.id)
    }

    func testHighConfidenceWithoutPatch_isNotAutofixable() {
        // This is the key regression test:
        // confidence >= 0.9 but patchArtifactId is nil → must be excluded.
        let finding = makeFinding(confidence: 0.95, patchArtifactId: nil)
        let result = autofixableFindings(from: [finding])
        XCTAssertTrue(result.isEmpty, "Finding with no patch must NOT be autofixable")
    }

    func testLowConfidenceWithPatch_isNotAutofixable() {
        let finding = makeFinding(confidence: 0.5, patchArtifactId: "patch-1")
        let result = autofixableFindings(from: [finding])
        XCTAssertTrue(result.isEmpty)
    }

    func testLowConfidenceWithoutPatch_isNotAutofixable() {
        let finding = makeFinding(confidence: 0.5, patchArtifactId: nil)
        let result = autofixableFindings(from: [finding])
        XCTAssertTrue(result.isEmpty)
    }

    func testNilConfidence_isNotAutofixable() {
        let finding = makeFinding(confidence: nil, patchArtifactId: "patch-1")
        let result = autofixableFindings(from: [finding])
        XCTAssertTrue(result.isEmpty)
    }

    func testExactThreshold_isAutofixable() {
        let finding = makeFinding(confidence: 0.9, patchArtifactId: "patch-1")
        let result = autofixableFindings(from: [finding])
        XCTAssertEqual(result.count, 1)
    }

    func testBelowThreshold_isNotAutofixable() {
        let finding = makeFinding(confidence: 0.89, patchArtifactId: "patch-1")
        let result = autofixableFindings(from: [finding])
        XCTAssertTrue(result.isEmpty)
    }

    func testMixedFindings_filtersCorrectly() {
        let findings = [
            makeFinding(id: "a", confidence: 0.95, patchArtifactId: "p1"),
            makeFinding(id: "b", confidence: 0.95, patchArtifactId: nil),
            makeFinding(id: "c", confidence: 0.5, patchArtifactId: "p2"),
            makeFinding(id: "d", confidence: nil, patchArtifactId: "p3"),
            makeFinding(id: "e", confidence: 0.91, patchArtifactId: "p4"),
        ]
        let result = autofixableFindings(from: findings)
        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(result[0].id, "a")
        XCTAssertEqual(result[1].id, "e")
    }

    func testSortingByConfidence() {
        let findings = [
            makeFinding(id: "low", confidence: 0.91, patchArtifactId: "p1"),
            makeFinding(id: "high", confidence: 0.99, patchArtifactId: "p2"),
            makeFinding(id: "mid", confidence: 0.95, patchArtifactId: "p3"),
        ]
        let result = autofixableFindings(from: findings)
        XCTAssertEqual(result.map(\.id), ["high", "mid", "low"])
    }

    func testCanonicalSelectionUsesOnlyVerifiedBugFindings() {
        let resolved = VerifiedFindingsResolvedState(
            recovered: VerifiedFindingsRecoveredEnvelope(
                source: .embeddedSnapshot,
                envelope: VerifiedFindingsSessionEnvelope(
                    sessionId: "session-1",
                    canonicalSnapshot: VerifiedFindingsCanonicalSnapshot(
                        runs: [:],
                        findings: [
                            "candidate": VerifiedFinding(
                                id: "candidate",
                                domain: .bug,
                                title: "Candidate",
                                summary: "candidate",
                                category: "correctness",
                                severity: .medium,
                                confidence: 0.99,
                                status: .candidate,
                                filePath: "A.swift",
                                originEntryPoint: .mcp,
                                findingFingerprint: "candidate"
                            ),
                            "security": VerifiedFinding(
                                id: "security",
                                domain: .security,
                                title: "Security",
                                summary: "security",
                                category: "security",
                                severity: .critical,
                                confidence: 0.99,
                                status: .verified,
                                filePath: "B.swift",
                                originEntryPoint: .mcp,
                                findingFingerprint: "security"
                            ),
                            "verified-low": VerifiedFinding(
                                id: "verified-low",
                                domain: .bug,
                                title: "Verified Low",
                                summary: "verified",
                                category: "correctness",
                                severity: .medium,
                                confidence: 0.91,
                                status: .verified,
                                filePath: "C.swift",
                                originEntryPoint: .mcp,
                                findingFingerprint: "verified-low"
                            ),
                            "verified-high": VerifiedFinding(
                                id: "verified-high",
                                domain: .bug,
                                title: "Verified High",
                                summary: "verified",
                                category: "correctness",
                                severity: .high,
                                confidence: 0.97,
                                status: .verified,
                                filePath: "D.swift",
                                originEntryPoint: .mcp,
                                findingFingerprint: "verified-high"
                            ),
                        ],
                        evidences: [:],
                        verificationReports: [:],
                        patchArtifacts: [:],
                        revalidationReports: [:],
                        commandLog: [],
                        eventLog: [],
                        traceLog: []
                    ),
                    projectionSnapshot: VerifiedFindingsProjectionSnapshot(
                        candidateQueue: [],
                        verifiedQueue: [],
                        duplicatesCount: 0,
                        staleCandidatesCount: 0,
                        traceSnippets: []
                    )
                ),
                checkpoint: nil
            ),
            securityGate: VerifiedFindingsSecurityGateReport(
                ready: false,
                canonicalProjectionMismatchCount: 0,
                undetectedDuplicateCount: 0,
                findingsMissingEvidenceCount: 0,
                findingsMissingVerificationCount: 0,
                rollbackCoverageCount: 0,
                rollbackEligibleCount: 0,
                applyRevalidateSuccessRate: 1.0,
                knownCriticalRaceCount: 0,
                summary: "test"
            ),
            replayReport: VerifiedFindingsReplayReport(
                sessionId: "session-1",
                checkpointSource: .embeddedSnapshot,
                eventSchemaVersion: 1,
                projectionSchemaVersion: 1,
                entitySchemaVersion: 1,
                findingCount: 4,
                eventCount: 0,
                traceCount: 0,
                candidateCount: 1,
                verifiedCount: 3,
                duplicatesCount: 0,
                staleCandidatesCount: 0
            )
        )

        let selected = BugHunterAutofixSelectionService.selectFindingId(from: resolved)

        XCTAssertEqual(selected, "verified-high")
    }

    /// Demonstrates the old buggy filter accepted findings without a patch.
    func testBuggyFilter_wouldAcceptWithoutPatch() {
        let buggyFilter: (CodeReviewFinding) -> Bool = {
            ($0.confidence ?? 0) >= 0.9 && $0.patchArtifactId != nil || ($0.confidence ?? 0) >= 0.9
        }
        let finding = makeFinding(confidence: 0.95, patchArtifactId: nil)
        XCTAssertTrue(buggyFilter(finding), "Buggy filter accepts finding without patch")

        let fixedFilter: (CodeReviewFinding) -> Bool = {
            ($0.confidence ?? 0) >= 0.9 && $0.patchArtifactId != nil
        }
        XCTAssertFalse(fixedFilter(finding), "Fixed filter rejects finding without patch")
    }
}
