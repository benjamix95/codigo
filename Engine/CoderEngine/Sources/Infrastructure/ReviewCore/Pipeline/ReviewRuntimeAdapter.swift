import Foundation

struct ReviewRuntimeAdapter {
    let context: WorkspaceContext
    let config: MultiSwarmReviewConfig
    let analysisProvider: any LLMProvider
    let executionProvider: any LLMProvider
    let prepareVerifiedPatches: ReviewPatchPreparationRuntime?
    let execController: ExecutionController?
    let fileLockCoordinator: FileLockCoordinator
    let sessionState: CodeReviewSessionState
    let continuation: AsyncThrowingStream<StreamEvent, Error>.Continuation

    func resolveScopeFiles(
        resolvedScope: String?,
        againstRef: String?
    ) -> ReviewPipelineRustCallbackResult {
        let scope = CodeReviewMultiSwarmProvider.ReviewFileScope(rawValue: resolvedScope ?? "uncommitted") ?? .uncommitted
        if let againstRef {
            guard CodeReviewMultiSwarmProvider.isValidAgainstRefFormat(againstRef) else {
                continuation.yield(.textReplace("Invalid AGAINST ref `\(againstRef)`.\n"))
                return ReviewPipelineRustCallbackResult(kind: "resolve_scope_files")
            }
            let (files, error) = CodeReviewMultiSwarmProvider.gitDiffFiles(
                ref: againstRef,
                workspacePath: context.workspacePath,
                excludedPaths: context.excludedPaths
            )
            if files.isEmpty {
                let message = ReviewPipelineCoordinator.noFilesAgainstRefMessage(
                    againstRef: againstRef,
                    normalizedInput: CodeReviewMultiSwarmProvider.normalizedAgainstRefInput(againstRef),
                    currentHeadRevision: currentHEADRevision(),
                    error: error
                )
                continuation.yield(.textReplace(message + "\n"))
            }
            return ReviewPipelineRustCallbackResult(kind: "resolve_scope_files", files: files)
        }

        let files = CodeReviewMultiSwarmProvider.resolveFiles(context: context, scope: scope)
        if files.isEmpty {
            let message = switch scope {
            case .staged: "No staged source files found.\n"
            case .workspace: "No workspace source files found.\n"
            case .uncommitted: "No uncommitted source files found.\n"
            }
            continuation.yield(.textReplace(message))
        }
        return ReviewPipelineRustCallbackResult(kind: "resolve_scope_files", files: files)
    }

    func runAuditStage(files: [String], sessionId: String) async -> ReviewPipelineRustCallbackResult {
        let tempState = CodeReviewSessionState(sessionId: sessionId)
        let findings = await ReviewPipelineCoordinator.shared.runAuditStage(
            filesToReview: files,
            workspacePath: context.workspacePath,
            sessionState: tempState,
            continuation: continuation
        )
        let candidates = findings.compactMap {
            ReviewCandidateVerificationService.candidate(from: $0, signalType: .pattern)
        }
        guard candidates.count == findings.count else {
            return ReviewPipelineRustCallbackResult(
                kind: "run_audit_stage",
                error: "Rust review candidate builder unavailable for audit findings."
            )
        }
        if !candidates.isEmpty {
            await tempState.addCandidates(candidates)
            await ReviewPipelineCoordinator.shared.verifyCandidates(
                candidates,
                workspacePath: context.workspacePath,
                filesToReview: files,
                sessionState: tempState
            )
        }
        let snapshot = await tempState.snapshot()
        return ReviewPipelineRustCallbackResult(
            kind: "run_audit_stage",
            findings: findings,
            candidates: snapshot.candidates,
            promotedFindings: snapshot.findings,
            events: snapshot.events,
            audit: snapshot.audit
        )
    }

    func runAnalysis(step: ReviewPipelineRustStep) async -> ReviewPipelineRustCallbackResult {
        do {
            let text = try await CodeReviewMultiSwarmProvider.runAnalysisPhase(
                cleanPrompt: step.cleanPrompt ?? "Review all changes",
                scopeDescription: step.scopeDescription ?? "Uncommitted changes",
                step.files,
                step.maxWorkers ?? config.maxWorkers,
                context: context,
                analysisProvider: analysisProvider,
                continuation: continuation,
                isCancelled: isCancelled,
                waitWhilePaused: waitWhilePaused
            )
            return ReviewPipelineRustCallbackResult(kind: "request_analysis_stream", text: text)
        } catch {
            return ReviewPipelineRustCallbackResult(
                kind: "request_analysis_stream",
                error: error.localizedDescription
            )
        }
    }

