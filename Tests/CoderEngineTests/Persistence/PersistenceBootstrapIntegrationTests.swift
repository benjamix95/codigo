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
        let run = VerifiedPipelineRun(
            id: "run-import",
            status: .running,
            domainScope: [.bug],
            workspaceId: "/tmp/workspace",
            entryPoint: .mainChat,
            budgetPolicy: VerifiedRunBudgetPolicy(name: "bootstrap-import", allowRetryOnTransientFailure: true),
            maxDuration: 120,
            maxToolCalls: 8,
            maxVerificationAttempts: 2,
            maxPatchAttempts: 1,
            maxRevalidationAttempts: 1,
            timeoutAt: nil,
            cancelledAt: nil,
            cancelReason: nil,
            toolCallCount: 1,
            verificationAttemptCount: 0,
            patchAttemptCount: 0,
            revalidationAttemptCount: 0,
            isCancellable: true,
            createdAt: stableDate,
            updatedAt: stableDate
        )
        let envelope = VerifiedFindingsSessionEnvelope(
            sessionId: "session-import",
            canonicalSnapshot: VerifiedFindingsCanonicalSnapshot(
                runs: [run.id: run],
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
                evidences: [
                    "evidence-import": VerifiedEvidence(
                        id: "evidence-import",
                        findingId: "finding-import",
                        type: .toolOutput,
                        source: "legacy",
                        summary: "Legacy evidence placeholder",
                        payloadRef: "inline:finding-import",
                        originTool: "legacy-import",
                        originCommandId: "cmd-import",
                        originRunId: "run-import",
                        originStep: "bootstrap",
                        sourceType: .manualAssisted,
                        capturedAt: stableDate,
                        artifactRef: "snapshot:session-import",
                        hashOrFingerprint: "hash-evidence-import",
                        containsSensitiveData: false,
                        redactionApplied: false,
                        redactionReason: nil,
                        retentionClass: .standard,
                        visibilityLevel: .restricted,
                        createdAt: stableDate
                    )
                ],
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
        XCTAssertEqual(
            try store.readVerifiedFindingsEnvelope(sessionId: "session-import")?.canonicalSnapshot.runs[run.id],
            run
        )
        let reviewSessionReference = try store.execute(
            sql: "SELECT COALESCE(review_session_id, 'NULL') FROM pipeline_runs WHERE id = 'run-import';"
        ).trimmingCharacters(in: .whitespacesAndNewlines)
        XCTAssertEqual(reviewSessionReference, "NULL")
        let originRunReference = try store.execute(
            sql: "SELECT COALESCE(origin_run_id, 'NULL') FROM findings WHERE id = 'finding-import';"
        ).trimmingCharacters(in: .whitespacesAndNewlines)
        XCTAssertEqual(originRunReference, "run-import")
        let artifactPayloadRows = try store.execute(
            sql: "SELECT COUNT(*) FROM artifact_payloads WHERE id IN ('inline:finding-import', 'snapshot:session-import');"
        ).trimmingCharacters(in: .whitespacesAndNewlines)
        XCTAssertEqual(artifactPayloadRows, "2")
        let latestPlan = try XCTUnwrap(store.readLatestPlanSnapshot(conversationId: conversationId))
        XCTAssertEqual(latestPlan.snapshot.goal, "Import legacy plan")
    }
}
