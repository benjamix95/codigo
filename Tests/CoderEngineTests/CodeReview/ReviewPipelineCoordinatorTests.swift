import XCTest
@testable import CoderEngine

final class ReviewPipelineCoordinatorTests: XCTestCase {
    override func setUpWithError() throws {
        try super.setUpWithError()
        let path = reviewCoreLibraryPathForCodeReviewTests(from: #filePath)
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

    func testPlanFixStageUsesRustBatchPlannerAndAgainstRefScope() async throws {
        guard ReviewCoreBridge.loadedState().loaded else {
            throw XCTSkip("Rust review core non disponibile in ambiente.")
        }

        let tasks = [
            CodeReviewMultiSwarmProvider.ReviewTask(
                id: "task-1",
                description: "Fix A",
                files: ["A.swift"],
                severity: "warning",
                category: nil,
                lineNumber: nil,
                endLineNumber: nil,
                origin: .reviewer,
                confidence: nil,
                evidence: nil,
                expectedInvariant: nil,
                reproOrReasoning: nil,
                sourceTool: nil,
                blocking: nil
            ),
            CodeReviewMultiSwarmProvider.ReviewTask(
                id: "task-2",
                description: "Fix B",
                files: ["A.swift", "B.swift"],
                severity: "critical",
                category: nil,
                lineNumber: nil,
                endLineNumber: nil,
                origin: .reviewer,
                confidence: nil,
                evidence: nil,
                expectedInvariant: nil,
                reproOrReasoning: nil,
                sourceTool: nil,
                blocking: true
            ),
            CodeReviewMultiSwarmProvider.ReviewTask(
                id: "task-3",
                description: "Fix C",
                files: ["C.swift"],
                severity: "warning",
                category: nil,
                lineNumber: nil,
                endLineNumber: nil,
                origin: .reviewer,
                confidence: nil,
                evidence: nil,
                expectedInvariant: nil,
                reproOrReasoning: nil,
                sourceTool: nil,
                blocking: nil
            ),
        ]

        let plan = await ReviewPipelineCoordinator.shared.planFixStage(
            tasks: tasks,
            againstRef: "HEAD~1",
            resolvedScope: .staged,
            sessionId: "session-fix-stage"
        )

        XCTAssertEqual(plan?.pipelineScope, .againstRef)
        XCTAssertEqual(plan?.taskBatches.count, 2)
        XCTAssertEqual(plan?.taskBatches.first?.map(\.id), ["task-1", "task-3"])
        XCTAssertEqual(plan?.taskBatches.last?.map(\.id), ["task-2"])
    }

    func testBridgedPipelineEventsUsesRustPayloadShapeForTaskFailure() async throws {
        guard ReviewCoreBridge.loadedState().loaded else {
            throw XCTSkip("Rust review core non disponibile in ambiente.")
        }

        let event = PipelineUIEvent.taskFailed(
            TaskFailedPayload(jobId: "job-1", taskId: "task-9", error: "boom")
        )
        let bridged = await ReviewPipelineCoordinator.shared.bridgedPipelineEvents(
            event,
            sessionId: "session-bridge"
        )

        XCTAssertEqual(bridged.count, 2)
        guard case .raw(let type, let payload) = bridged[0] else {
            return XCTFail("Expected raw bridged event")
        }
        XCTAssertEqual(type, "agent")
        XCTAssertEqual(payload["group_id"], "review-session-bridge-task-9")
        XCTAssertEqual(payload["status"], "failed")

        guard case .textDelta(let delta) = bridged[1] else {
            return XCTFail("Expected text delta failure tail")
        }
        XCTAssertEqual(delta, "\n[Task task-9 failed: boom]\n")
    }

    func testCandidateFromFindingUsesRustCanonicalFallbackFields() throws {
        guard ReviewCoreBridge.loadedState().loaded else {
            throw XCTSkip("Rust review core non disponibile in ambiente.")
        }

        let finding = CodeReviewFinding(
            id: "finding-1",
            severity: .warning,
            category: .correctness,
            origin: .reviewer,
            filePath: "File.swift",
            message: "message",
            suggestedFix: "fix me",
            verificationReport: "expected invariant"
        )

        let candidate = try XCTUnwrap(
            ReviewCandidateVerificationService.candidate(from: finding, signalType: .pattern)
        )
        XCTAssertEqual(candidate.expectedInvariant, "expected invariant")
        XCTAssertEqual(candidate.reproOrReasoning, "fix me")
        XCTAssertEqual(candidate.signalType, .pattern)
    }

    func testReviewCandidateFromTaskUsesRustCanonicalDerivation() async throws {
        guard ReviewCoreBridge.loadedState().loaded else {
            throw XCTSkip("Rust review core non disponibile in ambiente.")
        }

        let task = CodeReviewMultiSwarmProvider.ReviewTask(
            id: "task-1",
            description: "Security vulnerability in auth flow",
            files: ["Auth.swift"],
            severity: "high",
            category: nil,
            lineNumber: 10,
            endLineNumber: nil,
            origin: .auditTool,
            confidence: 0.9,
            evidence: "token",
            expectedInvariant: nil,
            reproOrReasoning: nil,
            sourceTool: "audit_security_dataflow",
            blocking: true
        )

        let runtimeCandidate = await ReviewPipelineCoordinator.shared.reviewCandidate(
            from: task,
            prefix: "r1-"
        )
        let candidate = try XCTUnwrap(runtimeCandidate)
        XCTAssertEqual(candidate.id, "r1-task-1")
        XCTAssertEqual(candidate.severity, .critical)
        XCTAssertEqual(candidate.category, .security)
        XCTAssertEqual(candidate.signalType, .pattern)
        XCTAssertEqual(candidate.filePath, "Auth.swift")
    }

    func testRunAuditStageUsesRustReductionForCandidatesAndAuditSnapshot() async throws {
        guard ReviewCoreBridge.loadedState().loaded else {
            throw XCTSkip("Rust review core non disponibile in ambiente.")
        }

        let workspacePath = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(
            at: workspacePath,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: workspacePath) }

        try """
        let input = request.query["cmd"]
        runProcess(input, shell: true)
        """.write(
            to: workspacePath.appendingPathComponent("Service.swift"),
            atomically: true,
            encoding: .utf8
        )

        var capturedContinuation: AsyncThrowingStream<StreamEvent, Error>.Continuation?
        _ = AsyncThrowingStream<StreamEvent, Error> { continuation in
            capturedContinuation = continuation
        }
        let continuation = try XCTUnwrap(capturedContinuation)

        let adapter = ReviewRuntimeAdapter(
            context: WorkspaceContext(workspacePath: workspacePath),
            config: MultiSwarmReviewConfig(maxWorkers: 1, enabledPhases: .analysisOnly, maxReviewRounds: 1),
            analysisProvider: SilentLLMProvider(),
            executionProvider: SilentLLMProvider(),
            prepareVerifiedPatches: nil,
            execController: nil,
            fileLockCoordinator: FileLockCoordinator(),
            sessionState: CodeReviewSessionState(sessionId: "session-audit-runtime"),
            continuation: continuation
        )

        let result = await adapter.runAuditStage(
            files: ["Service.swift"],
            sessionId: "session-audit-runtime"
        )

        XCTAssertEqual(result.kind, "run_audit_stage")
        XCTAssertFalse(result.candidates.isEmpty)
        XCTAssertFalse(result.promotedFindings.isEmpty)
        XCTAssertEqual(result.audit?.toolCoverage[ReviewAuditToolName.securityDataflow], true)
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
