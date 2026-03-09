import XCTest
@testable import CoderEngine

final class VerifiedFindingsSharedStateTests: XCTestCase {
    override func setUpWithError() throws {
        try super.setUpWithError()
        try? FileManager.default.removeItem(at: MCPSharedState.codeReviewDirectoryPath)
        try? FileManager.default.removeItem(at: MCPSharedState.verifiedFindingsDirectoryPath)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: MCPSharedState.codeReviewDirectoryPath)
        try? FileManager.default.removeItem(at: MCPSharedState.verifiedFindingsDirectoryPath)
        try super.tearDownWithError()
    }

    func testVerifiedFindingsEnvelopeRoundTrip() {
        let canonical = VerifiedFindingsCanonicalSnapshot(
            runs: [:],
            findings: [:],
            evidences: [:],
            verificationReports: [:],
            patchArtifacts: [:],
            revalidationReports: [:],
            commandLog: [],
            eventLog: [],
            traceLog: ["trace"]
        )
        let envelope = VerifiedFindingsSessionEnvelope(
            sessionId: "session-1",
            canonicalSnapshot: canonical,
            projectionSnapshot: VerifiedFindingsProjectionSnapshot(
                candidateQueue: [],
                verifiedQueue: [],
                duplicatesCount: 0,
                staleCandidatesCount: 0,
                traceSnippets: ["trace"]
            )
        )

        MCPSharedState.writeVerifiedFindingsEnvelope(envelope)
        let loaded = MCPSharedState.readVerifiedFindingsEnvelope(sessionId: "session-1")

        XCTAssertEqual(loaded, envelope)
    }

    func testCodeReviewSnapshotLoadsVerifiedFindingsEnvelopeFallback() {
        let snapshot = CodeReviewSessionSnapshot(
            sessionId: "session-1",
            conversationId: UUID(),
            phase: .completed,
            stage: .completed,
            findings: [],
            events: [],
            config: .default,
            scope: nil,
            workspacePath: "/tmp/repo",
            currentRound: 0,
            activeWorkerCount: 0,
            startedAt: Date(),
            completedAt: Date(),
            analysisCompletedAt: Date(),
            lastError: nil,
            currentJobId: nil,
            lastTestStatus: .passed,
            verifiedFindings: nil,
            lastUpdatedAt: Date()
        )
        let canonical = VerifiedFindingsCanonicalSnapshot(
            runs: [:],
            findings: [:],
            evidences: [:],
            verificationReports: [:],
            patchArtifacts: [:],
            revalidationReports: [:],
            commandLog: [],
            eventLog: [],
            traceLog: []
        )
        let envelope = VerifiedFindingsSessionEnvelope(
            sessionId: "session-1",
            canonicalSnapshot: canonical,
            projectionSnapshot: VerifiedFindingsProjectionSnapshot(
                candidateQueue: [],
                verifiedQueue: [],
                duplicatesCount: 0,
                staleCandidatesCount: 0,
                traceSnippets: []
            )
        )

        MCPSharedState.writeCodeReviewSnapshot(snapshot)
        MCPSharedState.writeVerifiedFindingsEnvelope(envelope)
        let loaded = MCPSharedState.readCodeReviewSnapshot(sessionId: "session-1")

        XCTAssertEqual(loaded?.verifiedFindings, envelope)
    }
}
