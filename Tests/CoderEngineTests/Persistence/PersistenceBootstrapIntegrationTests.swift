import XCTest
@testable import CoderEngine

final class PersistenceBootstrapIntegrationTests: XCTestCase {
    override func setUpWithError() throws {
        try super.setUpWithError()
        PersistenceTestSupport.resetPersistenceEnvironment()
        PersistenceTestSupport.disablePersistenceForTests()
    }

    override func tearDownWithError() throws {
        PersistenceTestSupport.resetPersistenceEnvironment()
        try super.tearDownWithError()
    }

    func testBootstrapImportsLegacyVerifiedFindingsAndPlanState() throws {
        let stableDate = PersistenceTestSupport.stableDate()
        let conversationId = UUID()
        let envelope = VerifiedFindingsSessionEnvelope(
            sessionId: "session-import",
            canonicalSnapshot: VerifiedFindingsCanonicalSnapshot(
                runs: [:],
                findings: [
                    "finding-import": VerifiedFinding(
                        id: "finding-import",
                        domain: .bug,
                        title: "Imported finding",
                        summary: "Imported from legacy storage",
                        category: "correctness",
                        severity: .medium,
                        confidence: 0.88,
                        status: .verified,
                        filePath: "Sources/Imported.swift",
                        originEntryPoint: .mainChat,
                        findingFingerprint: "fp-import",
                        createdAt: stableDate,
                        updatedAt: stableDate
                    )
                ],
                evidences: [:],
                verificationReports: [:],
                patchArtifacts: [:],
                revalidationReports: [:],
                commandLog: [],
                eventLog: [],
                traceLog: ["trace-import"]
            ),
            projectionSnapshot: VerifiedFindingsProjectionSnapshot(
                candidateQueue: [],
                verifiedQueue: [],
                duplicatesCount: 0,
                staleCandidatesCount: 0,
                traceSnippets: ["trace-import"]
            ),
            lastUpdatedAt: stableDate
        )

        MCPSharedState.writeVerifiedFindingsEnvelope(envelope)
        MCPSharedState.writePlanSnapshotFromIDE(
            conversationId: conversationId,
            goal: "Import legacy plan",
            chosenPath: "postgres",
            steps: [["id": "1", "title": "Import", "status": "done"]]
        )

        PersistenceTestSupport.enablePersistenceForTests()
        let store = PostgresPersistenceStore(postgresService: ManagedPostgresService())
        let report = try PersistenceBootstrapService(store: store).bootstrapIfNeeded()

        XCTAssertTrue(report.importedLegacyData)
        XCTAssertEqual(try store.readVerifiedFindingsEnvelope(sessionId: "session-import"), envelope)
        let latestPlan = try XCTUnwrap(store.readLatestPlanSnapshot(conversationId: conversationId))
        XCTAssertEqual(latestPlan.snapshot.goal, "Import legacy plan")
    }
}
