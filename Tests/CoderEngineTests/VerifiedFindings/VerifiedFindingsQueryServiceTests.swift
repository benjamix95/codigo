import XCTest
@testable import CoderEngine

final class VerifiedFindingsQueryServiceTests: XCTestCase {
    func testQueryServiceFiltersByDomainAndSourceOrigin() {
        let now = Date(timeIntervalSince1970: 1_700_002_500)
        let canonical = VerifiedFindingsCanonicalSnapshot(
            runs: [:],
            findings: [
                "bug-1": VerifiedFinding(
                    id: "bug-1",
                    domain: .bug,
                    title: "Crash path",
                    summary: "bug",
                    category: "correctness",
                    severity: .high,
                    confidence: 0.95,
                    status: .verified,
                    filePath: "Sources/App.swift",
                    originEntryPoint: .mcp,
                    sourceOrigin: "bugHunter",
                    findingFingerprint: "bug-1",
                    createdAt: now,
                    updatedAt: now
                ),
                "security-1": VerifiedFinding(
                    id: "security-1",
                    domain: .security,
                    title: "Missing authz",
                    summary: "security",
                    category: "security",
                    severity: .critical,
                    confidence: 0.99,
                    status: .verified,
                    filePath: "Sources/Auth.swift",
                    originEntryPoint: .mcp,
                    sourceOrigin: "securityAuditor",
                    findingFingerprint: "security-1",
                    createdAt: now,
                    updatedAt: now
                ),
            ],
            evidences: [:],
            verificationReports: [:],
            patchArtifacts: [:],
            revalidationReports: [:],
            commandLog: [],
            eventLog: [],
            traceLog: []
        )
        let resolved = VerifiedFindingsResolvedState(
            recovered: VerifiedFindingsRecoveredEnvelope(
                source: .embeddedSnapshot,
                envelope: VerifiedFindingsSessionEnvelope(
                    sessionId: "query-session",
                    canonicalSnapshot: canonical,
                    projectionSnapshot: VerifiedFindingsProjectionBuilder.build(from: canonical),
                    lastUpdatedAt: now
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
                sessionId: "query-session",
                checkpointSource: .embeddedSnapshot,
                eventSchemaVersion: 1,
                projectionSchemaVersion: 1,
                entitySchemaVersion: 1,
                findingCount: 2,
                eventCount: 0,
                traceCount: 0,
                candidateCount: 0,
                verifiedCount: 2,
                duplicatesCount: 0,
                staleCandidatesCount: 0
            )
        )

        let bugPayloads = VerifiedFindingsQueryService.listPayloads(
            resolved: resolved,
            query: VerifiedFindingsQuery(
                kind: .verified,
                domain: .bug,
                sourceOrigin: "bugHunter",
                includeSensitiveDetails: true
            )
        )
        let securityPayloads = VerifiedFindingsQueryService.listPayloads(
            resolved: resolved,
            query: VerifiedFindingsQuery(
                kind: .verified,
                domain: .security,
                sourceOrigin: "securityAuditor",
                includeSensitiveDetails: false
            )
        )

        XCTAssertEqual(bugPayloads.count, 1)
        XCTAssertEqual(bugPayloads.first?["id"], "bug-1")
        XCTAssertEqual(bugPayloads.first?["origin"], "bugHunter")

        XCTAssertEqual(securityPayloads.count, 1)
        XCTAssertEqual(securityPayloads.first?["id"], "security-1")
        XCTAssertEqual(securityPayloads.first?["origin"], "securityAuditor")
    }
}
