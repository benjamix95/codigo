import Foundation

extension CodeReviewMultiSwarmProvider {
    // MARK: - Phase 3: Parallel Fix

    /// Runs fix workers in parallel with file-lock coordination.
    /// Card lifecycle events (started/completed) are emitted immediately for live UI.
    /// Text output is serialized: collected per-worker then emitted sequentially for linear chat.
    static func runParallelFixPhase(
        tasks: [ReviewTask],
        context: WorkspaceContext,
        executionProvider: any LLMProvider,
        fileLockCoordinator: FileLockCoordinator,
        continuation: AsyncThrowingStream<StreamEvent, Error>.Continuation,
        isCancelled: @Sendable @escaping () -> Bool,
        waitWhilePaused: @Sendable @escaping () async -> Void
    ) async {
        guard !tasks.isEmpty else { return }

        continuation.yield(.textDelta("Launching \(tasks.count) parallel worker(s)...\n\n"))
        for task in tasks {
            continuation.yield(.raw(type: "agent", payload: [
                "title": task.description,
                "detail": "started",
                "swarm_id": task.id,
                "group_id": "swarm-\(task.id)"
            ]))
        }

        let workerResults: [(taskId: String, events: [StreamEvent])] = await withTaskGroup(
            of: (String, [StreamEvent]).self,
            returning: [(String, [StreamEvent])].self
        ) { group in
            for task in tasks {
                group.addTask {
                    if isCancelled() {
                        continuation.yield(.raw(type: "agent", payload: [
                            "title": task.description,
                            "detail": "completed",
                            "swarm_id": task.id,
                            "group_id": "swarm-\(task.id)"
                        ]))
                        return (task.id, [])
                    }

                    let taskFiles = Set(task.files)
                    let acquired = await fileLockCoordinator.acquireLock(
                        files: taskFiles,
                        swarmId: task.id,
                        isCancelled: isCancelled
                    )

                    guard acquired else {
                        continuation.yield(.raw(type: "agent", payload: [
                            "title": task.description,
                            "detail": "failed",
                            "status": "failed",
                            "swarm_id": task.id,
                            "group_id": "swarm-\(task.id)"
                        ]))
                        return (task.id, [.textDelta("\n**Worker \(task.id) skipped:** could not acquire file locks.\n")])
                    }



                    var collected: [StreamEvent] = []
                    var workerDidError = false
                    let scopedContext = WorkspaceContext(
                        workspacePaths: context.workspacePaths,
                        isNamedWorkspace: context.isNamedWorkspace,
                        workspaceName: context.workspaceName,
                        excludedPaths: context.excludedPaths,
                        includedPaths: task.files,
                        openFiles: context.openFiles,
                        activeSelection: context.activeSelection,
                        activeFilePath: context.activeFilePath,
                        activeRootPath: context.activeRootPath
                    )

                    let fixPrompt = """
                    You are a code fixer. Apply targeted fixes to the following files.

                    ## Task
                    \(task.description)

                    ## Severity
                    \(task.severity)

                    ## Files in Scope
                    \(task.files.joined(separator: "\n"))

                    ## Instructions
                    - Fix all issues identified for these files
                    - Make minimal, targeted changes — do not refactor beyond what is needed
                    - Preserve existing code style and conventions
                    - Do NOT modify files outside your scope
                    """

                    do {
                        let stream = try await executionProvider.send(
                            prompt: fixPrompt,
                            context: scopedContext,
                            imageURLs: nil
                        )
                        for try await event in stream {
                            await waitWhilePaused()
                            if isCancelled() { break }
                            switch event {
                            case .raw(let type, var payload):
                                payload["swarm_id"] = task.id
                                payload["group_id"] = "swarm-\(task.id)"
                                continuation.yield(.raw(type: type, payload: payload))
                            default:
                                collected.append(event)
                            }
                        }
                    } catch {
                        workerDidError = true
                        collected.append(.textDelta("\n**Worker \(task.id) error:** \(error.localizedDescription)\n"))
                    }

                    await fileLockCoordinator.releaseAllLocks(swarmId: task.id)

                    let finalDetail = workerDidError ? "failed" : "completed"
                    var finalPayload: [String: String] = [
                        "title": task.description,
                        "detail": finalDetail,
                        "swarm_id": task.id,
                        "group_id": "swarm-\(task.id)"
                    ]
                    if workerDidError { finalPayload["status"] = "failed" }
                    continuation.yield(.raw(type: "agent", payload: finalPayload))

                    return (task.id, collected)
                }
            }

            var results: [(String, [StreamEvent])] = []
            for await result in group {
                results.append(result)
            }
            return results
        }

        let sorted = workerResults.sorted {
            $0.taskId.localizedStandardCompare($1.taskId) == .orderedAscending
        }
        for (taskId, events) in sorted {
            await waitWhilePaused()
            if isCancelled() { break }
            continuation.yield(.textDelta("\n#### Worker \(taskId)\n\n"))
            for event in events {
                continuation.yield(event)
            }
        }
    }

