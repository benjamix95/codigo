import Foundation

extension ReviewRuntimeAdapter {
    func runFixStage(step: ReviewPipelineRustStep, sessionId: String) async -> ReviewPipelineRustCallbackResult {
        let tempState = CodeReviewSessionState(sessionId: sessionId)
        let scope = CodeReviewMultiSwarmProvider.ReviewFileScope(rawValue: step.resolvedScope ?? "uncommitted") ?? .uncommitted
        let success = await ReviewPipelineCoordinator.shared.runPipelineFixStage(
            tasks: step.tasks.map(\.reviewTask),
            context: context,
            executionProvider: executionProvider,
            config: config,
            againstRef: step.againstRef,
            resolvedScope: scope,
            fileLockCoordinator: fileLockCoordinator,
            round: step.round ?? 1,
            sessionState: tempState,
            continuation: continuation,
            isCancelled: isCancelled,
            waitWhilePaused: waitWhilePaused
        )
        let snapshot = await tempState.snapshot()
        return ReviewPipelineRustCallbackResult(
            kind: "run_fix_stage",
            events: snapshot.events,
            error: success ? nil : snapshot.lastError ?? "Review fix stage failed."
        )
    }

    func runTests(sessionId: String) async -> ReviewPipelineRustCallbackResult {
        let tempState = CodeReviewSessionState(sessionId: sessionId)
        await tempState.markTestingStarted()
        let result = await CodeReviewMultiSwarmProvider.runTests(
            context: context,
            executionProvider: executionProvider,
            continuation: continuation,
            execController: execController,
            isCancelled: isCancelled,
            waitWhilePaused: waitWhilePaused
        )
        switch result {
        case .passed:
            await tempState.markTestResult(.passed, detail: "Tests passed")
            return ReviewPipelineRustCallbackResult(kind: "run_tests", events: await tempState.snapshot().events, testStatus: ReviewSessionTestStatus.passed.rawValue)
        case .failed:
            await tempState.markTestResult(.failed, detail: "Tests failed")
            return ReviewPipelineRustCallbackResult(kind: "run_tests", events: await tempState.snapshot().events, testStatus: ReviewSessionTestStatus.failed.rawValue)
        case .inconclusive(let reason):
            await tempState.markTestResult(.inconclusive, detail: reason)
            return ReviewPipelineRustCallbackResult(kind: "run_tests", events: await tempState.snapshot().events, testStatus: ReviewSessionTestStatus.inconclusive.rawValue, detail: reason)
        }
    }

    func scanModifiedFiles() -> ReviewPipelineRustCallbackResult {
        let files = WorkspaceScanner.listUncommittedSourceFiles(
            workspacePath: context.workspacePath,
            excludedPaths: context.excludedPaths
        )
        return ReviewPipelineRustCallbackResult(kind: "scan_modified_files", files: files)
    }

    func runReReview(step: ReviewPipelineRustStep) async -> ReviewPipelineRustCallbackResult {
        let outcome = await CodeReviewMultiSwarmProvider.runReReviewPhase(
            modifiedFiles: step.files,
            round: step.round ?? 1,
            context: context,
            analysisProvider: analysisProvider,
            maxWorkers: step.maxWorkers ?? config.maxWorkers,
            continuation: continuation,
            isCancelled: isCancelled,
            waitWhilePaused: waitWhilePaused
        )
        return ReviewPipelineRustCallbackResult(
            kind: "request_rereview_stream",
            files: step.files,
            text: outcome.text
        )
    }

    func prepareVerifiedPatches(
        step: ReviewPipelineRustStep,
        sessionId: String
    ) async -> ReviewPipelineRustCallbackResult {
        guard let prepareVerifiedPatches else {
            return ReviewPipelineRustCallbackResult(
                kind: "prepare_verified_patches",
                error: "No patch preparation runtime is available for the review pipeline."
            )
        }
        let current = await sessionState.snapshot()
        let workspaceRoot = context.workspacePath.path
        continuation.yield(.textDelta("\n### Patch Preparation\n\n"))
        do {
            let updated = try await prepareVerifiedPatches(
                current,
                step.findingIds,
                workspaceRoot
            )
            let newEvents = Array(updated.events.dropFirst(current.events.count))
            return ReviewPipelineRustCallbackResult(
                kind: "prepare_verified_patches",
                findings: updated.findings,
                patches: updated.patches,
                events: newEvents
            )
        } catch {
            return ReviewPipelineRustCallbackResult(
                kind: "prepare_verified_patches",
                error: error.localizedDescription
            )
        }
    }
}
