import XCTest
@testable import CoderEngine

final class MCPSharedStatePostgresFallbackTests: XCTestCase {
    override func setUpWithError() throws {
        try super.setUpWithError()
        PersistenceTestSupport.resetPersistenceEnvironment()
        PersistenceTestSupport.enablePersistenceForTests()
    }

    override func tearDownWithError() throws {
        PersistenceTestSupport.resetPersistenceEnvironment()
        try super.tearDownWithError()
    }

    func testVerifiedFindingsReadsFromPostgresWhenLegacyFilesAreMissing() throws {
        let stableDate = PersistenceTestSupport.stableDate()
        let envelope = VerifiedFindingsSessionEnvelope(
            sessionId: "session-db",
            canonicalSnapshot: VerifiedFindingsCanonicalSnapshot(
                runs: [:],
                findings: [:],
                evidences: [:],
                verificationReports: [:],
                patchArtifacts: [:],
                revalidationReports: [:],
                commandLog: [],
                eventLog: [],
                traceLog: ["db-trace"]
            ),
            projectionSnapshot: VerifiedFindingsProjectionSnapshot(
                candidateQueue: [],
                verifiedQueue: [],
                duplicatesCount: 0,
                staleCandidatesCount: 0,
                traceSnippets: ["db-trace"]
            ),
            lastUpdatedAt: stableDate
        )

        MCPSharedState.writeVerifiedFindingsEnvelope(envelope)
        try? FileManager.default.removeItem(at: MCPSharedState.verifiedFindingsEnvelopeFilePath(sessionId: envelope.sessionId))
        try? FileManager.default.removeItem(at: MCPSharedState.verifiedFindingsCanonicalSnapshotFilePath(sessionId: envelope.sessionId))
        try? FileManager.default.removeItem(at: MCPSharedState.verifiedFindingsCheckpointFilePath(sessionId: envelope.sessionId))

        XCTAssertEqual(MCPSharedState.readVerifiedFindingsEnvelope(sessionId: envelope.sessionId), envelope)
        XCTAssertEqual(MCPSharedState.readVerifiedFindingsCheckpoint(sessionId: envelope.sessionId)?.traceCount, 1)
    }

    func testCodeReviewDeleteRemovesCanonicalPostgresState() {
        let snapshot = makeCodeReviewSnapshot(sessionId: "session-delete")

        MCPSharedState.writeCodeReviewSnapshot(snapshot)
        MCPSharedState.deleteCodeReviewSession(sessionId: snapshot.sessionId)

        XCTAssertNil(MCPSharedState.readCodeReviewSnapshot(sessionId: snapshot.sessionId))
    }

    func testBugHunterReadsFromPostgresWhenLegacyFileIsMissing() {
        let snapshot = MCPSharedBugHunterSnapshot(
            runId: "run-db",
            conversationId: UUID().uuidString.lowercased(),
            reviewSessionId: nil,
            sourceKind: .commit,
            triggerKind: .manual,
            gitRoot: "/tmp/repo",
            status: .running,
            startedAt: PersistenceTestSupport.stableDate(),
            lastUpdatedAt: PersistenceTestSupport.stableDate(1_700_000_100),
            lastMessage: "running"
        )

        MCPSharedState.writeBugHunterSnapshot(snapshot)
        try? FileManager.default.removeItem(at: MCPSharedState.bugHunterRunFilePath(runId: snapshot.runId))

        XCTAssertEqual(MCPSharedState.readBugHunterSnapshot(runId: snapshot.runId)?.runId, snapshot.runId)
    }

    func testPlanReadsFromPostgresWhenLegacyFileIsMissing() throws {
        let conversationId = UUID()

        MCPSharedState.writePlanSnapshotFromIDE(
            conversationId: conversationId,
            goal: "Persist plan",
            chosenPath: "db",
            steps: [["id": "1", "title": "Persist", "status": "done"]]
        )
        try? FileManager.default.removeItem(at: MCPSharedState.planStateFilePath)

        let latest = try XCTUnwrap(
            MCPSharedState.readLatestPlanSnapshotJSONObject(conversationId: conversationId)
        )
        XCTAssertEqual(latest["conversation_id"] as? String, conversationId.uuidString.lowercased())
        XCTAssertEqual(MCPSharedState.readPlanHistoryJSONObject(conversationId: conversationId, limit: 10).count, 1)
    }

