import XCTest
@testable import CoderEngine

final class ReviewPipelineCoordinatorTests: XCTestCase {
    func testRunCompletesSessionWhenReviewScopeHasNoFiles() async throws {
        let workspacePath = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(
            at: workspacePath,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: workspacePath) }

        let sessionState = CodeReviewSessionState()
        let provider = SilentLLMProvider()
        let stream = AsyncThrowingStream<StreamEvent, Error> { continuation in
            Task {
                do {
                    try await ReviewPipelineCoordinator.shared.run(
                        prompt: "[REVIEW_SCOPE:uncommitted] Review the patch",
                        context: WorkspaceContext(workspacePath: workspacePath),
                        config: MultiSwarmReviewConfig(
                            maxWorkers: 1,
                            enabledPhases: .analysisOnly,
                            maxReviewRounds: 1
                        ),
                        analysisProvider: provider,
                        executionProvider: provider,
                        runtimeResolver: nil,
                        execController: nil,
                        fileLockCoordinator: FileLockCoordinator(),
                        sessionState: sessionState,
                        continuation: continuation
                    )
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }

        var didStart = false
        var didComplete = false
        for try await event in stream {
            switch event {
            case .started:
                didStart = true
            case .completed:
                didComplete = true
            default:
                break
            }
        }

        let snapshot = await sessionState.snapshot()
        XCTAssertTrue(didStart)
        XCTAssertTrue(didComplete)
        XCTAssertEqual(snapshot.phase, .completed)
        XCTAssertEqual(snapshot.stage, .completed)
        XCTAssertEqual(snapshot.scope?.files, [])
        XCTAssertNotNil(snapshot.startedAt)
        XCTAssertNotNil(snapshot.completedAt)
    }

    func testNoFilesAgainstRefMessageExplainsSingleCommitReinterpretation() {
        let message = ReviewPipelineCoordinator.noFilesAgainstRefMessage(
            againstRef: "1e72c30",
            normalizedInput: "1e72c30^..1e72c30",
            currentHeadRevision: nil,
            error: nil
        )

        XCTAssertTrue(message.contains("single-commit range"))
        XCTAssertTrue(message.contains("1e72c30^..1e72c30"))
    }

    func testNoFilesAgainstRefMessageMentionsHeadWhenCommitMatchesHead() {
        let message = ReviewPipelineCoordinator.noFilesAgainstRefMessage(
            againstRef: "1e72c30",
            normalizedInput: "1e72c30^..1e72c30",
            currentHeadRevision: "1e72c3016738d6e34ad2b79e0c4a1676ded3e234",
            error: nil
        )

        XCTAssertTrue(message.contains("current `HEAD` commit"))
    }

    func testRunEmitsSingleTextReplaceWhenWorkspaceScopeHasNoFiles() async throws {
        let workspacePath = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(
            at: workspacePath,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: workspacePath) }

        let sessionState = CodeReviewSessionState()
        let provider = SilentLLMProvider()
        let stream = AsyncThrowingStream<StreamEvent, Error> { continuation in
            Task {
                do {
                    try await ReviewPipelineCoordinator.shared.run(
                        prompt: "[REVIEW_SCOPE:workspace] Review repository architecture",
                        context: WorkspaceContext(workspacePath: workspacePath),
                        config: MultiSwarmReviewConfig(
                            maxWorkers: 1,
                            enabledPhases: .analysisOnly,
                            maxReviewRounds: 1
                        ),
                        analysisProvider: provider,
                        executionProvider: provider,
                        runtimeResolver: nil,
                        execController: nil,
                        fileLockCoordinator: FileLockCoordinator(),
                        sessionState: sessionState,
                        continuation: continuation
                    )
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }

        var textReplaceEvents: [String] = []
        for try await event in stream {
            if case .textReplace(let replacement) = event {
                textReplaceEvents.append(replacement)
            }
        }

        XCTAssertEqual(textReplaceEvents, ["No workspace source files found.\n"])
        let snapshot = await sessionState.snapshot()
        XCTAssertEqual(snapshot.scope?.type, .workspace)
    }
}

private final class SilentLLMProvider: LLMProvider, @unchecked Sendable {
    let id = "silent-review-test"
    let displayName = "Silent Review Test"

    func isAuthenticated() -> Bool { true }

    func send(
        prompt _: String,
        context _: WorkspaceContext,
        imageURLs _: [URL]?
    ) async throws -> AsyncThrowingStream<StreamEvent, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish()
        }
    }
}