    // MARK: - Phase 5: Re-Review

    static func runReReviewPhase(
        modifiedFiles: [String],
        round: Int,
        context: WorkspaceContext,
        analysisProvider: any LLMProvider,
        maxWorkers: Int,
        continuation: AsyncThrowingStream<StreamEvent, Error>.Continuation,
        isCancelled: @Sendable @escaping () -> Bool,
        waitWhilePaused: @Sendable @escaping () async -> Void
    ) async -> ReReviewOutcome {
        let reReviewContext = WorkspaceContext(
            workspacePaths: context.workspacePaths,
            isNamedWorkspace: context.isNamedWorkspace,
            workspaceName: context.workspaceName,
            excludedPaths: context.excludedPaths,
            includedPaths: modifiedFiles,
            openFiles: context.openFiles,
            activeSelection: context.activeSelection,
            activeFilePath: context.activeFilePath,
            activeRootPath: context.activeRootPath
        )

        let reReviewPrompt = """
        You are a code reviewer performing re-review round \(round).

        ## Files to Re-Review
        \(modifiedFiles.joined(separator: "\n"))

        ## Instructions
        These files were modified by a previous fix phase. Check:
        1. Were the original issues properly fixed?
        2. Did the fixes introduce any new bugs or regressions?
        3. Is the code clean and well-structured after the fixes?

        If everything looks good, respond with: "No issues found."

        Otherwise, list remaining issues and at the end output a JSON task block:
        ```json
        [
          {
            "id": "review-0",
            "description": "Brief description of what to fix",
            "files": ["path/to/file.swift"],
            "severity": "critical"
          }
        ]
        ```
        Maximum \(maxWorkers) tasks. Group related fixes together.
        """

        var accumulator = CodeReviewStreamTextAccumulator()
        do {
            let stream = try await analysisProvider.send(
                prompt: reReviewPrompt,
                context: reReviewContext,
                imageURLs: nil
            )
            for try await event in stream {
                await waitWhilePaused()
                if isCancelled() { break }
                continuation.yield(event)
                accumulator.consume(event)
            }
        } catch {
            let partialText = accumulator.text
            continuation.yield(.textDelta("\n**Re-review error:** \(error.localizedDescription)\n"))
            return ReReviewOutcome(
                text: partialText,
                findings: .inconclusive(reason: "Re-review stream failed: \(error.localizedDescription)")
            )
        }

        let fullText = accumulator.text
        let findings = findingsContainIssues(fullText)
        switch findings {
        case .issues:
            return ReReviewOutcome(text: fullText, findings: .issues)
        case .clean:
            return ReReviewOutcome(text: fullText, findings: .clean)
        case .inconclusive(let reason):
            return ReReviewOutcome(text: fullText, findings: .inconclusive(reason: reason))
        }
    }
}
