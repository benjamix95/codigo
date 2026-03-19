import XCTest
@testable import CoderIDE
@testable import CoderEngine

@MainActor
final class ReviewPatchWorkflowCloseFindingTests: XCTestCase {
    override func setUpWithError() throws {
        try super.setUpWithError()
        unsetenv("SOLOCODE_REVIEW_CORE_LIBRARY_PATH")
        unsetenv("SOLOCODE_REVIEW_CORE_FORCE_SWIFT")
        ReviewCoreBridge.resetForTests()
        VerifiedFindingsPatchExecutionService.resetForTests()
    }

    override func tearDownWithError() throws {
        VerifiedFindingsPatchExecutionService.resetForTests()
        ReviewCoreBridge.resetForTests()
        unsetenv("SOLOCODE_REVIEW_CORE_LIBRARY_PATH")
        unsetenv("SOLOCODE_REVIEW_CORE_FORCE_SWIFT")
        try super.tearDownWithError()
    }

    func testCloseFindingExecutionClosesMergedFinding() async throws {
        try requireReviewCore()
        VerifiedFindingsPatchExecutionService.startRuntimeHandler = { _, _, _, _, _ in
            makeReviewPatchRuntimeResponse(
                isError: false,
                runtimeId: "runtime-close-success",
                status: "running",
                currentStep: "close_finding"
            )
        }
        VerifiedFindingsPatchExecutionService.applyRuntimeResultHandler = { _, succeeded, errorMessage in
            makeReviewPatchRuntimeResponse(
                isError: false,
                errorMessage: errorMessage,
                runtimeId: "runtime-close-success",
                status: succeeded ? "completed" : "failed"
            )
        }

        let snapshot = CodeReviewSessionSnapshot(
            sessionId: "session-close",
            conversationId: nil,
            phase: .completed,
            stage: .completed,
            findings: [
                CodeReviewFinding(
                    id: "finding-close",
                    severity: .warning,
                    category: .correctness,
                    filePath: "Sources/File.swift",
                    message: "Issue",
                    status: .merged
                )
            ],
            events: [],
            config: .default,
            scope: nil,
            workspacePath: "/tmp/repo",
            currentRound: 1,
            activeWorkerCount: 0,
            startedAt: Date(),
            completedAt: Date(),
            analysisCompletedAt: Date(),
            lastError: nil,
            currentJobId: nil,
            lastTestStatus: .passed,
            lastUpdatedAt: Date()
        )

        let updated = try await VerifiedFindingsPatchExecutionService.execute(
            action: "close_finding",
            snapshot: snapshot,
            findingId: "finding-close",
            workspaceRoot: "/tmp/repo",
            preferredProviderId: nil,
            providerRegistry: ProviderRegistry()
        )

        XCTAssertEqual(updated.findings.first?.status, .closed)
        XCTAssertEqual(updated.events.last?.type, .outcomePublished)
    }

    func testCloseFindingFailsWhenRustPatchRuntimeIsDisabled() async {
        setenv("SOLOCODE_REVIEW_CORE_FORCE_SWIFT", "1", 1)
        ReviewCoreBridge.resetForTests()

        let snapshot = CodeReviewSessionSnapshot(
            sessionId: "session-close-disabled",
            conversationId: nil,
            phase: .completed,
            stage: .completed,
            findings: [
                CodeReviewFinding(
                    id: "finding-close",
                    severity: .warning,
                    category: .correctness,
                    filePath: "Sources/File.swift",
                    message: "Issue",
                    status: .merged
                )
            ],
            events: [],
            config: .default,
            scope: nil,
            workspacePath: "/tmp/repo",
            currentRound: 1,
            activeWorkerCount: 0,
            startedAt: Date(),
            completedAt: Date(),
            analysisCompletedAt: Date(),
            lastError: nil,
            currentJobId: nil,
            lastTestStatus: .passed,
            lastUpdatedAt: Date()
        )

        do {
            _ = try await VerifiedFindingsPatchExecutionService.execute(
                action: "close_finding",
                snapshot: snapshot,
                findingId: "finding-close",
                workspaceRoot: "/tmp/repo",
                preferredProviderId: nil,
                providerRegistry: ProviderRegistry()
            )
            XCTFail("Expected rust patch runtime failure")
        } catch {
            XCTAssertEqual(
                error as? ReviewPatchWorkflowError,
                .applyFailed("Rust patch runtime required but unavailable")
            )
        }
    }

    func testCloseFindingFailsWhenPatchRuntimeResultBridgeIsUnavailable() async {
        VerifiedFindingsPatchExecutionService.startRuntimeHandler = { _, _, _, _, _ in
            makeReviewPatchRuntimeResponse(
                isError: false,
                runtimeId: "runtime-close-1",
                status: "running",
                currentStep: "close_finding"
            )
        }
        VerifiedFindingsPatchExecutionService.applyRuntimeResultHandler = { _, _, _ in nil }

        let snapshot = CodeReviewSessionSnapshot(
            sessionId: "session-close-bridge-missing",
            conversationId: nil,
            phase: .completed,
            stage: .completed,
            findings: [
                CodeReviewFinding(
                    id: "finding-close",
                    severity: .warning,
                    category: .correctness,
                    filePath: "Sources/File.swift",
                    message: "Issue",
                    status: .merged
                )
            ],
            events: [],
            config: .default,
            scope: nil,
            workspacePath: "/tmp/repo",
            currentRound: 1,
            activeWorkerCount: 0,
            startedAt: Date(),
            completedAt: Date(),
            analysisCompletedAt: Date(),
            lastError: nil,
            currentJobId: nil,
            lastTestStatus: .passed,
            lastUpdatedAt: Date()
        )

        do {
            _ = try await VerifiedFindingsPatchExecutionService.execute(
                action: "close_finding",
                snapshot: snapshot,
                findingId: "finding-close",
                workspaceRoot: "/tmp/repo",
                preferredProviderId: nil,
                providerRegistry: ProviderRegistry()
            )
            XCTFail("Expected runtime result bridge failure")
        } catch {
            XCTAssertEqual(
                error as? ReviewPatchWorkflowError,
                .applyFailed("Rust patch runtime result bridge unavailable")
            )
        }
    }

    private func requireReviewCore() throws {
        let path = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Native/target/debug/libsolocode_rust_core.dylib")
            .path
        setenv("SOLOCODE_REVIEW_CORE_LIBRARY_PATH", path, 1)
        ReviewCoreBridge.resetForTests()
        guard ReviewCoreBridge.loadedState().loaded else {
            throw XCTSkip("Rust review core non disponibile in ambiente.")
        }
    }
}
