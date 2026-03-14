import XCTest
@testable import CoderEngine

final class ReviewPipelineCoordinatorTests: XCTestCase {
    override func setUpWithError() throws {
        try super.setUpWithError()
        let path = reviewCoreLibraryPath(from: #filePath)
        if FileManager.default.fileExists(atPath: path) {
            setenv("SOLOCODE_REVIEW_CORE_LIBRARY_PATH", path, 1)
            unsetenv("SOLOCODE_REVIEW_CORE_FORCE_SWIFT")
        }
        ReviewCoreBridge.resetForTests()
    }

    override func tearDownWithError() throws {
        unsetenv("SOLOCODE_REVIEW_CORE_LIBRARY_PATH")
        unsetenv("SOLOCODE_REVIEW_CORE_FORCE_SWIFT")
        ReviewCoreBridge.resetForTests()
        try super.tearDownWithError()
    }

    func testRunCompletesSessionWhenReviewScopeHasNoFiles() async throws {
        guard ReviewCoreBridge.loadedState().loaded else {
            throw XCTSkip("Review core Rust non disponibile in build/lib")
        }
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
        guard ReviewCoreBridge.loadedState().loaded else {
            throw XCTSkip("Review core Rust non disponibile in build/lib")
        }
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

    func testRunFailsExplicitlyWhenRustReviewPipelineIsDisabled() async {
        setenv("SOLOCODE_REVIEW_CORE_FORCE_SWIFT", "1", 1)
        defer {
            unsetenv("SOLOCODE_REVIEW_CORE_FORCE_SWIFT")
            ReviewCoreBridge.resetForTests()
        }
        ReviewCoreBridge.resetForTests()

        let workspacePath = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(
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
                    XCTFail("Expected Rust pipeline requirement failure")
                } catch {
                    guard case CodeReviewMultiSwarmProvider.ReviewPipelineError.analysisTransportFailed(let reason) = error else {
                        return XCTFail("Unexpected error: \(error)")
                    }
                    XCTAssertEqual(reason, "Rust review pipeline required but unavailable.")
                    continuation.finish()
                }
            }
        }

        do {
            for try await _ in stream {
            }
        } catch {
            XCTFail("Unexpected stream error: \(error)")
        }
    }

    func testCurrentRuntimeResourcesUsesResolverOverride() async {
        let sessionState = CodeReviewSessionState(
            config: SessionConfig(maxWorkers: 4, maxRounds: 2, analysisBackend: "gemini-cli", executionBackend: "claude-cli")
        )
        let staticProvider = SilentLLMProvider()
        let overrideProvider = SilentLLMProvider()
        let config = MultiSwarmReviewConfig(maxWorkers: 1, enabledPhases: .analysisOnly, maxReviewRounds: 1)

        let resources = await ReviewPipelineCoordinator.shared.currentRuntimeResources(
            staticConfig: config,
            staticAnalysisProvider: staticProvider,
            staticExecutionProvider: staticProvider,
            runtimeResolver: { sessionConfig in
                guard sessionConfig.analysisBackend == "gemini-cli" else { return nil }
                return CodeReviewRuntimeResources(
                    config: MultiSwarmReviewConfig(maxWorkers: 4, enabledPhases: .analysisAndExecution, maxReviewRounds: 2, analysisBackend: "gemini-cli", executionBackend: "claude-cli"),
                    analysisProvider: overrideProvider,
                    executionProvider: overrideProvider
                )
            },
            sessionState: sessionState
        )

        XCTAssertEqual(resources.config.maxWorkers, 4)
        XCTAssertEqual(resources.analysisProvider.id, overrideProvider.id)
        XCTAssertEqual(resources.executionProvider.id, overrideProvider.id)
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
