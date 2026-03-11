import XCTest
@testable import CoderEngine

final class HistoricalFindingsQueryServiceTests: XCTestCase {
    override func setUpWithError() throws {
        try super.setUpWithError()
        PersistenceTestSupport.resetPersistenceEnvironment()
        PersistenceTestSupport.enablePersistenceForTests()
    }

    override func tearDownWithError() throws {
        PersistenceTestSupport.resetPersistenceEnvironment()
        try super.tearDownWithError()
    }

    func testHistoricalFindingsReadWorkspaceScopedHistoryAndResumeEligibility() throws {
        let stableDate = PersistenceTestSupport.stableDate()
        let store = PostgresPersistenceStore(postgresService: ManagedPostgresService())
        let openPatch = ReviewPatchArtifact(
            id: "patch-open",
            findingId: "finding-open",
            patchText: "diff --git a/App.swift b/App.swift",
            diffPreview: "@@",
            touchedFiles: ["Sources/App.swift"],
            status: .verified,
            verifyStatus: .verified,
            createdAt: stableDate,
            updatedAt: stableDate
        )
        let closedPatch = ReviewPatchArtifact(
            id: "patch-closed",
            findingId: "finding-closed",
            patchText: "diff --git a/Auth.swift b/Auth.swift",
            diffPreview: "@@",
            touchedFiles: ["Sources/Auth.swift"],
            status: .applied,
            verifyStatus: .verified,
            validationRunId: "validation-1",
            validationStatus: .passed,
            validationSummary: "validated",
            createdAt: stableDate.addingTimeInterval(10),
            updatedAt: stableDate.addingTimeInterval(10)
        )
        let snapshot = CodeReviewSessionSnapshot(
            sessionId: "history-session",
            conversationId: UUID(),
            phase: .completed,
            stage: .completed,
            findings: [
                CodeReviewFinding(
                    id: "finding-open",
                    severity: .warning,
                    category: .correctness,
                    origin: .bugHunter,
                    filePath: "Sources/App.swift",
                    lineNumber: 12,
                    message: "Retry may emit terminal event twice",
                    status: .patchReady,
                    verificationReport: "Verified with retry sequence",
                    verifiedAt: stableDate,
                    patchArtifactId: "patch-open",
                    createdAt: stableDate
                ),
                CodeReviewFinding(
                    id: "finding-closed",
                    severity: .warning,
                    category: .security,
                    origin: .securityAuditor,
                    filePath: "Sources/Auth.swift",
                    lineNumber: 30,
                    message: "Missing auth guard",
                    status: .patchApplied,
                    verificationReport: "Verified on direct code path",
                    verifiedAt: stableDate.addingTimeInterval(10),
                    patchArtifactId: "patch-closed",
                    createdAt: stableDate.addingTimeInterval(10)
                ),
            ],
            patches: [openPatch, closedPatch],
            events: [
                .findingAdded(findingId: "finding-open", severity: "warning", filePath: "Sources/App.swift"),
                .patchPrepared(patchId: "patch-open", findingId: "finding-open"),
                .findingAdded(findingId: "finding-closed", severity: "warning", filePath: "Sources/Auth.swift"),
                .findingFixApplied(findingId: "finding-closed"),
            ],
            config: .default,
            scope: ReviewSessionScope(type: .workspace, files: ["Sources/App.swift", "Sources/Auth.swift"]),
            workspacePath: "/tmp/history-workspace",
            currentRound: 1,
            activeWorkerCount: 0,
            startedAt: stableDate,
            completedAt: stableDate.addingTimeInterval(20),
            analysisCompletedAt: stableDate.addingTimeInterval(5),
            lastError: nil,
            currentJobId: "job-history",
            lastTestStatus: .passed,
            lastUpdatedAt: stableDate.addingTimeInterval(20)
        )

        try store.persistCodeReviewSnapshot(snapshot)

        let records = try store.readHistoricalFindings(
            query: HistoricalFindingsQuery(workspaceId: "/tmp/history-workspace")
        )

        XCTAssertEqual(records.map(\.findingId), ["finding-open", "finding-closed"])
        XCTAssertEqual(records.first?.resumeEligible, true)
        XCTAssertEqual(records.first?.patchApplyStatus, .notApplied)
        XCTAssertEqual(records.last?.resumeEligible, false)
        XCTAssertEqual(records.last?.revalidationVerdict, .fixedVerified)
        XCTAssertFalse(records.first?.timeline.isEmpty ?? true)
    }

    func testHistoricalFindingsShapeWithRustWhenLibraryIsAvailable() throws {
        let path = reviewCoreLibraryPath(from: #filePath)
        guard FileManager.default.fileExists(atPath: path) else {
            throw XCTSkip("Libreria review core Rust non disponibile")
        }
        setenv("SOLOCODE_REVIEW_CORE_LIBRARY_PATH", path, 1)
        unsetenv("SOLOCODE_REVIEW_CORE_FORCE_SWIFT")
        defer {
            unsetenv("SOLOCODE_REVIEW_CORE_LIBRARY_PATH")
            ReviewCoreBridge.resetForTests()
        }

        ReviewCoreBridge.resetForTests()
        let records = [
            HistoricalFindingRecord(
                findingId: "resolved",
                sessionId: "s1",
                workspaceId: "/tmp/workspace",
                domain: .bug,
                severity: .medium,
                title: "Resolved",
                summary: "done",
                status: .fixedVerified,
                filePath: "A.swift",
                lineStart: 10,
                sourceOrigin: nil,
                closedReason: nil,
                patchId: nil,
                patchApplyStatus: nil,
                revalidationReportId: nil,
                revalidationVerdict: nil,
                createdAt: Date(timeIntervalSince1970: 1),
                updatedAt: Date(timeIntervalSince1970: 1),
                resolvedAt: nil,
                resumeEligible: false,
                timeline: []
            ),
            HistoricalFindingRecord(
                findingId: "open",
                sessionId: "s2",
                workspaceId: "/tmp/workspace",
                domain: .bug,
                severity: .medium,
                title: "Open",
                summary: "todo",
                status: .verified,
                filePath: "B.swift",
                lineStart: 20,
                sourceOrigin: nil,
                closedReason: nil,
                patchId: nil,
                patchApplyStatus: nil,
                revalidationReportId: nil,
                revalidationVerdict: nil,
                createdAt: Date(timeIntervalSince1970: 2),
                updatedAt: Date(timeIntervalSince1970: 2),
                resolvedAt: nil,
                resumeEligible: true,
                timeline: []
            ),
        ]

        let request = ReviewCoreHistoricalShapeRequest(schemaVersion: 1, records: records)
        let response: ReviewCoreHistoricalShapeBridgeResponse? = ReviewCoreBridge.call(
            functionName: "review_core_shape_historical_findings",
            request: request
        )

        XCTAssertEqual(response?.mergedHistory?.first?.findingId, "open")
    }
}

private func reviewCoreLibraryPath(from sourceFile: StaticString) -> String {
    let sourceURL = URL(fileURLWithPath: "\(sourceFile)")
    return sourceURL
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("Native/RustCore/build/lib/libsolocode_rust_core.dylib")
        .path
}
