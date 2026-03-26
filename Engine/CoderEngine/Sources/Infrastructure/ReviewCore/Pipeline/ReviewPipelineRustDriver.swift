import Foundation

struct ReviewPipelineRustDriver {
    let prompt: String
    let context: WorkspaceContext
    let config: MultiSwarmReviewConfig
    let analysisProvider: any LLMProvider
    let executionProvider: any LLMProvider
    let runtimeResolver: CodeReviewRuntimeResolver?
    let execController: ExecutionController?
    let fileLockCoordinator: FileLockCoordinator
    let sessionState: CodeReviewSessionState
    let continuation: AsyncThrowingStream<StreamEvent, Error>.Continuation

    func run() async throws {
        execController?.beginScope(.review)
        defer { execController?.endScope(.review) }
        execController?.clearSwarmStopRequested()
        execController?.clearSwarmPauseRequested()
        continuation.yield(.started)

        let sessionConfig = await sessionState.snapshot().config
        let runtimeResources = runtimeResolver?(sessionConfig)
            ?? CodeReviewRuntimeResources(
                config: config,
                analysisProvider: analysisProvider,
                executionProvider: executionProvider
            )

        let initialSnapshot = await sessionState.snapshot()
        let request = ReviewPipelineRustStartRequest(
            schemaVersion: 1,
            sessionId: initialSnapshot.sessionId,
            conversationId: initialSnapshot.conversationId?.uuidString.lowercased(),
            prompt: prompt,
            workspacePath: context.workspacePath.path,
            config: ReviewPipelineRustConfig(config: runtimeResources.config)
        )
        guard var response: ReviewPipelineRustResponse = ReviewCoreBridge.call(
            functionName: "review_core_run_pipeline",
            request: request
        ) else {
            throw CodeReviewMultiSwarmProvider.ReviewPipelineError.analysisTransportFailed("Rust review pipeline unavailable.")
        }
        await sessionState.replaceCanonicalSnapshot(response.snapshot)
        let adapter = ReviewRuntimeAdapter(
            context: context,
            config: runtimeResources.config,
            analysisProvider: runtimeResources.analysisProvider,
            executionProvider: runtimeResources.executionProvider,
            prepareVerifiedPatches: runtimeResources.prepareVerifiedPatches,
            execController: execController,
            fileLockCoordinator: fileLockCoordinator,
            sessionState: sessionState,
            continuation: continuation
        )

        while true {
            switch response.step.kind {
            case "resolve_scope_files":
                response = try await apply(
                    sessionId: response.sessionId,
                    result: adapter.resolveScopeFiles(
                        resolvedScope: response.step.resolvedScope,
                        againstRef: response.step.againstRef
                    ),
                    sessionState: sessionState
                )
            case "run_audit_stage":
                response = try await apply(
                    sessionId: response.sessionId,
                    result: await adapter.runAuditStage(files: response.step.files, sessionId: response.sessionId),
                    sessionState: sessionState
                )
            case "request_analysis_stream":
                response = try await apply(
                    sessionId: response.sessionId,
                    result: await adapter.runAnalysis(step: response.step),
                    sessionState: sessionState
                )
            case "prepare_task_candidates":
                response = try await apply(
                    sessionId: response.sessionId,
                    result: await adapter.prepareTaskCandidates(step: response.step, sessionId: response.sessionId),
                    sessionState: sessionState
                )
            case "run_fix_stage":
                response = try await apply(
                    sessionId: response.sessionId,
                    result: await adapter.runFixStage(step: response.step, sessionId: response.sessionId),
                    sessionState: sessionState
                )
            case "run_tests":
                response = try await apply(
                    sessionId: response.sessionId,
                    result: await adapter.runTests(sessionId: response.sessionId),
                    sessionState: sessionState
                )
            case "scan_modified_files":
                response = try await apply(
                    sessionId: response.sessionId,
                    result: adapter.scanModifiedFiles(),
                    sessionState: sessionState
                )
            case "request_rereview_stream":
                response = try await apply(
                    sessionId: response.sessionId,
                    result: await adapter.runReReview(step: response.step),
                    sessionState: sessionState
                )
            case "prepare_verified_patches":
                response = try await apply(
                    sessionId: response.sessionId,
                    result: await adapter.prepareVerifiedPatches(step: response.step, sessionId: response.sessionId),
                    sessionState: sessionState
                )
            case "completed":
                if let message = response.step.message, !message.isEmpty {
                    continuation.yield(.textDelta(message))
                }
                continuation.yield(.completed)
                continuation.finish()
                return
            case "failed":
                let trimmed = response.step.reason?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let message = trimmed.isEmpty ? "Review failed." : trimmed
                continuation.yield(.textDelta("\n**\(message)**\n"))
                continuation.yield(.error(message))
                continuation.yield(.completed)
                continuation.finish()
                return
            default:
                let message = "Unsupported review pipeline step: \(response.step.kind)"
                continuation.yield(.textDelta("\n**\(message)**\n"))
                continuation.yield(.error(message))
                continuation.yield(.completed)
                continuation.finish()
                return
            }
        }
    }

    private func apply(
        sessionId: String,
        result: ReviewPipelineRustCallbackResult,
        sessionState: CodeReviewSessionState
    ) async throws -> ReviewPipelineRustResponse {
        let request = ReviewPipelineRustApplyRequest(
            schemaVersion: 1,
            sessionId: sessionId,
            callback: result
        )
        guard let response: ReviewPipelineRustResponse = ReviewCoreBridge.call(
            functionName: "review_core_pipeline_apply_callback_result",
            request: request
        ) else {
            throw CodeReviewMultiSwarmProvider.ReviewPipelineError.analysisTransportFailed("Rust review pipeline callback failed.")
        }
        await sessionState.replaceCanonicalSnapshot(response.snapshot)
        return response
    }
}

extension CodeReviewMultiSwarmProvider {
    static func runReviewPipeline(
        prompt: String,
        context: WorkspaceContext,
        config: MultiSwarmReviewConfig,
        analysisProvider: any LLMProvider,
        executionProvider: any LLMProvider,
        execController: ExecutionController?,
        fileLockCoordinator: FileLockCoordinator,
        sessionState: CodeReviewSessionState,
        continuation: AsyncThrowingStream<StreamEvent, Error>.Continuation
    ) async throws {
        try await ReviewPipelineCoordinator.shared.run(
            prompt: prompt,
            context: context,
            config: config,
            analysisProvider: analysisProvider,
            executionProvider: executionProvider,
            runtimeResolver: nil,
            execController: execController,
            fileLockCoordinator: fileLockCoordinator,
            sessionState: sessionState,
            continuation: continuation
        )
    }

    static func runReviewPipelineOrchestrated(
        prompt: String,
        context: WorkspaceContext,
        config: MultiSwarmReviewConfig,
        analysisProvider: any LLMProvider,
        executionProvider: any LLMProvider,
        execController: ExecutionController?,
        fileLockCoordinator: FileLockCoordinator,
        sessionState: CodeReviewSessionState,
        continuation: AsyncThrowingStream<StreamEvent, Error>.Continuation
    ) async throws {
        try await runReviewPipeline(
            prompt: prompt,
            context: context,
            config: config,
            analysisProvider: analysisProvider,
            executionProvider: executionProvider,
            execController: execController,
            fileLockCoordinator: fileLockCoordinator,
            sessionState: sessionState,
            continuation: continuation
        )
    }
}