    func prepareTaskCandidates(step: ReviewPipelineRustStep, sessionId: String) async -> ReviewPipelineRustCallbackResult {
        let tempState = CodeReviewSessionState(sessionId: sessionId)
        let rawCandidates = await step.tasks.asyncMap { task in
            await ReviewPipelineCoordinator.shared.reviewCandidate(
                from: task.reviewTask,
                prefix: "r\(step.round ?? 0)-"
            )
        }
        let candidates = rawCandidates.compactMap { $0 }
        guard candidates.count == step.tasks.count else {
            return ReviewPipelineRustCallbackResult(
                kind: "prepare_task_candidates",
                error: "Rust review candidate builder unavailable for task candidates."
            )
        }
        if !candidates.isEmpty {
            await tempState.addCandidates(candidates)
            await ReviewPipelineCoordinator.shared.verifyCandidates(
                candidates,
                workspacePath: context.workspacePath,
                filesToReview: step.files,
                sessionState: tempState
            )
        }
        let snapshot = await tempState.snapshot()
        return ReviewPipelineRustCallbackResult(
            kind: "prepare_task_candidates",
            candidates: snapshot.candidates,
            promotedFindings: snapshot.findings,
            events: snapshot.events
        )
    }

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
        let result = await CodeReviewMultiSwarmProvider.runTests(
            context: context,
            executionProvider: executionProvider,
            continuation: continuation,
            execController: execController,
            isCancelled: isCancelled,
            waitWhilePaused: waitWhilePaused
        )
        let request: ReviewRuntimeRustTestsReductionRequest
        switch result {
        case .passed:
            request = ReviewRuntimeRustTestsReductionRequest(
                schemaVersion: 1,
                result: "passed",
                detail: "Tests passed"
            )
        case .failed:
            request = ReviewRuntimeRustTestsReductionRequest(
                schemaVersion: 1,
                result: "failed",
                detail: "Tests failed"
            )
        case .inconclusive(let reason):
            request = ReviewRuntimeRustTestsReductionRequest(
                schemaVersion: 1,
                result: "inconclusive",
                detail: reason
            )
        }
        guard let response: ReviewRuntimeRustReductionResponse = ReviewCoreBridge.call(
            functionName: "review_core_runtime_reduce_tests",
            request: request
        ), response.error == nil, let callback = response.callback else {
            return ReviewPipelineRustCallbackResult(
                kind: "run_tests",
                error: "Rust review runtime tests reducer unavailable."
            )
        }
        return callback
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
            let request = ReviewRuntimeRustPatchReductionRequest(
                schemaVersion: 1,
                currentSnapshot: current,
                updatedSnapshot: updated
            )
            guard let response: ReviewRuntimeRustReductionResponse = ReviewCoreBridge.call(
                functionName: "review_core_runtime_reduce_prepare_verified_patches",
                request: request
            ), response.error == nil, let callback = response.callback else {
                return ReviewPipelineRustCallbackResult(
                    kind: "prepare_verified_patches",
                    error: "Rust review runtime patch reducer unavailable."
                )
            }
            return callback
        } catch {
            return ReviewPipelineRustCallbackResult(
                kind: "prepare_verified_patches",
                error: error.localizedDescription
            )
        }
    }

    private func currentHEADRevision() -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["rev-parse", "HEAD"]
        process.currentDirectoryURL = context.workspacePath
        let stdout = Pipe()
        process.standardOutput = stdout
        process.standardError = Pipe()
        do {
            try process.run()
        } catch {
            return nil
        }
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var isCancelled: @Sendable () -> Bool {
        { Task.isCancelled || execController?.swarmStopRequested == true }
    }

    var waitWhilePaused: @Sendable () async -> Void {
        {
            while execController?.swarmPauseRequested == true {
                if Task.isCancelled || execController?.swarmStopRequested == true { break }
                try? await Task.sleep(nanoseconds: 120_000_000)
            }
        }
    }
}

private struct ReviewRuntimeRustTestsReductionRequest: Encodable {
    let schemaVersion: Int
    let result: String
    let detail: String?
}

private struct ReviewRuntimeRustPatchReductionRequest: Encodable {
    let schemaVersion: Int
    let currentSnapshot: CodeReviewSessionSnapshot
    let updatedSnapshot: CodeReviewSessionSnapshot
}

private struct ReviewRuntimeRustReductionResponse: Decodable {
    let error: ReviewRuntimeRustReductionError?
    let callback: ReviewPipelineRustCallbackResult?
}

private struct ReviewRuntimeRustReductionError: Decodable {
    let code: String
    let message: String
}

private extension Array {
    func asyncMap<T>(
        _ transform: (Element) async -> T
    ) async -> [T] {
        var results: [T] = []
        for element in self {
            results.append(await transform(element))
        }
        return results
    }
}
