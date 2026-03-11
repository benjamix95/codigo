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
        let candidates = findings.map {
            ReviewCandidateVerificationService.candidate(from: $0, signalType: .pattern)
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
        let candidates = await step.tasks.asyncMap { task in
            await ReviewPipelineCoordinator.shared.reviewCandidate(
                from: task.reviewTask,
                prefix: "r\(step.round ?? 0)-"
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