    func testVerifiedFindingsDeltaPersistenceRemovesDeletedRowsAndReadsLatestEnvelope() throws {
        let store = PostgresPersistenceStore(postgresService: ManagedPostgresService())
        let original = makeVerifiedFindingsEnvelope(
            sessionId: "session-delta",
            findings: [
                makeVerifiedFinding(id: "finding-a", title: "Old A"),
                makeVerifiedFinding(id: "finding-b", title: "Old B"),
            ]
        )
        let updated = makeVerifiedFindingsEnvelope(
            sessionId: "session-delta",
            findings: [
                makeVerifiedFinding(id: "finding-b", title: "New B")
            ]
        )

        try store.persistVerifiedFindingsEnvelope(original)
        try store.persistVerifiedFindingsEnvelope(updated)

        let envelope = try XCTUnwrap(store.readVerifiedFindingsEnvelope(sessionId: "session-delta"))
        XCTAssertEqual(Set(envelope.canonicalSnapshot.findings.keys), ["finding-b"])
        XCTAssertEqual(envelope.canonicalSnapshot.findings["finding-b"]?.title, "New B")

        let findingsCount = try store.execute(
            sql: "SELECT COUNT(*) FROM findings WHERE session_id = 'session-delta';"
        ).trimmingCharacters(in: .whitespacesAndNewlines)
        XCTAssertEqual(findingsCount, "1")
    }

    private func makeCodeReviewSnapshot(sessionId: String) -> CodeReviewSessionSnapshot {
        CodeReviewSessionSnapshot(
            sessionId: sessionId,
            conversationId: UUID(),
            mutationSequence: 1,
            phase: .completed,
            stage: .completed,
            findings: [],
            events: [],
            config: .default,
            scope: ReviewSessionScope(type: .workspace, files: ["Sources/File.swift"]),
            workspacePath: "/tmp/repo",
            currentRound: 1,
            activeWorkerCount: 0,
            startedAt: PersistenceTestSupport.stableDate(),
            completedAt: PersistenceTestSupport.stableDate(1_700_000_100),
            analysisCompletedAt: PersistenceTestSupport.stableDate(1_700_000_050),
            lastError: nil,
            currentJobId: nil,
            lastTestStatus: .passed,
            lastUpdatedAt: PersistenceTestSupport.stableDate(1_700_000_200)
        )
    }

    private func makeVerifiedFindingsEnvelope(
        sessionId: String,
        findings: [VerifiedFinding]
    ) -> VerifiedFindingsSessionEnvelope {
        let canonical = VerifiedFindingsCanonicalSnapshot(
            runs: [:],
            findings: Dictionary(uniqueKeysWithValues: findings.map { ($0.id, $0) }),
            evidences: [:],
            verificationReports: [:],
            patchArtifacts: [:],
            revalidationReports: [:],
            commandLog: [],
            eventLog: [],
            traceLog: ["trace-\(sessionId)"]
        )
        return VerifiedFindingsSessionEnvelope(
            sessionId: sessionId,
            canonicalSnapshot: canonical,
            projectionSnapshot: VerifiedFindingsProjectionBuilder.build(from: canonical),
            lastUpdatedAt: PersistenceTestSupport.stableDate(1_700_000_300)
        )
    }

    private func makeVerifiedFinding(id: String, title: String) -> VerifiedFinding {
        VerifiedFinding(
            id: id,
            domain: .bug,
            title: title,
            summary: title,
            category: "correctness",
            severity: .medium,
            confidence: 0.8,
            status: .verified,
            filePath: "Sources/\(id).swift",
            originEntryPoint: .mainChat,
            findingFingerprint: "fp-\(id)",
            createdAt: PersistenceTestSupport.stableDate(),
            updatedAt: PersistenceTestSupport.stableDate(1_700_000_100)
        )
    }
}
